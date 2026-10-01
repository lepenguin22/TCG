import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tcg_decks/playtest/ability_reader.dart';
import 'package:tcg_decks/playtest/playtest_controller.dart';
import 'package:tcg_decks/playtest/playtest_state.dart';
import 'package:tcg_decks/screens/playtest_screen.dart';
import 'package:tcg_decks/store/deck_store.dart';
import 'package:tcg_decks/theme.dart';

import 'ability_deck.dart' show deckWith, engineFor, logHas;

/// The abilities the board cannot play but can still raise.
///
/// The reader's executable half is all-or-nothing, which leaves most of a
/// real deck as text on a card. These are the ones it can time and price but
/// not carry out: the board offers them at the right moment, pays for them,
/// and the player applies what they say.

/// A clause the reader will never execute: it names a target, and choosing
/// one is exactly what the board cannot do on its own.
const targeting =
    '[AUTO](RC):When this unit is placed on (RC), [COST][Counter-Blast 1], '
    'choose one of your rear-guards, and [Stand] it.';

/// The same, with nothing to pay: what reaches the board on a ride.
const freeTargeting =
    '[AUTO](VC):When this unit is placed on (VC), choose one of your '
    'rear-guards, and [Stand] it.';

GameCard spare(PlaytestSide side, String name) => side.hand.firstWhere(
  (c) => c.name == name,
  orElse: () => side.deck.firstWhere((c) => c.name == name),
);

