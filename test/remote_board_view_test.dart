import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tcg_decks/models/card_definition.dart';
import 'package:tcg_decks/playtest/net/playtest_host.dart';
import 'package:tcg_decks/playtest/net/playtest_intent.dart';
import 'package:tcg_decks/playtest/net/playtest_transport.dart';
import 'package:tcg_decks/playtest/net/remote_board.dart';
import 'package:tcg_decks/playtest/playtest_engine.dart';
import 'package:tcg_decks/playtest/playtest_state.dart';
import 'package:tcg_decks/screens/remote_board_view.dart';
import 'package:tcg_decks/theme.dart';

import 'playtest_engine_test.dart' show buildDeck;

/// A board on a device, with the game running on another one.
Future<({PlaytestHost host, RemoteBoard mine, RemoteBoard theirs})>
hosted() async {
  final (store, deck) = await buildDeck();
  final engine = PlaytestEngine.startFromItems(
    yourItems: store.viewOf(deck).items,
    opponentItems: store.viewOf(deck).items,
    yourName: 'Player 1',
    opponentName: 'Player 2',
    random: Random(7),
  );
  final host = PlaytestHost(engine);
  final (hostOne, deviceOne) = LoopbackTransport.pair();
  final (hostTwo, deviceTwo) = LoopbackTransport.pair();
  final mine = RemoteBoard(transport: deviceOne, gameId: 'vanguard');
  final theirs = RemoteBoard(transport: deviceTwo, gameId: 'vanguard');
  host
    ..seat(engine.state.you, hostOne)
    ..seat(engine.state.opponent, hostTwo);
  return (host: host, mine: mine, theirs: theirs);
}

