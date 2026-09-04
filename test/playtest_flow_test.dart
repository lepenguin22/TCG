import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tcg_decks/playtest/playtest_controller.dart';
import 'package:tcg_decks/playtest/playtest_state.dart';
import 'package:tcg_decks/screens/playtest_screen.dart';
import 'package:tcg_decks/store/deck_store.dart';
import 'package:tcg_decks/theme.dart';

import 'playtest_engine_test.dart' show buildDeck;

void main() {
  group('the playtest controller', () {
    test('a game begins waiting on your mulligan', () async {
      final (store, deck) = await buildDeck();
      final game = PlaytestController(
        store: store,
        yourDeck: deck,
        opponentDeck: deck,
        random: Random(1),
      );

      expect(game.stage, PlaytestStage.mulligan);
      expect(game.you.hand.length, 5);
    });

    test('keeping the hand starts turn one', () async {
      final (store, deck) = await buildDeck();
      final game = PlaytestController(
        store: store,
        yourDeck: deck,
        opponentDeck: deck,
        random: Random(1),
      );

      game.confirmMulligan();
      expect(game.stage, PlaytestStage.yours);
      expect(game.state.turn, 1);
      expect(game.state.yourTurn, isTrue);
      // Turn one draws, so the hand is six.
      expect(game.you.hand.length, 6);
    });

    test('putting cards back replaces them', () async {
      final (store, deck) = await buildDeck();
      final game = PlaytestController(
        store: store,
        yourDeck: deck,
        opponentDeck: deck,
        random: Random(1),
      );

      final pitched = game.you.hand.take(2).toList();
      for (final card in pitched) {
        game.togglePick(card);
      }
      expect(game.mulliganPicks.length, 2);
      game.confirmMulligan();

      expect(game.you.hand.length, 6, reason: 'five again, plus the draw');
      for (final card in pitched) {
        expect(game.you.hand.contains(card), isFalse);
      }
    });

    test('ending your turn hands over to the CPU', () async {
      final (store, deck) = await buildDeck();
      final game = PlaytestController(
        store: store,
        yourDeck: deck,
        opponentDeck: deck,
        random: Random(5),
      );
      game.confirmMulligan();

      game.nextPhase(); // ride -> main
      game.nextPhase(); // main -> battle
      game.nextPhase(); // battle -> end, which passes the turn

      // The CPU has taken its turn far enough to be attacking, or has finished
      // and handed back. Either way it is no longer waiting on nothing.
      expect(game.stage, anyOf(PlaytestStage.guarding, PlaytestStage.yours));
    });

    test('an attack you declare is guarded and then resolved', () async {
      final (store, deck) = await buildDeck();
      final game = PlaytestController(
        store: store,
        yourDeck: deck,
        opponentDeck: deck,
        random: Random(11),
      );
      game.confirmMulligan();
      game.nextPhase();
      game.nextPhase();
      expect(game.state.phase, PlaytestPhase.battle);

      game.selectAttacker(Circle.vanguard);
      game.attackWithSelected(Circle.vanguard);
      expect(game.stage, PlaytestStage.yourAttack);
      expect(game.state.attack, isNotNull);

      game.driveCheck();
      expect(game.lastChecks, isNotEmpty, reason: 'a vanguard drive checks');

      game.resolveYourAttack();
      expect(game.state.attack, isNull);
      expect(game.stage, PlaytestStage.yours);
    });

    test('a rear-guard attack skips the drive check', () async {
      final (store, deck) = await buildDeck();
      final game = PlaytestController(
        store: store,
        yourDeck: deck,
        opponentDeck: deck,
        random: Random(2),
      );
      game.confirmMulligan();
      game.ride(game.engine.rideDeckOption(game.you)!, fromRideDeck: true);
      game.nextPhase();

      final unit = game.you.hand.firstWhere(
        (c) => game.engine.canCall(game.you, c, Circle.frontLeft),
      );
      game.hold(unit);
      game.placeHeld(Circle.frontLeft);
      expect(game.you.field[Circle.frontLeft], isNotNull);

      game.nextPhase();
      game.selectAttacker(Circle.frontLeft);
      game.attackWithSelected(Circle.vanguard);
      game.driveCheck();
      expect(game.lastChecks, isEmpty);
    });
  });

  group('the playtest board', () {
    Future<void> pump(WidgetTester tester, DeckStore store, deck) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<DeckStore>.value(
          value: store,
          child: MaterialApp(
            theme: buildTheme(),
            home: PlaytestScreen(yourDeck: deck, opponentDeck: deck),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('it opens on the opening hand', (tester) async {
      final (store, deck) = await buildDeck();
      await pump(tester, store, deck);

      expect(find.text('Opening hand'), findsOneWidget);
      expect(find.text('Keep this hand'), findsOneWidget);
    });

    testWidgets('keeping the hand shows the board', (tester) async {
      final (store, deck) = await buildDeck();
      await pump(tester, store, deck);

      await tester.tap(find.text('Keep this hand'));
      await tester.pump();

      // The board names both players and the turn.
      expect(find.textContaining('Turn 1'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      expect(find.text('CPU'), findsOneWidget);
    });

    testWidgets('the ride phase offers a ride', (tester) async {
      final (store, deck) = await buildDeck();
      await pump(tester, store, deck);
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();

      expect(find.text('Ride'), findsOneWidget);
      await tester.tap(find.text('Ride'));
      await tester.pumpAndSettle();

      // The sheet offers the grade 1 off the ride deck.
      expect(find.textContaining('Ride deck · grade 1'), findsOneWidget);
    });
  });
}
