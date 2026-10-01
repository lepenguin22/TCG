import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tcg_decks/playtest/net/playtest_intent.dart';
import 'package:tcg_decks/playtest/net/socket_transport.dart';
import 'package:tcg_decks/playtest/net/two_player_session.dart';
import 'package:tcg_decks/playtest/net/wire_deck.dart';
import 'package:tcg_decks/playtest/playtest_state.dart';

import 'playtest_engine_test.dart' show buildDeck;

/// Waits until [done] is true, or gives up and lets the test say why.
///
/// A real socket delivers when the operating system says so, not after a
/// fixed number of turns round the event queue: pumping a set number of
/// times passes on a quiet machine and fails on a busy one, which is a test
/// that reports the weather rather than the code.
Future<void> until(bool Function() done) async {
  for (var i = 0; i < 600 && !done(); i += 1) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  test('a socket carries messages both ways', () async {
    final server = await PlaytestServer.bind(port: 0);
    final waiting = server.waitForPlayer();
    final dialled = await SocketTransport.connect('127.0.0.1', server.port);
    final host = await waiting;

    final heardByHost = <Map<String, Object?>>[];
    final heardByGuest = <Map<String, Object?>>[];
    host.messages.listen(heardByHost.add);
    dialled.messages.listen(heardByGuest.add);

    dialled.send({'type': 'hello', 'from': 'the guest'});
    host.send({'type': 'hello', 'from': 'the host'});
    await until(() => heardByHost.isNotEmpty && heardByGuest.isNotEmpty);

    expect(heardByHost.single['from'], 'the guest');
    expect(heardByGuest.single['from'], 'the host');
    await host.close();
    await dialled.close();
  });

  test('a message split across packets still arrives whole', () async {
    // TCP hands over whatever turned up, which is not the same as what was
    // sent: a long message can arrive in pieces and two short ones together.
    final server = await PlaytestServer.bind(port: 0);
    final waiting = server.waitForPlayer();
    final guest = await SocketTransport.connect('127.0.0.1', server.port);
    final host = await waiting;

    final heard = <Map<String, Object?>>[];
    host.messages.listen(heard.add);

    // A message with a lot in it, sent alongside a small one.
    final long = List.generate(400, (i) => 'card $i');
    guest.send({'type': 'deck', 'cards': long});
    guest.send({'type': 'ready'});
    await until(() => heard.length >= 2);

    expect(heard, hasLength(2));
    expect((heard.first['cards']! as List), hasLength(400));
    expect(heard.last['type'], 'ready');
    await host.close();
    await guest.close();
  });

  test('a line that is not a message does not take the game down', () async {
    final server = await PlaytestServer.bind(port: 0);
    final waiting = server.waitForPlayer();
    final guest = await SocketTransport.connect('127.0.0.1', server.port);
    final host = await waiting;

    final heard = <Map<String, Object?>>[];
    host.messages.listen(heard.add);

    guest.send({'type': 'first'});
    await until(() => heard.isNotEmpty);
    // Something that is not this protocol at all.
    await guest.close();

    expect(heard.single['type'], 'first');
    await host.close();
  });

  /// A game between two phones, over real sockets on this machine.
  Future<({HostSession host, GuestSession guest})> table({
    Duration retryAfter = const Duration(milliseconds: 50),
  }) async {
    final (store, myDeck) = await buildDeck();
    final (guestStore, theirDeck) = await buildDeck(name: 'Their deck');
    final host = HostSession(
      gameId: 'vanguard',
      deck: WireDeck.of(store.viewOf(myDeck)),
      turnOrder: TurnOrder.playerOneFirst,
      random: Random(7),
    );
    await host.open(port: 0);
    final guest = GuestSession(
      gameId: 'vanguard',
      deck: WireDeck.of(guestStore.viewOf(theirDeck)),
      retryAfter: retryAfter,
    );
    await guest.join('127.0.0.1', port: host.port!);
    await until(() => host.stage == SessionStage.playing);
    return (host: host, guest: guest);
  }

  test('a phone that drops off comes back to the same game', () async {
    // Long enough between redials that the board can be looked at while the
    // phone is away, and short enough that the test does not sit waiting.
    final game = await table(retryAfter: const Duration(milliseconds: 300));

    // Play far enough in that coming back to the start would be obvious.
    game.host.board!.ask(const PlaytestIntent(IntentKind.confirmMulligan));
    game.guest.board!.ask(const PlaytestIntent(IntentKind.confirmMulligan));
    await until(() => game.host.host!.state.phase != PlaytestPhase.mulligan);
    final riding = game.host.host!.state.you.rideDeck.firstWhere(
      (card) => card.grade == 1,
    );
    game.host.board!.ask(
      PlaytestIntent(IntentKind.ride, card: riding.instanceId),
    );
    await until(
      () =>
          game.guest.board!.snapshot!.them.units[Circle.vanguard]?.cardId ==
          riding.instanceId,
    );
    expect(game.guest.board!.snapshot!.turn, greaterThan(0));

    // The guest's Wi-Fi goes. The game does not.
    await game.guest.board!.transport.close();
    // Both ends have to notice, and they notice separately: waiting for one
    // and then asking the other is a race the busy machine wins.
    await until(
      () =>
          !game.host.guestConnected &&
          game.guest.stage == SessionStage.reconnecting,
    );
    expect(game.guest.stage, SessionStage.reconnecting);
    expect(game.host.guestConnected, isFalse);
    expect(
      game.host.host!.state.opponent.hand,
      isNotEmpty,
      reason: 'their hand is still on the table',
    );

    // It dials again by itself, and the board picks up where it was.
    await until(
      () =>
          game.guest.stage == SessionStage.playing && game.host.guestConnected,
    );
    expect(game.host.guestConnected, isTrue);
    expect(
      game.guest.board!.snapshot!.them.units[Circle.vanguard]!.cardId,
      riding.instanceId,
      reason: 'the ride that happened while it was away is there',
    );
    expect(game.guest.board!.live, isTrue);

    // And the seat plays on: the turn is passed to it, and a card is put
    // down from the phone that dropped.
    final engine = game.host.host!;
    while (engine.state.active != engine.state.opponent) {
      // One phase at a time, waiting for each to land: asking again before
      // the last one arrived would run the turn past where it was wanted.
      final phase = engine.state.phase;
      game.host.board!.ask(const PlaytestIntent(IntentKind.nextPhase));
      await until(
        () =>
            engine.state.phase != phase ||
            engine.state.active == engine.state.opponent,
      );
    }
    final before = engine.state.opponent.hand.length;
    game.guest.board!.ask(
      PlaytestIntent(
        IntentKind.discard,
        card: engine.state.opponent.hand.first.instanceId,
      ),
    );
    await until(() => engine.state.opponent.hand.length == before - 1);
    expect(engine.state.opponent.hand.length, before - 1);

    await game.guest.close();
    await game.host.close();
  });

  test('somebody else cannot take the seat', () async {
    final game = await table(retryAfter: const Duration(seconds: 30));
    game.host.board!.ask(const PlaytestIntent(IntentKind.confirmMulligan));
    game.guest.board!.ask(const PlaytestIntent(IntentKind.confirmMulligan));
    await until(() => game.host.host!.state.phase != PlaytestPhase.mulligan);

    // A third phone dials the host and asks for the seat without the token
    // the seat was given.
    final intruder = await SocketTransport.connect(
      '127.0.0.1',
      game.host.port!,
    );
    final heard = <Map<String, Object?>>[];
    intruder.messages.listen(heard.add);
    intruder.send({'type': 'resume', 'token': 'not-the-token'});
    await until(() => heard.isNotEmpty);

    expect(heard.single['type'], 'refused');
    expect(
      game.guest.board!.live,
      isTrue,
      reason: 'and the player in the seat was not thrown out of it',
    );

    // A phone that dials in wanting a game of its own is turned away too:
    // this device is already running one.
    final latecomer = await SocketTransport.connect(
      '127.0.0.1',
      game.host.port!,
    );
    final alsoHeard = <Map<String, Object?>>[];
    latecomer.messages.listen(alsoHeard.add);
    latecomer.send({'type': 'deck', 'deck': const <String, Object?>{}});
    await until(() => alsoHeard.isNotEmpty);
    expect(alsoHeard.single['reason'], contains('already in a game'));

    await intruder.close();
    await latecomer.close();
    await game.guest.close();
    await game.host.close();
  });

  test('two devices meet, swap decks and play', () async {
    final (store, myDeck) = await buildDeck();
    final (guestStore, theirDeck) = await buildDeck(name: 'Their deck');

    final host = HostSession(
      gameId: 'vanguard',
      deck: WireDeck.of(store.viewOf(myDeck)),
      turnOrder: TurnOrder.playerOneFirst,
      random: Random(7),
    );
    final opened = host.open(port: 0);
    // The address is offered as soon as there is one to offer.
    await until(() => host.port != null);
    expect(host.stage, SessionStage.waiting);

    final guest = GuestSession(
      gameId: 'vanguard',
      deck: WireDeck.of(guestStore.viewOf(theirDeck)),
    );
    await guest.join('127.0.0.1', port: host.port!);
    await opened;
    await until(
      () =>
          host.stage == SessionStage.playing && guest.board?.connected == true,
    );

    expect(host.stage, SessionStage.playing);
    expect(guest.board!.connected, isTrue, reason: 'the first board arrived');

    // Both are looking at the same game from their own seats.
    final mine = host.board!.snapshot!;
    final theirs = guest.board!.snapshot!;
    expect(mine.me.name, HostSession.hostName);
    expect(theirs.me.name, HostSession.guestName);
    expect(mine.me.handIds.length, 5);
    expect(theirs.me.handIds.length, 5);
    expect(
      theirs.them.handIds.any(theirs.knows),
      isFalse,
      reason: 'the host\'s hand stays on the host\'s phone',
    );

    // And a move made on one phone lands on the other.
    host.board!.ask(const PlaytestIntent(IntentKind.confirmMulligan));
    guest.board!.ask(const PlaytestIntent(IntentKind.confirmMulligan));
    await until(
      () =>
          host.host!.state.phase != PlaytestPhase.mulligan &&
          guest.board!.snapshot!.phase != PlaytestPhase.mulligan,
    );
    expect(host.host!.state.phase, isNot(PlaytestPhase.mulligan));
    expect(guest.board!.snapshot!.phase, isNot(PlaytestPhase.mulligan));
    expect(guest.board!.snapshot!.turn, greaterThan(0));

    await guest.close();
    await host.close();
  });
}