Future<void> pumpBoard(WidgetTester tester, RemoteBoard board) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: RemoteBoardView(board: board, onLeave: () {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('it opens on the opening hand', (tester) async {
    final game = await hosted();
    await pumpBoard(tester, game.mine);

    expect(find.text('Your opening hand'), findsOneWidget);
    expect(find.text('Keep this hand'), findsOneWidget);
  });

  testWidgets('keeping the hand waits for the other player', (tester) async {
    final game = await hosted();
    await pumpBoard(tester, game.mine);

    await tester.tap(find.text('Keep this hand'));
    await tester.pumpAndSettle();

    // Nothing moves until both openings are settled, which is the one thing
    // a game across two devices has that a game on one does not: waiting.
    expect(find.text('Your opening hand'), findsOneWidget);

    game.theirs.ask(const PlaytestIntent(IntentKind.confirmMulligan));
    await tester.pumpAndSettle();
    expect(find.text('Your opening hand'), findsNothing);
  });

  testWidgets('the board draws both sides from one snapshot', (tester) async {
    final game = await hosted();
    game.mine.ask(const PlaytestIntent(IntentKind.confirmMulligan));
    game.theirs.ask(const PlaytestIntent(IntentKind.confirmMulligan));
    await pumpBoard(tester, game.mine);

    // Both vanguards stood up at the start, and both are on the board.
    expect(find.byKey(const ValueKey('my-vanguard')), findsOneWidget);
    expect(find.byKey(const ValueKey('their-vanguard')), findsOneWidget);
    expect(find.textContaining('Player 1 (you)'), findsOneWidget);
    expect(find.text('Player 2'), findsOneWidget);
    // Five cards in hand, each of them a card this player can read.
    expect(find.byKey(const ValueKey('hand-1')), findsNothing);
    expect(
      tester.widgetList(find.byType(GestureDetector)).length,
      greaterThan(6),
      reason: 'the board is tappable',
    );
  });

  testWidgets('the phase bar follows the game', (tester) async {
    final game = await hosted();
    game.mine.ask(const PlaytestIntent(IntentKind.confirmMulligan));
    game.theirs.ask(const PlaytestIntent(IntentKind.confirmMulligan));
    await pumpBoard(tester, game.mine);

    final lit = tester.widget<Text>(
      find.byKey(const ValueKey('remote-phase-ride')),
    );
    expect(lit.style!.color, AppColors.bg, reason: 'the ride phase is lit');

    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();

    final now = tester.widget<Text>(
      find.byKey(const ValueKey('remote-phase-main')),
    );
    expect(now.style!.color, AppColors.bg);
  });

  testWidgets('the player who is not playing is told so', (tester) async {
    final game = await hosted();
    game.mine.ask(const PlaytestIntent(IntentKind.confirmMulligan));
    game.theirs.ask(const PlaytestIntent(IntentKind.confirmMulligan));
    await pumpBoard(tester, game.theirs);

    expect(find.textContaining('Waiting for Player 1'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Next'), findsNothing);
  });

  testWidgets('the board fits a small phone', (tester) async {
    // The board you play alone is swept across four sizes; this one is new
    // and gets the same treatment at the tightest of them.
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final game = await hosted();
    await pumpBoard(tester, game.mine);
    expect(tester.takeException(), isNull, reason: 'the opening hand');

    await tester.tap(find.text('Keep this hand'));
    await tester.pumpAndSettle();
    game.theirs.ask(const PlaytestIntent(IntentKind.confirmMulligan));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'the board');

    // And through a turn, which is where the attack banner and the checks
    // turn up and the strip between the boards has the most in it.
    for (var i = 0; i < 6; i += 1) {
      final next = find.widgetWithText(FilledButton, 'Next');
      if (next.evaluate().isEmpty) break;
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'after step $i');
    }
  });

  testWidgets('a card played on one board shows up on the other', (
    tester,
  ) async {
    final game = await hosted();
    game.mine.ask(const PlaytestIntent(IntentKind.confirmMulligan));
    game.theirs.ask(const PlaytestIntent(IntentKind.confirmMulligan));
    await tester.pump();

    // Player 1 rides, from the other device's seat.
    final riding = game.host.state.you.rideDeck.firstWhere(
      (card) => card.grade == 1,
    );
    game.mine.ask(PlaytestIntent(IntentKind.ride, card: riding.instanceId));

    // The far board is looking at it as the opponent's vanguard.
    await pumpBoard(tester, game.theirs);
    expect(find.text(riding.name), findsWidgets);
  });

  testWidgets('a set order sits in the order zone on both boards', (
    tester,
  ) async {
    // A phone's worth of room, so the strip of piles is not under the hand.
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final game = await hosted();
    game.mine.ask(const PlaytestIntent(IntentKind.confirmMulligan));
    game.theirs.ask(const PlaytestIntent(IntentKind.confirmMulligan));
    await tester.pump();

    final you = game.host.state.you;
    // An id far above anything the engine hands out, so it is this card the
    // board finds and not whatever else the counter reached.
    final order = GameCard(
      900760,
      CardDefinition(
        id: 'catalog:test-set-order',
        gameId: 'vanguard',
        name: 'Pinned Product',
        attributes: const {'grade': '1', 'cardType': 'order-set'},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    you.hand.add(order);
    game.mine.ask(
      PlaytestIntent(IntentKind.playSetOrder, card: order.instanceId),
    );

    // The other player's board says what is set, since they are playing
    // under it too.
    await pumpBoard(tester, game.theirs);
    expect(find.text('Orders 1'), findsOneWidget);
    // On the table against the field, too, where it can be read without
    // opening anything; tapping it opens the pile, with nothing to move.
    expect(find.byKey(const ValueKey('remote-order-their-0')), findsOneWidget);
    expect(find.text('ORDERS 1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('remote-order-their-0')));
    await tester.pumpAndSettle();
    expect(find.text('Player 1’s Orders (1)'), findsOneWidget);
    expect(find.byKey(const ValueKey('move-order-900760')), findsNothing);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // And its owner can take it off the table again.
    await pumpBoard(tester, game.mine);
    await tester.tap(find.byKey(const ValueKey('remote-order-my-0')));
    await tester.pumpAndSettle();
    expect(find.text('Pinned Product'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('move-order-900760')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('remote-order-exit-soul')));
    await tester.pumpAndSettle();

    expect(you.orderZone, isEmpty);
    expect(you.soul, contains(order));
  });

  testWidgets('a stride crest sits on the table on both boards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final game = await hosted();
    game.mine.ask(const PlaytestIntent(IntentKind.confirmMulligan));
    game.theirs.ask(const PlaytestIntent(IntentKind.confirmMulligan));
    await tester.pump();

    GameCard crest(int id, String name, String type) => GameCard(
      id,
      CardDefinition(
        id: 'catalog:test-$id',
        gameId: 'vanguard',
        name: name,
        attributes: {'grade': '0', 'cardType': type},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    final you = game.host.state.you;
    you.crestZone
      ..add(crest(900770, 'Energy Generator', 'ride-deck-crest'))
      ..add(crest(900771, 'Nightrose', 'crest'));
    game.host.broadcast();

    for (final (board, whose) in [(game.theirs, 'my'), (game.mine, 'their')]) {
      // Each board names the other's table "their", and its own "my".
      final key = whose == 'my' ? 'their' : 'my';
      await pumpBoard(tester, board);
      expect(find.byKey(ValueKey('remote-crest-$key-0')), findsOneWidget);
      // The Energy Generator stays in its pile: its energy is a number on
      // the board already.
      expect(find.byKey(ValueKey('remote-crest-$key-1')), findsNothing);
      expect(find.text('CREST'), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('remote-crest-$key-0')));
      await tester.pumpAndSettle();
      expect(find.text('Player 1’s Crest (2)'), findsOneWidget);
      expect(find.text('Energy Generator'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('a board with nothing on the table draws no strip', (
    tester,
  ) async {
    final game = await hosted();
    game.mine.ask(const PlaytestIntent(IntentKind.confirmMulligan));
    game.theirs.ask(const PlaytestIntent(IntentKind.confirmMulligan));
    await pumpBoard(tester, game.mine);

    expect(find.byKey(const ValueKey('remote-table-my')), findsNothing);
    expect(find.byKey(const ValueKey('remote-table-their')), findsNothing);
  });
}
