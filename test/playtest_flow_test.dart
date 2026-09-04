import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tcg_decks/playtest/playtest_controller.dart';
import 'package:tcg_decks/playtest/playtest_state.dart';
import 'package:tcg_decks/screens/playtest_screen.dart';
import 'package:tcg_decks/screens/playtest_setup_screen.dart';
import 'package:tcg_decks/store/deck_store.dart';
import 'package:tcg_decks/theme.dart';

import 'playtest_engine_test.dart'
    show buildDeck, buildEnergyDeck, buildStrideDeck;

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

    test('a boost is off until you ask for it', () async {
      final (store, deck) = await buildDeck();
      final game = PlaytestController(
        store: store,
        yourDeck: deck,
        opponentDeck: deck,
        random: Random(3),
      );
      game.confirmMulligan();
      game.ride(game.engine.rideDeckOption(game.you)!, fromRideDeck: true);
      game.nextPhase();

      final booster = game.you.hand.firstWhere(
        (c) => game.engine.canCall(game.you, c, Circle.backCenter),
      );
      game.hold(booster);
      game.placeHeld(Circle.backCenter);
      game.nextPhase();

      game.selectAttacker(Circle.vanguard);
      expect(game.availableBooster, isNotNull, reason: 'one is standing there');
      expect(game.boostSelected, isFalse, reason: 'not without being asked');

      game.attackWithSelected(Circle.vanguard);
      // The attack is the vanguard alone, and the booster is still standing.
      expect(game.state.attack!.attackPower, game.you.vanguard!.power);
      expect(game.you.field[Circle.backCenter]!.rested, isFalse);
    });

    test('asking for the boost brings it along', () async {
      final (store, deck) = await buildDeck();
      final game = PlaytestController(
        store: store,
        yourDeck: deck,
        opponentDeck: deck,
        random: Random(3),
      );
      game.confirmMulligan();
      game.ride(game.engine.rideDeckOption(game.you)!, fromRideDeck: true);
      game.nextPhase();

      final booster = game.you.hand.firstWhere(
        (c) => game.engine.canCall(game.you, c, Circle.backCenter),
      );
      game.hold(booster);
      game.placeHeld(Circle.backCenter);
      game.nextPhase();

      game.selectAttacker(Circle.vanguard);
      game.toggleBoost();
      expect(game.boostSelected, isTrue);

      final vanguardPower = game.you.vanguard!.power;
      game.attackWithSelected(Circle.vanguard);
      expect(game.state.attack!.attackPower, vanguardPower + booster.power);
      expect(game.you.field[Circle.backCenter]!.rested, isTrue);
    });

    test('choosing another attacker clears the boost', () async {
      final (store, deck) = await buildDeck();
      final game = PlaytestController(
        store: store,
        yourDeck: deck,
        opponentDeck: deck,
        random: Random(3),
      );
      game.confirmMulligan();
      game.ride(game.engine.rideDeckOption(game.you)!, fromRideDeck: true);
      game.nextPhase();
      final booster = game.you.hand.firstWhere(
        (c) => game.engine.canCall(game.you, c, Circle.backCenter),
      );
      game.hold(booster);
      game.placeHeld(Circle.backCenter);
      game.nextPhase();

      game.selectAttacker(Circle.vanguard);
      game.toggleBoost();
      game.selectAttacker(null);
      expect(game.boostSelected, isFalse);
    });

    test('the CPU going first has already played when you take over', () async {
      final (store, deck) = await buildDeck();
      final game = PlaytestController(
        store: store,
        yourDeck: deck,
        opponentDeck: deck,
        turnOrder: TurnOrder.cpuFirst,
        random: Random(4),
      );
      expect(game.stage, PlaytestStage.mulligan);

      game.confirmMulligan();
      // Turn one belongs to the CPU, so keeping your hand hands straight over
      // to it rather than giving you a board you cannot act on.
      expect(game.state.turn, 1);
      expect(
        game.stage,
        anyOf(PlaytestStage.guarding, PlaytestStage.yours),
        reason: 'it played its turn out',
      );
      expect(game.cpu.vanguard, isNotNull);
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

  group('setting a game up', () {
    Future<void> pumpSetup(WidgetTester tester, DeckStore store, deck) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<DeckStore>.value(
          value: store,
          child: MaterialApp(
            theme: buildTheme(),
            home: PlaytestSetupScreen(deck: deck),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('turn order is offered, with you first to start', (
      tester,
    ) async {
      final (store, deck) = await buildDeck();
      await pumpSetup(tester, store, deck);

      expect(find.text('Turn order'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      expect(find.text('CPU'), findsOneWidget);
      expect(find.text('Random'), findsOneWidget);
      expect(find.text('You go first'), findsOneWidget);
    });

    testWidgets('choosing the CPU deals it the first turn', (tester) async {
      final (store, deck) = await buildDeck();
      await pumpSetup(tester, store, deck);

      await tester.tap(find.text('CPU'));
      await tester.pumpAndSettle();
      expect(find.text('The CPU goes first'), findsOneWidget);

      await tester.tap(find.text('Mirror match'));
      await tester.pumpAndSettle();

      // The board opens on the mulligan and says who has turn one.
      expect(find.text('Opening hand'), findsOneWidget);
      expect(find.textContaining('The CPU goes first'), findsOneWidget);
    });

    testWidgets('random says it is rolled again each restart', (tester) async {
      final (store, deck) = await buildDeck();
      await pumpSetup(tester, store, deck);

      await tester.tap(find.text('Random'));
      await tester.pumpAndSettle();
      expect(
        find.text('Rolled again every time you restart the board.'),
        findsOneWidget,
      );
    });
  });

  group('the playtest board', () {
    /// Taps something on the board, scrolling it into view first: the board
    /// is taller than the test viewport, so the lower half needs reaching.
    Future<void> tapOnBoard(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

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

    testWidgets('the zones are on the board and open', (tester) async {
      final (store, deck) = await buildDeck();
      await pump(tester, store, deck);
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();

      // One pile each side for the deck, drop and soul.
      expect(find.text('Deck'), findsNWidgets(2));
      expect(find.text('Drop'), findsNWidgets(2));
      expect(find.text('Soul'), findsNWidgets(2));
      // No G zone for a Standard deck that does not stride.
      expect(find.text('G'), findsNothing);

      // Yours is the lower of the two.
      await tapOnBoard(tester, find.text('Drop').last);
      expect(find.textContaining('Drop zone'), findsOneWidget);
    });

    testWidgets('the damage zone opens with its costs', (tester) async {
      final (store, deck) = await buildDeck();
      await pump(tester, store, deck);
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();

      expect(find.text('No damage'), findsNWidgets(2));
      await tapOnBoard(tester, find.text('No damage').last);

      expect(find.textContaining('Damage zone'), findsOneWidget);
      expect(find.text('Counter-blast 1'), findsOneWidget);
      expect(find.text('Counter-charge 1'), findsOneWidget);
    });

    testWidgets('the deck can be searched', (tester) async {
      final (store, deck) = await buildDeck();
      await pump(tester, store, deck);
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();

      await tapOnBoard(tester, find.text('Deck').last);
      expect(find.text('Shuffle'), findsOneWidget);
      expect(find.text('To hand'), findsWidgets);
    });

    testWidgets('a stride deck shows a G zone', (tester) async {
      final (store, deck) = await buildStrideDeck();
      await pump(tester, store, deck);
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();

      expect(find.text('G'), findsNWidgets(2));
      await tapOnBoard(tester, find.text('G').last);
      expect(find.textContaining('G zone'), findsOneWidget);
      // A grade 0 vanguard cannot stride yet, and the sheet says why.
      expect(find.textContaining('needs a grade 3 vanguard'), findsOneWidget);
    });

    testWidgets('the crest is on the board and explains itself', (
      tester,
    ) async {
      final (store, deck) = await buildEnergyDeck();
      await pump(tester, store, deck);
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();

      expect(find.text('Crest'), findsNWidgets(2));
      await tapOnBoard(tester, find.text('Crest').last);

      expect(find.text('Energy Generator'), findsOneWidget);
      // Turn one, before riding: it says why nothing has been charged.
      expect(find.textContaining('Still in the ride deck'), findsOneWidget);
    });

    testWidgets('riding charges the crest into play', (tester) async {
      final (store, deck) = await buildEnergyDeck();
      await pump(tester, store, deck);
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();

      await tester.tap(find.text('Ride'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Ride deck · grade 1'));
      await tester.pumpAndSettle();

      await tapOnBoard(tester, find.text('Crest').last);
      // Going first, so it is down but has charged nothing yet.
      expect(find.textContaining('0 energy'), findsOneWidget);
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
