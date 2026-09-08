import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tcg_decks/games/vanguard/vanguard_data.dart';
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
    /// Steps the CPU's first turn out, so the board is on your turn two.
    ///
    /// Nobody attacks on turn one, so a test about attacking gives that turn
    /// to the CPU and plays it through.
    void pastTheFirstTurn(PlaytestController game) {
      for (var i = 0; i < 30 && game.stage == PlaytestStage.cpuTurn; i += 1) {
        game.cpuStep();
      }
    }

    test('the board does not offer a boost a grade 2 cannot give', () async {
      final (store, deck) = await buildDeck();
      final game = PlaytestController(
        store: store,
        yourDeck: deck,
        opponentDeck: deck,
        random: Random(1),
      );
      game.confirmMulligan();
      final you = game.you;
      game.engine.ride(
        you,
        game.engine.rideDeckOption(you)!,
        fromRideDeck: true,
      );

      // A grade 2 standing behind the vanguard, which in this deck is a body
      // and not a booster.
      final beater = you.deck.lastWhere((c) => c.grade == 2);
      you.deck.remove(beater);
      you.hand.add(beater);
      game.engine.call(you, beater, Circle.backCenter);
      game.state.phase = PlaytestPhase.battle;
      game.selectAttacker(Circle.vanguard);

      expect(game.availableBooster, isNull, reason: 'grade 2 has no [Boost]');
      expect(
        game.boosterThatCannot?.card.name,
        'Beater',
        reason: 'so the board can say why',
      );

      // Given the keyword by an ability, it is a booster like any other.
      game.grantBoost(you, Circle.backCenter, granted: true);
      expect(game.availableBooster?.card.name, 'Beater');
      expect(game.boosterThatCannot, isNull);
    });

    /// A game where both hands are yours and nothing plays itself.
    Future<PlaytestController> soloGame(int seed) async {
      final (store, deck) = await buildDeck();
      return PlaytestController(
        store: store,
        yourDeck: deck,
        opponentDeck: deck,
        mode: PlaytestMode.bothSides,
        random: Random(seed),
      );
    }

    test('both openings are decided by you', () async {
      final game = await soloGame(1);
      expect(game.stage, PlaytestStage.mulligan);
      expect(game.mulliganSide, game.you);
      expect(game.you.name, 'Player 1');
      expect(game.cpu.name, 'Player 2');

      game.confirmMulligan();
      expect(
        game.stage,
        PlaytestStage.mulligan,
        reason: 'the second hand is yours as well',
      );
      expect(game.mulliganSide, game.cpu);

      game.confirmMulligan();
      expect(game.stage, PlaytestStage.yours);
      expect(game.you.hand.length, 6, reason: 'five kept, one drawn');
      expect(
        game.cpu.hand.length,
        5,
        reason: 'the second player has not drawn',
      );
    });

    /// Ends the turn of whoever is playing, however many phases that takes.
    void passTheTurn(PlaytestController game) {
      final started = game.state.active;
      for (var i = 0; i < 8 && game.state.active == started; i += 1) {
        game.nextPhase();
      }
    }

    test('nothing plays the far side but you', () async {
      final game = await soloGame(2);
      game.confirmMulligan();
      game.confirmMulligan();

      final theirBoard = game.cpu.units.length;
      final theirHand = game.cpu.hand.length;
      passTheTurn(game);

      // The turn is the other player's, and it is still yours to play: no
      // CPU step, no board that filled itself in while you were not looking.
      expect(game.state.yourTurn, isFalse);
      expect(game.stage, PlaytestStage.yours);
      expect(game.me, game.cpu, reason: 'you are playing them now');
      expect(game.handSide, game.cpu);
      expect(game.cpu.units.length, theirBoard);
      expect(
        game.cpu.hand.length,
        theirHand + 1,
        reason: 'their own draw step, and nothing else',
      );
      expect(game.controls(game.you), isTrue);
      expect(game.controls(game.cpu), isTrue);
    });

    test(
      'player two strides their own G unit, not player one\u2019s',
      () async {
        final (store, deck) = await buildStrideDeck();
        final game = PlaytestController(
          store: store,
          yourDeck: deck,
          opponentDeck: deck,
          mode: PlaytestMode.bothSides,
          random: Random(6),
        );
        game.confirmMulligan();
        game.confirmMulligan();
        passTheTurn(game);
        expect(game.me, game.cpu, reason: 'player two is playing');

        // A grade 3 vanguard to stride over, and a hand that can pay for it.
        final them = game.cpu;
        // The grade 3 lives in the ride deck, which is where a real one is
        // ridden from.
        final grade3 = them.rideDeck.firstWhere((c) => c.grade == 3);
        them.rideDeck.remove(grade3);
        them.field[Circle.vanguard] = FieldUnit(grade3);
        final cost = <GameCard>[];
        var total = 0;
        while (total < 3) {
          final card = them.deck.removeLast();
          them.hand.add(card);
          cost.add(card);
          total += card.grade;
        }

        final gUnit = them.gZone.first;
        final theirHand = them.hand.length;
        final myVanguard = game.you.vanguard;

        game.stride(them, gUnit, cost);

        expect(
          them.vanguard!.card.name,
          gUnit.name,
          reason: 'the G unit is on their vanguard circle',
        );
        expect(them.isStriding, isTrue);
        expect(them.hand.length, theirHand - cost.length, reason: 'they paid');
        expect(them.gZone.contains(gUnit), isFalse);
        expect(
          game.you.vanguard,
          myVanguard,
          reason: 'player one was not touched',
        );
      },
    );

    test('you guard your own attack, then drive and resolve it', () async {
      final game = await soloGame(4);
      game.confirmMulligan();
      game.confirmMulligan();
      // Turn one does not attack, so hand the turn over and take it back.
      passTheTurn(game);
      passTheTurn(game);
      expect(game.state.turn, greaterThan(1), reason: 'past the first turn');
      expect(game.me, game.you);

      game.state.phase = PlaytestPhase.battle;
      game.selectAttacker(Circle.vanguard);
      game.attackWithSelected(Circle.vanguard);

      // The defender guards -- by hand, with their own cards.
      expect(game.stage, PlaytestStage.guarding);
      expect(game.handSide, game.cpu, reason: 'the defender holds the shields');
      final shield = game.cpu.hand.firstWhere((c) => c.shield > 0);
      final before = game.state.attack!.defence;
      game.guardWith(shield);
      expect(game.state.attack!.defence, before + shield.shield);

      // Then it goes back to the attacker to drive and resolve.
      game.confirmGuard();
      expect(game.stage, PlaytestStage.yourAttack);
      game.driveCheck();
      game.resolveYourAttack();
      expect(game.stage, PlaytestStage.yours);
      expect(game.state.attack, isNull);
    });

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
        turnOrder: TurnOrder.cpuFirst,
        random: Random(11),
      );
      game.confirmMulligan();
      pastTheFirstTurn(game);
      game.nextPhase();
      game.nextPhase();
      expect(game.state.phase, PlaytestPhase.battle);

      game.selectAttacker(Circle.vanguard);
      game.attackWithSelected(Circle.vanguard);
      expect(game.stage, PlaytestStage.yourAttack);
      expect(game.state.attack, isNotNull);

      game.driveCheck();
      expect(
        game.triggerZone.where((c) => c.kind == CheckKind.drive),
        isNotEmpty,
        reason: 'a vanguard drive checks',
      );

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
        turnOrder: TurnOrder.cpuFirst,
        random: Random(3),
      );
      game.confirmMulligan();
      pastTheFirstTurn(game);
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
        turnOrder: TurnOrder.cpuFirst,
        random: Random(3),
      );
      game.confirmMulligan();
      pastTheFirstTurn(game);
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

    test('the CPU going first waits to be stepped through', () async {
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
      // to it -- and its main phase is yours to step through rather than a
      // finished board handed back to you.
      expect(game.state.turn, 1);
      expect(game.stage, PlaytestStage.cpuTurn);
      expect(
        game.cpu.vanguard!.card.grade,
        0,
        reason: 'still its starting vanguard, not ridden up',
      );

      for (var i = 0; i < 20 && game.stage == PlaytestStage.cpuTurn; i += 1) {
        game.cpuStep();
      }
      expect(
        game.stage,
        anyOf(PlaytestStage.guarding, PlaytestStage.yours),
        reason: 'it played its turn out',
      );
      expect(game.cpu.vanguard!.card.grade, 1, reason: 'it rode up');
    });

    test('the CPU plays one action per step', () async {
      final (store, deck) = await buildDeck();
      final game = PlaytestController(
        store: store,
        yourDeck: deck,
        opponentDeck: deck,
        turnOrder: TurnOrder.cpuFirst,
        random: Random(4),
      );
      game.confirmMulligan();

      // The ride is the first thing it does, and it is the only thing that
      // first tap does.
      game.cpuStep();
      expect(game.cpu.vanguard!.card.grade, 1, reason: 'it rode');
      expect(game.cpu.units, hasLength(1), reason: 'and called nothing yet');
      expect(game.lastCpuAction, contains('rides'));

      // Each tap after that puts at most one more unit on the board.
      var units = game.cpu.units.length;
      while (game.stage == PlaytestStage.cpuTurn) {
        game.cpuStep();
        final now = game.cpu.units.length;
        expect(
          now - units,
          lessThanOrEqualTo(1),
          reason: 'one action at a time',
        );
        units = now;
      }
      expect(units, greaterThan(1), reason: 'it did build a board');
    });

    test('stepping to the end is the same board as playing it out', () async {
      Future<PlaytestController> game(bool stepped) async {
        final (store, deck) = await buildDeck();
        final controller = PlaytestController(
          store: store,
          yourDeck: deck,
          opponentDeck: deck,
          turnOrder: TurnOrder.cpuFirst,
          random: Random(9),
        );
        controller.confirmMulligan();
        if (stepped) {
          while (controller.stage == PlaytestStage.cpuTurn) {
            controller.cpuStep();
          }
        } else {
          // What the CPU does when nobody is watching it: the same steps,
          // run to the end in one go.
          controller.ai.takeTurn();
        }
        return controller;
      }

      final stepped = await game(true);
      final atOnce = await game(false);
      expect(
        stepped.cpu.units.map((u) => u.card.name).toList(),
        atOnce.cpu.units.map((u) => u.card.name).toList(),
      );
      expect(stepped.cpu.hand.length, atOnce.cpu.hand.length);
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
      expect(game.triggerZone, isEmpty);
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

      // The opponent list sits below the mode and turn order choices.
      await tester.ensureVisible(find.text('Mirror match'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mirror match'));
      await tester.pumpAndSettle();

      // The board opens on the mulligan and says who has turn one.
      expect(find.text('Opening hand'), findsOneWidget);
      expect(find.textContaining('The CPU goes first'), findsOneWidget);
    });

    testWidgets('the setup screen offers taking both sides', (tester) async {
      final (store, deck) = await buildDeck();
      await pumpSetup(tester, store, deck);

      await tester.tap(find.text('You, both sides'));
      await tester.pumpAndSettle();
      // The turn order is said in the words of a game with two players.
      expect(find.text('Player 1'), findsOneWidget);
      expect(find.text('Player 1 goes first'), findsOneWidget);

      // The opponent list sits below both choices, and a list only builds
      // what is on screen, so it is scrolled to rather than found.
      for (
        var i = 0;
        i < 8 && find.text('Mirror match').evaluate().isEmpty;
        i += 1
      ) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Mirror match'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Player 1\u2019s opening hand'),
        findsOneWidget,
      );
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

    /// Scrolls the open sheet until [finder] has something, then brings it
    /// on screen. A sheet only builds what is near its viewport, so anything
    /// below the fold is not in the tree until it is scrolled to.
    Future<void> scrollSheetTo(WidgetTester tester, Finder finder) async {
      for (var i = 0; i < 10 && finder.evaluate().isEmpty; i += 1) {
        await tester.drag(find.byType(Scrollable).last, const Offset(0, -200));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(finder.first);
      await tester.pumpAndSettle();
    }

    Future<void> pump(
      WidgetTester tester,
      DeckStore store,
      deck, {
      TurnOrder turnOrder = TurnOrder.youFirst,
      PlaytestMode mode = PlaytestMode.vsCpu,
    }) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<DeckStore>.value(
          value: store,
          child: MaterialApp(
            theme: buildTheme(),
            home: PlaytestScreen(
              yourDeck: deck,
              opponentDeck: deck,
              turnOrder: turnOrder,
              mode: mode,
              // A fixed shuffle: these tests reach for particular
              // cards, and a board that is a different board every
              // run fails one time in a hundred for no reason.
              random: Random(7),
            ),
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

      // The deck opens on what can be done to it, without showing itself.
      await tapOnBoard(tester, find.text('Deck').last);
      expect(find.text('Draw a card'), findsOneWidget);
      expect(find.text('Shuffle'), findsOneWidget);
      expect(find.text('To hand'), findsNothing, reason: 'not revealed yet');

      // Looking is the deliberate one.
      await tester.tap(find.text('Look through the deck'));
      await tester.pumpAndSettle();
      expect(find.text('To hand'), findsWidgets);
    });

    testWidgets('a card can be drawn without reading the deck', (tester) async {
      final (store, deck) = await buildDeck();
      await pump(tester, store, deck);
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();
      expect(find.textContaining('Hand '), findsWidgets);

      await tapOnBoard(tester, find.text('Deck').last);
      await tester.tap(find.text('Draw a card'));
      await tester.pumpAndSettle();

      // One more card in hand, one fewer in the deck, and the deck was never
      // laid out to take it.
      await tapOnBoard(tester, find.text('Deck').last);
      expect(find.textContaining('Deck (43)'), findsOneWidget);
      expect(find.text('To hand'), findsNothing);
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

    testWidgets('a G zone card can be turned face up and back', (tester) async {
      final (store, deck) = await buildStrideDeck();
      await pump(tester, store, deck);
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();

      await tapOnBoard(tester, find.text('G').last);
      expect(find.textContaining('0 face up'), findsOneWidget);
      expect(find.text('Flip face up'), findsWidgets);

      await tester.tap(find.text('Flip face up').first);
      await tester.pumpAndSettle();

      // The board says how many are face up without opening the sheet.
      expect(find.text('G ↑1'), findsOneWidget);

      await tapOnBoard(tester, find.text('G ↑1'));
      expect(find.textContaining('1 face up'), findsOneWidget);
      expect(find.text('Turn face down'), findsOneWidget);
      await tester.tap(find.text('Turn face down'));
      await tester.pumpAndSettle();
      expect(find.text('G ↑1'), findsNothing);
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

      // Turn one, before riding: it names the crest waiting in the ride deck
      // and says why nothing has been charged.
      expect(
        find.textContaining('Energy Generator is still in the ride deck'),
        findsOneWidget,
      );
    });

    testWidgets('the energy cap can be raised from the crest zone', (
      tester,
    ) async {
      final (store, deck) = await buildEnergyDeck();
      await pump(tester, store, deck);
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();

      await tapOnBoard(tester, find.text('Crest').last);
      expect(find.textContaining('of 10 energy'), findsOneWidget);

      // The controls sit below what is in the zone, so scroll to them.
      for (var i = 0; i < 8 && find.text('Cap 15').evaluate().isEmpty; i += 1) {
        await tester.drag(find.byType(Scrollable).last, const Offset(0, -200));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text('Cap 15'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cap 15'));
      await tester.pumpAndSettle();

      // Back up to the heading, which the scroll took off screen.
      for (
        var i = 0;
        i < 8 && find.textContaining('energy').evaluate().isEmpty;
        i += 1
      ) {
        await tester.drag(find.byType(Scrollable).last, const Offset(0, 200));
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('of 15 energy'), findsOneWidget);
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
      // A ride out of the ride deck costs a card, and which one is asked.
      await tester.tap(find.text('Discard').first);
      await tester.pumpAndSettle();

      await tapOnBoard(tester, find.text('Crest').last);
      // Going first, so it is down but has charged nothing yet.
      expect(find.textContaining('0 energy'), findsOneWidget);
    });

    /// A card in hand of a grade low enough to call under a grade 1
    /// vanguard. Hand tiles label themselves with their grade, which is the
    /// only handle a widget test has on which card is which.
    /// Plays the CPU's first turn out, so the board is on your turn two.
    ///
    /// Nobody attacks on turn one -- whoever goes first does not -- so a test
    /// about attacking starts by handing that turn to the CPU and stepping
    /// through it.
    Future<void> pastTheFirstTurn(WidgetTester tester) async {
      for (var i = 0; i < 30; i += 1) {
        final step = find.text('Continue');
        if (step.evaluate().isEmpty) break;
        await tester.tap(step);
        await tester.pumpAndSettle();
      }
    }

    Finder callableHandCard() {
      for (final label in ['G1', 'G0']) {
        if (find.text(label).evaluate().isNotEmpty) return find.text(label);
      }
      return find.text('G1');
    }

    testWidgets('a rear-guard offers to move up its column', (tester) async {
      final (store, deck) = await buildDeck();
      await pump(tester, store, deck);
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();

      // Ride into grade 1 so there is something to call under, then move on
      // to the main phase.
      await tester.tap(find.text('Ride'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Ride deck · grade 1'));
      await tester.pumpAndSettle();
      // A ride out of the ride deck costs a card, and which one is asked.
      await tester.tap(find.text('Discard').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pump();

      // Call something into the back left circle.
      await tapOnBoard(tester, callableHandCard().first);
      await tester.tap(find.text('Call to a circle'));
      await tester.pumpAndSettle();
      await tapOnBoard(
        tester,
        find.byKey(const ValueKey('circle-You-backLeft')),
      );

      // Tapping it now offers the move up, because the front of its column
      // is empty.
      await tapOnBoard(
        tester,
        find.byKey(const ValueKey('circle-You-backLeft')),
      );
      expect(find.textContaining('Move to front left'), findsOneWidget);
      await tester.tap(find.textContaining('Move to front left'));
      await tester.pumpAndSettle();

      // It is in the front row now, and the offer has flipped the other way.
      await tapOnBoard(
        tester,
        find.byKey(const ValueKey('circle-You-frontLeft')),
      );
      expect(find.textContaining('Move to back left'), findsOneWidget);
    });

    testWidgets('the vanguard is never offered a move', (tester) async {
      final (store, deck) = await buildDeck();
      await pump(tester, store, deck);
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();
      await tester.tap(find.text('Next'));
      await tester.pump();

      await tapOnBoard(
        tester,
        find.byKey(const ValueKey('circle-You-vanguard')),
      );
      // Nothing moves onto or off the vanguard circle.
      expect(find.textContaining('Move to'), findsNothing);
      expect(find.textContaining('Swap with'), findsNothing);
    });

    testWidgets('a unit can be given critical by hand', (tester) async {
      final (store, deck) = await buildDeck();
      await pump(tester, store, deck);
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();

      await tapOnBoard(
        tester,
        find.byKey(const ValueKey('circle-You-vanguard')),
      );
      expect(find.text('+1 critical'), findsOneWidget);
      expect(find.text('-1 critical'), findsOneWidget);

      await tester.tap(find.text('+1 critical'));
      await tester.pumpAndSettle();

      // Close the sheet by tapping the barrier above it.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      // The unit now wears its critical on the board, where one critical --
      // the default -- would not be shown at all.
      expect(find.textContaining('★2'), findsOneWidget);
    });

    testWidgets('power is given in whatever amount the card says', (
      tester,
    ) async {
      final (store, deck) = await buildDeck();
      await pump(tester, store, deck);
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();

      await tapOnBoard(
        tester,
        find.byKey(const ValueKey('circle-You-vanguard')),
      );

      // The field opens on the commonest amount, and the old fixed buttons
      // are gone: an ability giving 4000 is typed in as 4000.
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '5000',
      );
      expect(find.text('+5k power'), findsNothing);
      await tester.enterText(find.byType(TextField), '4000');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add power'));
      await tester.pumpAndSettle();

      // A grade 0 vanguard is 9000 in this deck, so it now reads 13000 and
      // says how much of that was applied by hand.
      expect(find.textContaining('13000 power'), findsWidgets);
      expect(find.textContaining(RegExp(r'\+4000 by hand')), findsOneWidget);

      // Taking it away again works off the same field, and clearing puts
      // the unit back where it started.
      await tester.tap(find.text('Remove power'));
      await tester.pumpAndSettle();
      expect(find.textContaining(RegExp(r'\d by hand')), findsNothing);

      await tester.tap(find.text('Add power'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(find.textContaining(RegExp(r'\d by hand')), findsNothing);
    });

    testWidgets('an empty power field does nothing', (tester) async {
      final (store, deck) = await buildDeck();
      await pump(tester, store, deck);
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();

      await tapOnBoard(
        tester,
        find.byKey(const ValueKey('circle-You-vanguard')),
      );
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();

      final add = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Add power'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(add.onPressed, isNull, reason: 'nothing to add');
    });

    testWidgets('drive is offered on the vanguard alone', (tester) async {
      final (store, deck) = await buildDeck();
      // The drive check is only reached by attacking, and nobody attacks on
      // turn one, so the CPU takes it.
      await pump(tester, store, deck, turnOrder: TurnOrder.cpuFirst);
      await tester.tap(find.text('Keep this hand'));
      await tester.pumpAndSettle();
      await pastTheFirstTurn(tester);

      await tapOnBoard(
        tester,
        find.byKey(const ValueKey('circle-You-vanguard')),
      );
      expect(find.text('+1 drive'), findsOneWidget);
      // The heading counts the checks it will make.
      expect(find.textContaining('1 drive'), findsWidgets);

      await tester.tap(find.text('+1 drive'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      // Ride, then attack: the button says how many checks are coming.
      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.tap(find.text('Next'));
      await tester.pump();
      await tapOnBoard(
        tester,
        find.byKey(const ValueKey('circle-You-vanguard')),
      );
      await tapOnBoard(
        tester,
        find.byKey(const ValueKey('circle-CPU-vanguard')),
      );
      // Two checks to make, and the button says how many are left rather
      // than flipping them together.
      expect(find.text('Drive check (2 left)'), findsOneWidget);
      await tester.tap(find.text('Drive check (2 left)'));
      await tester.pumpAndSettle();
      expect(
        find.text('Drive check'),
        findsOneWidget,
        reason: 'the second one, on its own',
      );
      await tester.tap(find.text('Drive check'));
      await tester.pumpAndSettle();
      expect(find.text('Resolve'), findsOneWidget);
    });

    testWidgets('a rear-guard is offered no drive', (tester) async {
      final (store, deck) = await buildDeck();
      await pump(tester, store, deck);
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();
      await tester.tap(find.text('Ride'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Ride deck · grade 1'));
      await tester.pumpAndSettle();
      // A ride out of the ride deck costs a card, and which one is asked.
      await tester.tap(find.text('Discard').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pump();

      await tapOnBoard(tester, callableHandCard().first);
      await tester.tap(find.text('Call to a circle'));
      await tester.pumpAndSettle();
      await tapOnBoard(
        tester,
        find.byKey(const ValueKey('circle-You-frontLeft')),
      );

      await tapOnBoard(
        tester,
        find.byKey(const ValueKey('circle-You-frontLeft')),
      );
      // It has power and critical controls, but nothing drive: a rear-guard
      // never drive checks.
      expect(find.text('+1 critical'), findsOneWidget);
      expect(find.text('+1 drive'), findsNothing);
    });

    testWidgets('the battle shows its guardian and trigger zones', (
      tester,
    ) async {
      final (store, deck) = await buildDeck();
      // The CPU takes turn one, which is the turn nobody attacks on.
      await pump(tester, store, deck, turnOrder: TurnOrder.cpuFirst);
      await tester.tap(find.text('Keep this hand'));
      await tester.pumpAndSettle();
      await pastTheFirstTurn(tester);

      // Nothing to show before a battle starts.
      expect(find.text('GUARDIAN'), findsNothing);
      expect(find.text('TRIGGER'), findsNothing);

      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.tap(find.text('Next'));
      await tester.pump();
      await tapOnBoard(
        tester,
        find.byKey(const ValueKey('circle-You-vanguard')),
      );
      await tapOnBoard(
        tester,
        find.byKey(const ValueKey('circle-CPU-vanguard')),
      );

      // The guardian circle appears with the attack, empty until something
      // is called to it.
      expect(find.text('GUARDIAN'), findsOneWidget);
      expect(find.text('Nothing guarding'), findsOneWidget);

      // The bar says "Drive check to see what you turn up." as well, so the
      // button is picked out rather than the words.
      await tester.tap(
        find.descendant(
          of: find.byType(FilledButton),
          matching: find.textContaining('Drive check'),
        ),
      );
      await tester.pumpAndSettle();

      // And the drive check lands in the trigger zone.
      expect(find.text('TRIGGER'), findsOneWidget);
      expect(find.text('Nothing checked'), findsNothing);
    });

    testWidgets('a checked trigger can be handed to another unit', (
      tester,
    ) async {
      final (store, deck) = await buildDeck();
      // Nobody attacks on turn one, so the CPU takes it.
      await pump(tester, store, deck, turnOrder: TurnOrder.cpuFirst);
      await tester.tap(find.text('Keep this hand'));
      await tester.pumpAndSettle();
      await pastTheFirstTurn(tester);

      final game = Provider.of<PlaytestController>(
        tester.element(find.byType(Scaffold)),
        listen: false,
      );
      // A rear-guard to hand a trigger to, then attack.
      await tester.tap(find.text('Next'));
      await tester.pump();
      await tapOnBoard(tester, callableHandCard().first);
      await tester.tap(find.text('Call to a circle'));
      await tester.pumpAndSettle();
      await tapOnBoard(
        tester,
        find.byKey(const ValueKey('circle-You-frontLeft')),
      );
      await tester.tap(find.text('Next'));
      await tester.pump();

      // A critical trigger put on top, so the check is the one being tested
      // rather than whatever the shuffle happened to leave there.
      final trigger = game.you.deck.lastWhere((c) => c.trigger == 'critical');
      game.you.deck.remove(trigger);
      game.you.deck.add(trigger);

      await tapOnBoard(
        tester,
        find.byKey(const ValueKey('circle-You-vanguard')),
      );
      await tapOnBoard(
        tester,
        find.byKey(const ValueKey('circle-CPU-vanguard')),
      );
      await tester.tap(
        find.descendant(
          of: find.byType(FilledButton),
          matching: find.textContaining('Drive check'),
        ),
      );
      await tester.pumpAndSettle();

      final checked = game.triggerZone.last;
      expect(checked.card, trigger);
      expect(checked.isSplittable, isTrue);

      final vanguard = game.you.vanguard!;
      final rear = game.you.field[Circle.frontLeft]!;
      expect(vanguard.powerBonus, greaterThan(0));

      // Tapping the checked card offers who gets what.
      await tapOnBoard(tester, find.text('critical').last);
      expect(find.textContaining('trigger —'), findsOneWidget);
      expect(find.textContaining('Power +'), findsOneWidget);

      // The power list and the critical list both name every unit, so the
      // row is picked by which list it is in.
      await tester.tap(find.byKey(const ValueKey('trigger-power-frontLeft')));
      await tester.pumpAndSettle();

      expect(rear.powerBonus, greaterThan(0));
      expect(vanguard.powerBonus, 0, reason: 'it moved rather than doubled');
      expect(
        vanguard.critical,
        2,
        reason: 'the critical stayed on the vanguard',
      );

      // And the critical can go its own way. Its list is below the power's,
      // so it takes a scroll to reach.
      await scrollSheetTo(
        tester,
        find.byKey(const ValueKey('trigger-critical-frontLeft')),
      );
      await tester.tap(
        find.byKey(const ValueKey('trigger-critical-frontLeft')),
      );
      await tester.pumpAndSettle();
      expect(rear.critical, 2);
      expect(vanguard.critical, 1);
    });

    testWidgets('a damage check stays visible after the attack', (
      tester,
    ) async {
      final (store, deck) = await buildDeck();
      // The CPU takes turn one, which is the turn nobody attacks on.
      await pump(tester, store, deck, turnOrder: TurnOrder.cpuFirst);
      await tester.tap(find.text('Keep this hand'));
      await tester.pumpAndSettle();
      await pastTheFirstTurn(tester);
      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.tap(find.text('Next'));
      await tester.pump();

      await tapOnBoard(
        tester,
        find.byKey(const ValueKey('circle-You-vanguard')),
      );
      await tapOnBoard(
        tester,
        find.byKey(const ValueKey('circle-CPU-vanguard')),
      );
      // The bar says "Drive check to see what you turn up." as well, so the
      // button is picked out rather than the words.
      await tester.tap(
        find.descendant(
          of: find.byType(FilledButton),
          matching: find.textContaining('Drive check'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resolve'));
      await tester.pumpAndSettle();

      // The battle is over, but what it turned up is still on the board.
      expect(find.text('GUARDIAN'), findsNothing, reason: 'no attack now');
      expect(find.text('TRIGGER'), findsOneWidget);
    });

    testWidgets('a unit can be called out of the deck mid-battle', (
      tester,
    ) async {
      final (store, deck) = await buildDeck();
      await pump(tester, store, deck);
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();

      // Ride to grade 1 so something in the deck is callable, then go all
      // the way to the battle phase, which is when these abilities fire.
      await tester.tap(find.text('Ride'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Ride deck · grade 1'));
      await tester.pumpAndSettle();
      // A ride out of the ride deck costs a card, and which one is asked.
      await tester.tap(find.text('Discard').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.tap(find.text('Next'));
      await tester.pump();

      // The deck offers a call as well as a search to hand. The top of the
      // deck is whatever the shuffle left there, so scroll down the sheet
      // until a card the vanguard's grade allows comes into view.
      await tapOnBoard(tester, find.text('Deck').last);
      await tester.tap(find.text('Look through the deck'));
      await tester.pumpAndSettle();
      expect(find.text('To hand'), findsWidgets);
      for (var i = 0; i < 12 && find.text('Call').evaluate().isEmpty; i += 1) {
        await tester.drag(find.byType(Scrollable).last, const Offset(0, -220));
        await tester.pumpAndSettle();
      }
      expect(find.text('Call'), findsWidgets);

      await tapOnBoard(tester, find.text('Call').first);

      // The board is now waiting for a circle, in the battle phase.
      expect(find.textContaining('Tap a circle to call'), findsOneWidget);
      await tapOnBoard(
        tester,
        find.byKey(const ValueKey('circle-You-frontLeft')),
      );

      // And the called unit is standing on the field. A tap in the battle
      // phase picks an attacker, so the unit's own sheet comes up on a long
      // press instead.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('circle-You-frontLeft')),
          matching: find.text('—'),
        ),
        findsNothing,
        reason: 'the circle is filled',
      );
      await tester.longPress(
        find.byKey(const ValueKey('circle-You-frontLeft')),
      );
      await tester.pumpAndSettle();
      expect(find.text('+1 critical'), findsOneWidget, reason: 'a unit here');
    });

    testWidgets('the drop zone offers a call too', (tester) async {
      final (store, deck) = await buildDeck();
      await pump(tester, store, deck);
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();
      await tester.tap(find.text('Ride'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Ride deck · grade 1'));
      await tester.pumpAndSettle();
      // A ride out of the ride deck costs a card, and which one is asked.
      await tester.tap(find.text('Discard').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pump();

      // Discard something so the drop has a unit in it.
      await tapOnBoard(tester, callableHandCard().first);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      await tapOnBoard(tester, find.text('Drop').last);
      expect(find.textContaining('Drop zone'), findsOneWidget);
      expect(find.text('Call'), findsWidgets);
    });

    testWidgets('an order in the drop can be played, and then it is gone', (
      tester,
    ) async {
      final (store, deck) = await buildDeck();
      await pump(tester, store, deck);
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();

      // The board's own controller, so an order can be put in the drop the
      // way a game would put one there without playing a whole turn for it.
      final game = Provider.of<PlaytestController>(
        tester.element(find.byType(Scaffold)),
        listen: false,
      );
      final order = GameCard(
        4242,
        store.saveCard(
          gameId: 'vanguard',
          name: 'Ancient Dragon Rampage',
          attributes: {
            'grade': '1',
            'cardType': 'order',
            'effect':
                'You may play this card from your drop zone. If you do, '
                'remove it from the game.',
          },
        ),
      );
      game.you.drop.add(order);
      game.hold(null); // Repaints, without reaching for anything private.
      await tester.pumpAndSettle();

      expect(find.text('Removed'), findsNothing, reason: 'nothing gone yet');

      await tapOnBoard(tester, find.text('Drop').last);
      expect(find.text('Ancient Dragon Rampage'), findsOneWidget);
      expect(find.text('Play from drop'), findsOneWidget);

      await tester.tap(find.text('Play from drop'));
      await tester.pumpAndSettle();

      expect(game.you.drop.contains(order), isFalse);
      expect(game.you.removed, contains(order));
      expect(find.text('Removed'), findsOneWidget);
    });

    testWidgets('a unit in the drop activates rather than being played', (
      tester,
    ) async {
      final (store, deck) = await buildDeck();
      await pump(tester, store, deck);
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();

      // Discard a unit, which is what a drop zone is usually full of.
      await tapOnBoard(tester, callableHandCard().first);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      await tapOnBoard(tester, find.text('Drop').last);
      expect(find.textContaining('Drop zone'), findsOneWidget);
      expect(
        find.text('Play from drop'),
        findsNothing,
        reason: 'a unit is not played, it activates',
      );
      expect(find.text('Activate from drop'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget, reason: 'for the costs');
    });

    testWidgets('a card removed from the drop by hand leaves the game', (
      tester,
    ) async {
      final (store, deck) = await buildDeck();
      await pump(tester, store, deck);
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();

      final game = Provider.of<PlaytestController>(
        tester.element(find.byType(Scaffold)),
        listen: false,
      );
      await tapOnBoard(tester, callableHandCard().first);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      final discarded = game.you.drop.single;

      await tapOnBoard(tester, find.text('Drop').last);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(game.you.drop, isEmpty);
      expect(game.you.removed, contains(discarded));
      expect(find.text('Removed'), findsOneWidget);
    });

    testWidgets('the top cards can be looked at and taken to hand', (
      tester,
    ) async {
      final (store, deck) = await buildDeck();
      await pump(tester, store, deck);
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();

      final game = Provider.of<PlaytestController>(
        tester.element(find.byType(Scaffold)),
        listen: false,
      );
      final top = game.engine.topOfDeck(game.you, 5);
      final hand = game.you.hand.length;

      await tapOnBoard(tester, find.text('Deck').last);
      await tester.tap(find.text('Look at the top cards'));
      await tester.pumpAndSettle();

      // Five by default, and the count can be changed without reopening.
      expect(find.textContaining('Top 5 of the deck'), findsOneWidget);
      // By the chip, not by the text: the board behind has counters on it
      // that are also single digits.
      await tester.tap(find.widgetWithText(ChoiceChip, '3'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Top 3 of the deck'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, '5'));
      await tester.pumpAndSettle();

      // The first card listed is the top of the deck, and it goes to hand.
      expect(find.text('To hand'), findsWidgets);
      await tester.tap(find.text('To hand').first);
      await tester.pumpAndSettle();

      expect(game.you.hand.length, hand + 1);
      expect(game.you.hand.contains(top.first), isTrue);
      expect(game.you.deck.contains(top.first), isFalse);
      // What was under it is still in the same order.
      expect(game.engine.topOfDeck(game.you, 1), [top[1]]);
    });

    testWidgets('taking one of the top cards does not turn over another', (
      tester,
    ) async {
      final (store, deck) = await buildDeck();
      await pump(tester, store, deck);
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();

      final game = Provider.of<PlaytestController>(
        tester.element(find.byType(Scaffold)),
        listen: false,
      );
      final top = game.engine.topOfDeck(game.you, 5);
      final sixth = game.engine.topOfDeck(game.you, 6).last;

      await tapOnBoard(tester, find.text('Deck').last);
      await tester.tap(find.text('Look at the top cards'));
      await tester.pumpAndSettle();

      // Every card in this deck shares a handful of names, so the window is
      // checked by what the sheet says it is showing rather than by name.
      await tester.tap(find.text('To hand').first);
      await tester.pumpAndSettle();

      // Four left to choose from: the list shrank rather than refilling from
      // underneath, which is what taking one out of a look means.
      expect(find.textContaining('4 of 5 left'), findsOneWidget);
      expect(game.you.hand.contains(top.first), isTrue);
      expect(
        game.you.deck.contains(sixth),
        isTrue,
        reason: 'the card under the five was never turned over',
      );
      expect(
        game.engine.topOfDeck(game.you, 1).single,
        top[1],
        reason: 'the deck simply lost the card that was taken',
      );
    });

    testWidgets('the look at the top can shuffle afterwards, or not', (
      tester,
    ) async {
      final (store, deck) = await buildDeck();
      await pump(tester, store, deck);
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();

      final game = Provider.of<PlaytestController>(
        tester.element(find.byType(Scaffold)),
        listen: false,
      );

      await tapOnBoard(tester, find.text('Deck').last);
      await tester.tap(find.text('Look at the top cards'));
      await tester.pumpAndSettle();

      final before = [...game.you.deck];
      await scrollSheetTo(tester, find.text('Leave the order'));
      await tester.tap(find.text('Leave the order'));
      await tester.pumpAndSettle();
      expect(game.you.deck, before, reason: 'left exactly as it was');
    });

    testWidgets('a card in hand goes under the deck', (tester) async {
      final (store, deck) = await buildDeck();
      await pump(tester, store, deck);
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();

      await tapOnBoard(tester, find.text('Deck').last);
      final before = find.textContaining(RegExp(r'^Deck \(\d+\)$'));
      final count = tester.widget<Text>(before).data!;
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      await tapOnBoard(tester, callableHandCard().first);
      await tester.tap(find.text('To the bottom of the deck'));
      await tester.pumpAndSettle();

      // The deck is one card bigger than it was, and the card left the hand
      // without passing through the drop zone.
      await tapOnBoard(tester, find.text('Deck').last);
      expect(
        tester.widget<Text>(before).data,
        isNot(count),
        reason: 'the deck grew',
      );
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await tapOnBoard(tester, find.text('Drop').last);
      expect(find.textContaining('Drop zone (0)'), findsOneWidget);
    });

    testWidgets('a rear-guard goes under the deck', (tester) async {
      final (store, deck) = await buildDeck();
      await pump(tester, store, deck);
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();
      await tester.tap(find.text('Ride'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Ride deck · grade 1'));
      await tester.pumpAndSettle();
      // A ride out of the ride deck costs a card, and which one is asked.
      await tester.tap(find.text('Discard').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pump();

      await tapOnBoard(tester, callableHandCard().first);
      await tester.tap(find.text('Call to a circle'));
      await tester.pumpAndSettle();
      await tapOnBoard(
        tester,
        find.byKey(const ValueKey('circle-You-backLeft')),
      );

      await tapOnBoard(
        tester,
        find.byKey(const ValueKey('circle-You-backLeft')),
      );
      await tester.tap(find.text('To bottom of deck'));
      await tester.pumpAndSettle();

      // The circle is empty again, and the drop holds only what paid for the
      // ride -- the unit went under the deck, which is what separates this
      // from a retire.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('circle-You-backLeft')),
          matching: find.text('—'),
        ),
        findsOneWidget,
      );
      await tapOnBoard(tester, find.text('Drop').last);
      expect(find.textContaining('Drop zone (1)'), findsOneWidget);
      expect(find.text('Booster'), findsNothing, reason: 'not retired');
    });

    testWidgets('the vanguard is never offered the bottom of the deck', (
      tester,
    ) async {
      final (store, deck) = await buildDeck();
      await pump(tester, store, deck);
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();

      await tapOnBoard(
        tester,
        find.byKey(const ValueKey('circle-You-vanguard')),
      );
      expect(find.text('To bottom of deck'), findsNothing);
      expect(find.text('Retire'), findsNothing, reason: 'nor a retire');
      expect(find.text('To soul'), findsNothing, reason: 'nor the soul');
    });

    testWidgets('a rear-guard goes into the soul from its sheet', (
      tester,
    ) async {
      final (store, deck) = await buildDeck();
      await pump(tester, store, deck);
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();

      final game = Provider.of<PlaytestController>(
        tester.element(find.byType(Scaffold)),
        listen: false,
      );

      // Calling happens in the main phase, so ride first and move on.
      await tester.tap(find.text('Ride'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Ride deck · grade 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pump();

      await tapOnBoard(tester, callableHandCard().first);
      await tester.tap(find.text('Call to a circle'));
      await tester.pumpAndSettle();
      await tapOnBoard(
        tester,
        find.byKey(const ValueKey('circle-You-backLeft')),
      );
      final called = game.you.field[Circle.backLeft]!.card;

      await tapOnBoard(
        tester,
        find.byKey(const ValueKey('circle-You-backLeft')),
      );
      await scrollSheetTo(tester, find.text('To soul'));
      await tester.tap(find.text('To soul'));
      await tester.pumpAndSettle();

      expect(game.you.field[Circle.backLeft], isNull);
      expect(game.you.soul.contains(called), isTrue);
      expect(
        game.you.drop.contains(called),
        isFalse,
        reason: 'the soul is not the drop',
      );
    });

    testWidgets('the drop zone sends a card under the deck', (tester) async {
      final (store, deck) = await buildDeck();
      await pump(tester, store, deck);
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();

      await tapOnBoard(tester, callableHandCard().first);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      await tapOnBoard(tester, find.text('Drop').last);
      expect(find.text('To bottom'), findsOneWidget);
      await tester.tap(find.text('To bottom'));
      await tester.pumpAndSettle();

      await tapOnBoard(tester, find.text('Drop').last);
      expect(find.textContaining('Drop zone (0)'), findsOneWidget);
    });

    testWidgets('the CPU main phase is stepped from the board', (tester) async {
      final (store, deck) = await buildDeck();
      await pump(tester, store, deck);
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();
      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.tap(find.text('Next'));
      await tester.pump();
      // Battle to the end phase, and the end phase hands the turn over.
      await tester.tap(find.text('End turn'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      // The board hands over to the CPU and waits, rather than showing a
      // finished board with no account of how it got there.
      expect(find.text('The CPU takes its turn.'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('rides'),
        findsOneWidget,
        reason: 'it says what it just did',
      );
    });

    testWidgets('a rear-guard can be locked and unlocked', (tester) async {
      final (store, deck) = await buildDeck();
      await pump(tester, store, deck);
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();
      await tester.tap(find.text('Ride'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Ride deck · grade 1'));
      await tester.pumpAndSettle();
      // A ride out of the ride deck costs a card, and which one is asked.
      await tester.tap(find.text('Discard').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pump();

      await tapOnBoard(tester, callableHandCard().first);
      await tester.tap(find.text('Call to a circle'));
      await tester.pumpAndSettle();
      await tapOnBoard(
        tester,
        find.byKey(const ValueKey('circle-You-backLeft')),
      );

      // Lock it, and the circle turns face down.
      await tapOnBoard(
        tester,
        find.byKey(const ValueKey('circle-You-backLeft')),
      );
      expect(find.text('Lock'), findsOneWidget);
      await tester.tap(find.text('Lock'));
      await tester.pumpAndSettle();
      expect(find.text('LOCKED'), findsOneWidget);

      // Its sheet offers nothing but turning it back over.
      await tapOnBoard(
        tester,
        find.byKey(const ValueKey('circle-You-backLeft')),
      );
      expect(find.text('Unlock'), findsOneWidget);
      expect(find.text('Retire'), findsNothing, reason: 'it is not a unit');
      expect(find.text('+1 critical'), findsNothing);

      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(find.text('LOCKED'), findsNothing);
    });

    testWidgets('the CPU\'s units can be locked too', (tester) async {
      final (store, deck) = await buildDeck();
      await pump(tester, store, deck);
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();

      // Its starting vanguard is all it has, and a vanguard is never locked.
      await tapOnBoard(
        tester,
        find.byKey(const ValueKey('circle-CPU-vanguard')),
      );
      expect(find.text('Lock'), findsNothing);
    });

    testWidgets('a deck with no crest can be given one', (tester) async {
      final (store, deck) = await buildDeck();
      // A crest in the library but not in the deck, which is the case a
      // stride deck is in: no crest of its own, one available to play.
      store.saveCard(
        gameId: 'vanguard',
        name: 'Energy Generator',
        attributes: {
          'cardType': 'ride-deck-crest',
          'effect':
              '[AUTO]: At the beginning of your ride phase, '
              '[Energy-Charge 3].',
        },
      );
      await pump(tester, store, deck);
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();

      // The crest zone is on the board even with nothing in it.
      expect(find.text('Crest'), findsNWidgets(2));
      await tapOnBoard(tester, find.text('Crest').last);
      // The crests on offer are below the energy controls.
      await scrollSheetTo(tester, find.text('Energy Generator'));
      expect(find.textContaining('crest zone'), findsWidgets);
      expect(find.text('Energy Generator'), findsOneWidget);

      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      // It is in the zone, saying what it charges, with a way back out.
      await tapOnBoard(tester, find.text('Crest').last);
      expect(find.textContaining('Crest zone (1)'), findsOneWidget);
      expect(find.textContaining('Charges 3'), findsOneWidget);
      expect(find.text('Take it out'), findsOneWidget);

      await tester.tap(find.text('Take it out'));
      await tester.pumpAndSettle();
      await tapOnBoard(tester, find.text('Crest').last);
      await scrollSheetTo(tester, find.text('Energy Generator'));
      expect(
        find.text('Energy Generator'),
        findsOneWidget,
        reason: 'offered again',
      );
    });

    testWidgets('a stride deck crest charges nothing and says so', (
      tester,
    ) async {
      final (store, deck) = await buildDeck();
      store.saveCard(
        gameId: 'vanguard',
        name: 'Masked Magician, Harri',
        attributes: {
          'cardType': 'crest',
          'effect':
              '[CONT]:You can perform [Stride], and cannot ride grade 3 '
              'or greater cards without "Harri" in their card names.',
        },
      );
      await pump(tester, store, deck);
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();

      await tapOnBoard(tester, find.text('Crest').last);
      await scrollSheetTo(tester, find.text('Play'));
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      await tapOnBoard(tester, find.text('Crest').last);
      // It is permission to stride, not an energy engine, so it does not
      // claim to charge zero every turn.
      expect(find.textContaining('Charges no energy'), findsOneWidget);
      expect(find.textContaining('Charges 0'), findsNothing);
    });

    testWidgets('a crest is played beside the one already there', (
      tester,
    ) async {
      // The Energy Generator comes out of the ride deck; the stride deck's
      // crest is played on top of that, without taking the generator out.
      final (store, deck) = await buildEnergyDeck();
      store.saveCard(
        gameId: 'vanguard',
        name: 'Vampire Princess of Night Fog, Nightrose',
        attributes: {
          'cardType': 'crest',
          'effect': '[CONT]:You can perform [Stride].',
        },
      );
      await pump(tester, store, deck);
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();
      await tester.tap(find.text('Ride'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Ride deck · grade 1'));
      await tester.pumpAndSettle();
      // A ride out of the ride deck costs a card, and which one is asked.
      await tester.tap(find.text('Discard').first);
      await tester.pumpAndSettle();

      await tapOnBoard(tester, find.text('Crest').last);
      expect(find.textContaining('Crest zone (1)'), findsOneWidget);

      // The crest zone offers another without asking for the first back. The
      // list of them sits below what is already in the zone, so scroll to it.
      // Passed unfiltered: `.first` on a finder with nothing in it throws
      // rather than reporting empty, which is no use for a scroll loop.
      await scrollSheetTo(tester, find.text('Play'));
      await tester.tap(find.text('Play').first);
      await tester.pumpAndSettle();

      await tapOnBoard(tester, find.text('Crest').last);
      expect(find.textContaining('Crest zone (2)'), findsOneWidget);

      // Both are in it, each saying what it charges. The sheet is taller than
      // the screen with two crests in it, so it takes a scroll to see them.
      for (
        var i = 0;
        i < 8 && find.textContaining('Charges no energy').evaluate().isEmpty;
        i += 1
      ) {
        await tester.drag(find.byType(Scrollable).last, const Offset(0, -120));
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('Charges 3'), findsOneWidget);
      expect(find.textContaining('Charges no energy'), findsOneWidget);
      expect(find.text('Take it out'), findsNWidgets(2));
    });

    testWidgets('the ride deck asks which card pays for it', (tester) async {
      final (store, deck) = await buildDeck();
      await pump(tester, store, deck);
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();

      await tester.tap(find.text('Ride'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('discard a card to ride it'),
        findsOneWidget,
        reason: 'the cost is on the row',
      );

      await tester.tap(find.textContaining('Ride deck · grade 1'));
      await tester.pumpAndSettle();

      // The hand is laid out to choose from rather than a card being taken.
      expect(find.textContaining('Discard a card from hand'), findsOneWidget);
      expect(find.text('Discard'), findsWidgets);

      await tester.tap(find.text('Discard').first);
      await tester.pumpAndSettle();

      // The ride happened and the discard is in the drop zone.
      expect(find.text('Ride'), findsNothing, reason: 'ridden already');
      await tapOnBoard(tester, find.text('Drop').last);
      expect(find.textContaining('Drop zone (1)'), findsOneWidget);
    });

    testWidgets('turn one says why you cannot attack', (tester) async {
      final (store, deck) = await buildDeck();
      await pump(tester, store, deck);
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();
      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.tap(find.text('Next'));
      await tester.pump();

      // The battle phase, and the board says the rule rather than simply
      // not responding to a tap.
      expect(
        find.textContaining('whoever goes first does not attack'),
        findsOneWidget,
      );

      // And tapping a unit does not start an attack.
      await tapOnBoard(
        tester,
        find.byKey(const ValueKey('circle-You-vanguard')),
      );
      expect(
        find.textContaining('Drive check ×'),
        findsNothing,
        reason: 'no attack was declared',
      );
      // It opened the unit sheet instead, which is what a tap means when
      // attacking is not on offer.
      expect(find.text('+1 critical'), findsOneWidget);
    });

    testWidgets('a removed over trigger shows on the board', (tester) async {
      // A deck of nothing but over triggers, so the first damage check is one.
      final (store, deck) = await buildDeck();
      for (final name in ['Critical Trigger', 'Beater', 'Booster']) {
        final card = store.cards.firstWhere((c) => c.name == name);
        store.setQuantity(deck.id, card.id, zoneMain, 0);
      }
      final over = store.saveCard(
        gameId: 'vanguard',
        name: 'Over Trigger',
        attributes: {
          'grade': '0',
          'cardType': 'trigger',
          'trigger': 'over',
          'power': '15000',
          'shield': '0',
        },
      );
      store.addToDeck(deck.id, over.id, zoneMain, quantity: 50);
      await pump(tester, store, store.decks.firstWhere((d) => d.id == deck.id));
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();

      expect(find.text('Removed'), findsNothing, reason: 'nothing gone yet');

      // Take a damage by hand, which checks the top card.
      await tapOnBoard(
        tester,
        find.byKey(const ValueKey('circle-You-vanguard')),
      );
      await tester.tap(find.text('Take damage'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      // No damage taken, and the card is on the removed pile instead.
      expect(find.text('No damage'), findsNWidgets(2));
      expect(find.text('Removed'), findsOneWidget);

      await tapOnBoard(tester, find.text('Removed'));
      expect(find.textContaining('Removed from the game'), findsOneWidget);
      expect(find.textContaining('Nothing comes back'), findsOneWidget);
    });

    testWidgets('both sides are played from one board', (tester) async {
      final (store, deck) = await buildDeck();
      await pump(tester, store, deck, mode: PlaytestMode.bothSides);

      // Both openings are yours, one after the other.
      expect(find.textContaining('Player 1'), findsWidgets);
      await tester.tap(find.text('Keep this hand'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Player 2\u2019s opening hand'),
        findsOneWidget,
        reason: 'the second hand is yours too',
      );
      await tester.tap(find.text('Keep this hand'));
      await tester.pumpAndSettle();

      // The board names whose turn it is and whose hand is on the strip.
      expect(find.text('Turn 1 · Player 1'), findsOneWidget);
      expect(find.text('Player 1\u2019s hand'), findsOneWidget);
      expect(
        find.textContaining('The CPU'),
        findsNothing,
        reason: 'there is no CPU in this mode',
      );

      // Ending the turn hands the board to the other player rather than to a
      // CPU that plays itself.
      for (var i = 0; i < 6; i += 1) {
        if (find.text('Turn 2 · Player 2').evaluate().isNotEmpty) break;
        final button = find.text('End turn').evaluate().isNotEmpty
            ? find.text('End turn')
            : find.text('Next');
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      expect(find.text('Turn 2 · Player 2'), findsOneWidget);
      expect(find.text('Player 2\u2019s hand'), findsOneWidget);
      expect(find.text('Continue'), findsNothing, reason: 'no CPU to step');
    });

    testWidgets('the back button asks before throwing the game away', (
      tester,
    ) async {
      final (store, deck) = await buildDeck();
      await pump(tester, store, deck);
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();

      // The system back press, as a phone sends it.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Leave the game?'), findsOneWidget);
      expect(find.textContaining('The board goes with it'), findsOneWidget);

      // Keeping playing leaves the board exactly where it was.
      await tester.tap(find.text('Keep playing'));
      await tester.pumpAndSettle();
      expect(find.text('Leave the game?'), findsNothing);
      expect(
        find.textContaining('Turn 1'),
        findsOneWidget,
        reason: 'still on the board',
      );
    });

    testWidgets('a game that is over does not ask', (tester) async {
      final (store, deck) = await buildDeck();
      await pump(tester, store, deck);
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();

      final game = Provider.of<PlaytestController>(
        tester.element(find.byType(Scaffold)),
        listen: false,
      );
      // Six damage ends it, and a finished board has nothing left to lose.
      while (game.cpu.damageCount < 6) {
        game.dealDamage(game.cpu);
      }
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Leave the game?'), findsNothing);
    });

    testWidgets('a ticket can be taken into hand from the board', (
      tester,
    ) async {
      final (store, deck) = await buildDeck();
      // The ticket comes out of the card database in the app; a test has no
      // catalog, so the library carries it here the way a saved card would.
      store.saveCard(
        gameId: 'vanguard',
        name: 'Persona Shield',
        attributes: {
          'grade': '0',
          'cardType': 'order-blitz',
          'cardNo': 'DZ-BT15/T01EN',
          'effect':
              '(This card is a ticket card, and cannot be put in a deck)\n'
              'Choose a unit being attacked, it gets [Power]+10000 until end '
              'of that battle.',
        },
      );
      await pump(tester, store, deck);
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();

      final game = Provider.of<PlaytestController>(
        tester.element(find.byType(Scaffold)),
        listen: false,
      );
      final hand = game.you.hand.length;
      final deckSize = game.you.deck.length;

      await tapOnBoard(tester, find.text('Tickets'));
      expect(find.text('Persona Shield'), findsOneWidget);
      expect(find.textContaining('DZ-BT15/T01EN'), findsOneWidget);

      await tester.tap(find.text('To hand'));
      await tester.pumpAndSettle();

      expect(game.you.hand.length, hand + 1);
      expect(game.you.hand.last.name, 'Persona Shield');
      expect(game.you.hand.last.isTicket, isTrue);
      expect(game.you.deck.length, deckSize, reason: 'the deck was untouched');
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
