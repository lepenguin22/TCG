import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../models/card_definition.dart';
import '../playtest_engine.dart';
import '../playtest_state.dart';
import 'playtest_host.dart';
import 'playtest_transport.dart';
import 'remote_board.dart';
import 'socket_transport.dart';
import 'wire_deck.dart';

/// How far along a two-player game is in getting started.
enum SessionStage {
  /// Opening a door, or knocking on one.
  connecting,

  /// The host is waiting for somebody to arrive.
  waiting,

  /// Both decks are in and the game is on.
  playing,

  /// The game is still there; the phone playing it is not, for the moment.
  reconnecting,

  /// It did not work, or it ended.
  closed,
}

/// The host's side of a game played across two devices.
///
/// The host runs the game. It also plays in it, over a pipe with nothing in
/// between, so both players are talking to the board the same way -- there is
/// no second path through the rules for the player who happens to own the
/// game.
class HostSession extends ChangeNotifier {
  HostSession({
    required this.gameId,
    required this.deck,
    this.crests = const [],
    this.turnOrder = TurnOrder.random,
    this.random,
  });

  /// The names the two seats play under. The host is Player 1 whoever they
  /// are, which is also what the log calls them.
  static const hostName = 'Player 1';
  static const guestName = 'Player 2';

  final String gameId;
  final WireDeck deck;
  final Iterable<CardDefinition> crests;
  final TurnOrder turnOrder;

  /// A fixed shuffle, for a test that wants the same game twice.
  final Random? random;

  SessionStage stage = SessionStage.connecting;
  String? failure;

  /// Where the other player should dial, once there is something to dial.
  List<String> addresses = const [];
  int? port;

  PlaytestServer? _server;
  PlaytestTransport? _guest;
  PlaytestHost? host;

  /// The host's own board, which is a guest of its own game.
  RemoteBoard? board;

  /// Whether the other player's phone is on the line right now.
  bool guestConnected = false;

  /// Opens the door and keeps it open.
  ///
  /// The first player through starts the game. Everybody after them is either
  /// that player coming back from a dropped connection -- which is what the
  /// token is for -- or somebody who has dialled the wrong phone, and is told
  /// so and shown out.
  Future<void> open({int port = PlaytestServer.defaultPort}) async {
    try {
      final server = await PlaytestServer.bind(port: port);
      _server = server;
      this.port = server.port;
      addresses = await PlaytestServer.addresses();
      stage = SessionStage.waiting;
      notifyListeners();

      _knocking = server.connections.listen(_answer);
    } on Object catch (error) {
      failure = '$error';
      stage = SessionStage.closed;
      notifyListeners();
    }
  }

  StreamSubscription<PlaytestTransport>? _knocking;

  /// Deals with somebody who has just dialled in.
  Future<void> welcome(PlaytestTransport transport) => _answer(transport);

  Future<void> _answer(PlaytestTransport transport) async {
    final hello = await transport.messages.firstWhere(
      (message) => message['type'] == 'deck' || message['type'] == 'resume',
      orElse: () => const {},
    );
    final game = host;

    if (hello['type'] == 'resume') {
      final seat = game?.state.opponent;
      if (game == null ||
          seat == null ||
          !game.holdsSeat(seat, hello['token'] as String?)) {
        transport.send({
          'type': 'refused',
          'reason': 'that is not a seat at this game',
        });
        await transport.close();
        return;
      }
      _guest = transport;
      game.seat(seat, transport);
      return;
    }

    if (game != null) {
      // A game is already on and this is not the player who left it.
      transport.send({
        'type': 'refused',
        'reason': 'this device is already in a game',
      });
      await transport.close();
      return;
    }
    await _start(transport, hello);
  }

