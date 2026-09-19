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

  /// Opens the door and waits for one player to come through.
  Future<void> open({int port = PlaytestServer.defaultPort}) async {
    try {
      final server = await PlaytestServer.bind(port: port);
      _server = server;
      this.port = server.port;
      addresses = await PlaytestServer.addresses();
      stage = SessionStage.waiting;
      notifyListeners();

      final guest = await server.waitForPlayer();
      await _welcome(guest);
    } on Object catch (error) {
      failure = '$error';
      stage = SessionStage.closed;
      notifyListeners();
    }
  }

  /// Seats a player who has arrived over [transport], once they say what
  /// they brought to play with.
  Future<void> welcome(PlaytestTransport transport) => _welcome(transport);

  Future<void> _welcome(PlaytestTransport transport) async {
    _guest = transport;
    final hello = await transport.messages.firstWhere(
      (message) => message['type'] == 'deck',
    );
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
    final game = PlaytestHost(engine);
    host = game;

    // The host's own seat: the same pipe as the guest's, minus the wire.
    final (mine, forMe) = LoopbackTransport.pair();
    board = RemoteBoard(transport: forMe, gameId: gameId);
    game
      ..seat(engine.state.you, mine)
      ..seat(engine.state.opponent, transport);

    stage = SessionStage.playing;
    notifyListeners();
  }

  Future<void> close() async {
    stage = SessionStage.closed;
    await host?.close();
    await _guest?.close();
    await _server?.close();
    board?.dispose();
    board = null;
    notifyListeners();
  }
}

/// The guest's side: a board, and a pipe to the device holding the game.
class GuestSession extends ChangeNotifier {
  GuestSession({required this.gameId, required this.deck});

  final String gameId;
  final WireDeck deck;

  SessionStage stage = SessionStage.connecting;
  String? failure;
  RemoteBoard? board;
  PlaytestTransport? _transport;

  /// Dials the host and announces what this player brought.
  Future<void> join(
    String address, {
    int port = PlaytestServer.defaultPort,
  }) async {
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
    final remote = RemoteBoard(transport: transport, gameId: gameId);
    board = remote;
    transport.send({'type': 'deck', 'deck': deck.toJson()});
    stage = SessionStage.playing;
    notifyListeners();
  }

  Future<void> close() async {
    stage = SessionStage.closed;
    board?.dispose();
    board = null;
    await _transport?.close();
    notifyListeners();
  }
}