void main() {
  group('reading an ability only as far as the player needs', () {
    test('a clause it cannot carry out is still timed and priced', () {
      final read = readAbilities(targeting);

      expect(read.prompted, hasLength(1));
      final prompt = read.prompted.single;
      expect(prompt.timing, AbilityTiming.onCall);
      expect(prompt.cost.counterBlast, 1);
      expect(prompt.text, targeting, reason: 'shown to the player as printed');
    });

    test('a clause the board could once play out is offered too', () {
      final read = readAbilities(
        '[AUTO](RC):When this unit is placed on (RC), draw a card.',
      );

      expect(read.prompted, hasLength(1), reason: 'offered, not played');
      expect(read.prompted.single.timing, AbilityTiming.onCall);
      expect(read.unread, isEmpty);
    });

    test('a cost it cannot read is not offered, since it could not pay it', () {
      final read = readAbilities(
        '[AUTO](RC):When this unit is placed on (RC), '
        '[COST][Choose a card from your hand, and bind it], draw a card.',
      );

      expect(read.prompted, isEmpty);
    });

    test('a continuous ability has no moment to be offered at', () {
      final read = readAbilities(
        '[CONT](RC):All of your opponent\'s units in the front row '
        'get [Power]-2000.',
      );

      expect(read.prompted, isEmpty);
    });

    test('a cost that spends the unit itself is not offered', () {
      final read = readAbilities(
        '[AUTO](RC):When this unit attacks, [COST][Retire this unit], '
        'choose one of your opponent\'s rear-guards, and retire it.',
      );

      expect(
        read.prompted,
        isEmpty,
        reason: 'the unit would be gone before the player applied it',
      );
    });

    test('a clause it made nothing of is kept as text', () {
      final read = readAbilities(
        '[CONT](VC):Your opponent cannot call units to (GC) from hand.',
      );

      expect(read.prompted, isEmpty);
      expect(read.unread, hasLength(1));
    });
  });

  group('the board raising an ability at its moment', () {
    test('calling a unit offers what the board cannot play', () async {
      final (store, deck) = await deckWith(boosterEffect: targeting);
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      engine.dealDamage(you); // Something to counter-blast.

      engine.call(you, spare(you, 'Booster'), Circle.frontLeft);

      expect(engine.state.prompts, hasLength(1));
      expect(engine.state.prompts.single.card.name, 'Booster');
      expect(engine.state.prompts.single.circle, Circle.frontLeft);
    });

    test('the far side is offered its own, both hands being yours', () async {
      final (store, deck) = await deckWith(boosterEffect: targeting);
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final far = engine.state.opponent;
      engine.dealDamage(far);

      engine.call(far, spare(far, 'Booster'), Circle.frontLeft);

      expect(engine.state.prompts, hasLength(1));
      expect(engine.state.prompts.single.side, far);
    });

    test('an offer it could not pay for is not made', () async {
      final (store, deck) = await deckWith(boosterEffect: targeting);
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;

      // No damage taken, so there is nothing to counter-blast.
      engine.call(you, spare(you, 'Booster'), Circle.frontLeft);

      expect(engine.state.prompts, isEmpty);
    });

    test('accepting pays the cost and writes it into the log', () async {
      final (store, deck) = await deckWith(boosterEffect: targeting);
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      engine.dealDamage(you);
      engine.call(you, spare(you, 'Booster'), Circle.frontLeft);
      final open = you.openDamage;

      final taken = engine.takePrompt(engine.state.prompts.single);

      expect(taken, isTrue);
      expect(you.openDamage, open - 1, reason: 'the counter-blast was paid');
      expect(logHas(engine, 'plays Booster'), isTrue);
      expect(engine.state.prompts, isEmpty);
    });

    test('skipping pays nothing and claims nothing', () async {
      final (store, deck) = await deckWith(boosterEffect: targeting);
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      engine.dealDamage(you);
      engine.call(you, spare(you, 'Booster'), Circle.frontLeft);
      final open = you.openDamage;

      engine.dismissPrompt(engine.state.prompts.single);

      expect(you.openDamage, open, reason: 'nothing was spent');
      expect(logHas(engine, 'plays Booster'), isFalse);
      expect(engine.state.prompts, isEmpty);
    });

    test('an offer left standing goes away with the turn', () async {
      final (store, deck) = await deckWith(boosterEffect: targeting);
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      engine.dealDamage(you);
      engine.call(you, spare(you, 'Booster'), Circle.frontLeft);
      expect(engine.state.prompts, hasLength(1));

      engine.endTurn();

      expect(engine.state.prompts, isEmpty);
    });

    test('the same clause reached twice is one offer', () async {
      final (store, deck) = await deckWith(boosterEffect: targeting);
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      engine.dealDamage(you);

      engine.call(you, spare(you, 'Booster'), Circle.frontLeft);
      engine.raisePrompts(you, Circle.frontLeft, AbilityTiming.onCall);

      expect(engine.state.prompts, hasLength(1));
    });
  });

  group('the board showing an offer', () {
    test('an offer is only shown to the side that owns it', () async {
      final (store, deck) = await deckWith(boosterEffect: targeting);
      final game = PlaytestController(
        store: store,
        yourDeck: deck,
        opponentDeck: deck,
        random: Random(7),
      );
      game.confirmMulligan();
      final you = game.you;
      game.engine.dealDamage(you);
      game.engine.call(you, spare(you, 'Booster'), Circle.frontLeft);

      expect(game.prompts, hasLength(1));
      expect(game.prompts.single.side, you);
    });

    test('taking an offer tells the board to rebuild', () async {
      final (store, deck) = await deckWith(boosterEffect: targeting);
      final game = PlaytestController(
        store: store,
        yourDeck: deck,
        opponentDeck: deck,
        random: Random(7),
      );
      game.confirmMulligan();
      game.engine.dealDamage(game.you);
      game.engine.call(game.you, spare(game.you, 'Booster'), Circle.frontLeft);

      var told = 0;
      game.addListener(() => told += 1);
      game.takePrompt(game.prompts.single);

      expect(told, greaterThan(0));
      expect(game.prompts, isEmpty);
    });

    testWidgets('the strip appears when an ability is waiting', (tester) async {
      final (store, deck) = await deckWith(
        boosterEffect: '',
        vanguardEffect: freeTargeting,
      );
      await tester.pumpWidget(
        ChangeNotifierProvider<DeckStore>.value(
          value: store,
          child: MaterialApp(
            theme: buildTheme(),
            home: PlaytestScreen(
              yourDeck: deck,
              opponentDeck: deck,
              random: Random(7),
            ),
          ),
        ),
      );
      await tester.pump();
      // Both openings are yours, so the hand is kept twice.
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();

      // Nothing has been ridden yet, so nothing is waiting.
      expect(find.textContaining('ability now'), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, 'Ride'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Ride deck · grade 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard').first);
      await tester.pumpAndSettle();

      // The ride put a unit on (VC) with an ability the board cannot play.
      expect(find.textContaining('ability now'), findsOneWidget);

      await tester.tap(find.textContaining('ability now'));
      await tester.pumpAndSettle();
      expect(find.text('Abilities now'), findsOneWidget);
      expect(find.textContaining('choose one of your rear-guards'), findsOne);

      await tester.tap(find.text('Use'));
      await tester.pumpAndSettle();

      // Taken, so the sheet closed and the strip went with it.
      expect(find.textContaining('ability now'), findsNothing);
    });
  });
}