  Future<void> _start(
    PlaytestTransport transport,
    Map<String, Object?> hello,
  ) async {
    _guest = transport;
    final theirDeck = WireDeck.fromJson(
      (hello['deck'] as Map? ?? const {}).cast<String, Object?>(),
    );

    final engine = PlaytestEngine.startFromItems(
      yourItems: deck.toItems(gameId),
      opponentItems: theirDeck.toItems(gameId),
      yourName: hostName,
      opponentName: guestName,
      crests: crests,
      turnOrder: turnOrder,
      random: random,
    );
    final game = PlaytestHost(engine)
      ..onSeatChanged = (side, connected) {
        if (side.name != guestName) return;
        guestConnected = connected;
        notifyListeners();
      };
    host = game;

    // The host's own seat: the same pipe as the guest's, minus the wire.
    final (mine, forMe) = LoopbackTransport.pair();
    board = RemoteBoard(transport: forMe, gameId: gameId);
    game
      ..seat(engine.state.you, mine)
      ..seat(engine.state.opponent, transport);

    guestConnected = true;
    stage = SessionStage.playing;
    notifyListeners();
  }

  Future<void> close() async {
    stage = SessionStage.closed;
    await _knocking?.cancel();
    await host?.close();
    await _guest?.close();
    await _server?.close();
    board?.dispose();
    board = null;
    notifyListeners();
  }
}

/// The guest's side: a board, and a pipe to the device holding the game.
///
/// The pipe is the part that breaks. A phone that walks out of range, or one
/// whose owner answered a call, loses the socket and not the game -- the game
/// is on the other device the whole time -- so this dials again, shows the
/// seat's token, and picks the board back up where it was.
class GuestSession extends ChangeNotifier {
  GuestSession({
    required this.gameId,
    required this.deck,
    this.retryAfter = const Duration(seconds: 2),
  });

  final String gameId;
  final WireDeck deck;

  /// How long to wait between knocks. Short: the usual cause is a phone that
  /// dropped off the Wi-Fi for a moment and is already back.
  final Duration retryAfter;

  SessionStage stage = SessionStage.connecting;
  String? failure;
  RemoteBoard? board;
  PlaytestTransport? _transport;

  /// Where the game is, so it can be dialled again.
  String? _address;
  int? _port;
  bool _closed = false;
  Timer? _retry;

  /// How many times the phone has dialled again without getting through.
  int attempts = 0;

  /// Dials the host and announces what this player brought.
  Future<void> join(
    String address, {
    int port = PlaytestServer.defaultPort,
  }) async {
    _address = address;
    _port = port;
    try {
      await connect(await SocketTransport.connect(address, port));
    } on Object catch (error) {
      failure = '$error';
      stage = SessionStage.closed;
      notifyListeners();
    }
  }

  /// The same, over a pipe that is already open.
  Future<void> connect(PlaytestTransport transport) async {
    _transport = transport;
    final remote = RemoteBoard(transport: transport, gameId: gameId)
      ..onLost = _lost;
    board = remote;
    transport.send({'type': 'deck', 'deck': deck.toJson()});
    stage = SessionStage.playing;
    notifyListeners();
  }

  void _lost() {
    if (_closed || _address == null) return;
    stage = SessionStage.reconnecting;
    notifyListeners();
    _retry = Timer(retryAfter, _dialAgain);
  }

  Future<void> _dialAgain() async {
    if (_closed) return;
    attempts += 1;
    notifyListeners();
    try {
      final pipe = await SocketTransport.connect(
        _address!,
        _port ?? PlaytestServer.defaultPort,
        timeout: const Duration(seconds: 5),
      );
      _transport = pipe;
      // The seat is claimed with the token the host handed out, so it goes
      // back to the player who left it rather than to whoever dials next.
      board?.resumeOn(pipe);
      attempts = 0;
      stage = SessionStage.playing;
      notifyListeners();
    } on Object {
      // Still out of reach. The game is not going anywhere; knock again.
      if (_closed) return;
      _retry = Timer(retryAfter, _dialAgain);
    }
  }

  Future<void> close() async {
    _closed = true;
    _retry?.cancel();
    stage = SessionStage.closed;
    board?.dispose();
    board = null;
    await _transport?.close();
    notifyListeners();
  }
}
