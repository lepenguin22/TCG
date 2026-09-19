import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tcg_decks/playtest/net/playtest_intent.dart';
import 'package:tcg_decks/playtest/net/socket_transport.dart';
import 'package:tcg_decks/playtest/net/two_player_session.dart';
import 'package:tcg_decks/playtest/net/wire_deck.dart';
import 'package:tcg_decks/playtest/playtest_state.dart';

import 'playtest_engine_test.dart' show buildDeck;

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
    await pumpEventQueue();

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
    await pumpEventQueue();

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
    await pumpEventQueue();
    // Something that is not this protocol at all.
    await guest.close();

    expect(heard.single['type'], 'first');
    await host.close();
  });

  test('two devices meet, swap decks and play', () async {
    final (store, myDeck) = await buildDeck();
    final (guestStore, theirDeck) = await buildDeck(name: 'Their deck');

    final host = HostSession(
      gameId: 'vanguard',
      deck: WireDeck.of(store.viewOf(myDeck)),
      crests: store.cards,
      turnOrder: TurnOrder.youFirst,
      random: Random(7),
    );
    final opened = host.open(port: 0);
    // The address is offered as soon as there is one to offer.
    while (host.port == null) {
      await pumpEventQueue();
    }
    expect(host.stage, SessionStage.waiting);

    final guest = GuestSession(
      gameId: 'vanguard',
      deck: WireDeck.of(guestStore.viewOf(theirDeck)),
    );
    await guest.join('127.0.0.1', port: host.port!);
    await opened;
    await pumpEventQueue();

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
    await pumpEventQueue();
    expect(host.host!.state.phase, isNot(PlaytestPhase.mulligan));
    expect(guest.board!.snapshot!.phase, isNot(PlaytestPhase.mulligan));
    expect(guest.board!.snapshot!.turn, greaterThan(0));

    await guest.close();
    await host.close();
  });
}
