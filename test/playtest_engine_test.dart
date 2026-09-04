import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tcg_decks/games/vanguard/vanguard_data.dart';
import 'package:tcg_decks/models/deck.dart';
import 'package:tcg_decks/playtest/playtest_ai.dart';
import 'package:tcg_decks/playtest/playtest_engine.dart';
import 'package:tcg_decks/playtest/playtest_state.dart';
import 'package:tcg_decks/store/deck_store.dart';

/// A deck that can actually be played: a full ride deck and enough main deck
/// to check damage against without running out.
Future<(DeckStore, Deck)> buildDeck({
  String name = 'Test deck',
  int triggers = 16,
}) async {
  SharedPreferences.setMockInitialValues({});
  final store = DeckStore();
  await store.load();
  final deck = store.createDeck(name: name, formatId: formatStandard);

  void add(
    String cardName,
    String zone,
    int quantity,
    Map<String, String> attributes,
  ) {
    final card = store.saveCard(
      gameId: 'vanguard',
      name: cardName,
      attributes: attributes,
    );
    store.addToDeck(deck.id, card.id, zone, quantity: quantity);
  }

  // The ride deck: one unit of each grade to climb through.
  for (var grade = 0; grade <= 3; grade += 1) {
    add('Ride $grade', zoneRide, 1, {
      'grade': '$grade',
      'cardType': 'normal',
      'power': '${9000 + grade * 2000}',
      'shield': grade == 0 ? '10000' : '0',
      'effect': 'Ride deck unit $grade.',
    });
  }

  add('Critical Trigger', zoneMain, triggers, {
    'grade': '0',
    'cardType': 'trigger',
    'trigger': 'critical',
    'power': '5000',
    'shield': '15000',
  });
  add('Beater', zoneMain, 20, {
    'grade': '2',
    'cardType': 'normal',
    'power': '13000',
    'shield': '5000',
  });
  add('Booster', zoneMain, 14 + (16 - triggers), {
    'grade': '1',
    'cardType': 'normal',
    'power': '8000',
    'shield': '10000',
  });

  return (store, store.decks.firstWhere((d) => d.id == deck.id));
}

/// The same deck with a G zone bolted on, as a Premium deck that strides has.
Future<(DeckStore, Deck)> buildStrideDeck() async {
  final (store, deck) = await buildDeck();
  final gUnit = store.saveCard(
    gameId: 'vanguard',
    name: 'Stride Beast',
    attributes: {
      'grade': '4',
      'cardType': 'g-unit',
      'power': '15000',
      'effect': 'A G unit.',
    },
  );
  store.addToDeck(deck.id, gUnit.id, zoneG, quantity: 8);
  return (store, store.decks.firstWhere((d) => d.id == deck.id));
}

PlaytestEngine engineFor(DeckStore store, Deck deck, {int seed = 7}) =>
    PlaytestEngine.start(
      store: store,
      yourDeck: deck,
      opponentDeck: deck,
      random: Random(seed),
    );

void main() {
  group('setting up a game', () {
    test('both sides start with a grade 0 vanguard and five cards', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);

      expect(engine.state.you.vanguard, isNotNull);
      expect(engine.state.you.vanguard!.card.grade, 0);
      expect(engine.state.you.hand.length, 5);
      // The CPU has already taken its own mulligan, so its hand is five too.
      expect(engine.state.opponent.hand.length, 5);
    });

    test('the ride deck keeps the grades still to be ridden', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);

      // The grade 0 stood up as the first vanguard, leaving 1, 2 and 3.
      expect(
        engine.state.you.rideDeck.map((c) => c.grade),
        containsAllInOrder([1, 2, 3]),
      );
      expect(engine.state.you.rideDeck.length, 3);
    });

    test(
      'the main deck holds every copy and nothing from the ride deck',
      () async {
        final (store, deck) = await buildDeck();
        final engine = engineFor(store, deck);
        final side = engine.state.you;

        // 50 main deck cards, less the five drawn for the opening hand.
        expect(side.deck.length + side.hand.length, 50);
        expect(side.deck.any((c) => c.name.startsWith('Ride')), isFalse);
      },
    );

    test('a deck with no grade 0 cannot be played', () async {
      final (store, deck) = await buildDeck();
      final view = store.viewOf(deck);
      expect(playtestBlocker(view), isNull);

      // Take the first vanguard away and the game has nothing to start with.
      final grade0 = view.items.firstWhere(
        (i) => i.entry.zoneId == zoneRide && i.card.attributes['grade'] == '0',
      );
      store.setQuantity(deck.id, grade0.card.id, zoneRide, 0);
      final without = store.viewOf(store.decks.first);
      expect(playtestBlocker(without), contains('no grade 0'));
    });
  });

  group('riding', () {
    test('the ride deck is climbed one grade at a time', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final side = engine.state.you;

      // From a grade 0 vanguard, only the grade 1 is available.
      final first = engine.rideDeckOption(side);
      expect(first!.grade, 1);
      engine.ride(side, first, fromRideDeck: true);
      expect(side.vanguard!.card.grade, 1);

      // And the unit ridden over goes to the soul.
      expect(side.soul.single.grade, 0);
    });

    test('a ride cannot skip a grade', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final side = engine.state.you;

      // The grade 3 is in the ride deck, but a grade 0 vanguard cannot reach
      // it: only the grade 1 is offered.
      expect(side.rideDeck.any((c) => c.grade == 3), isTrue);
      expect(engine.rideDeckOption(side)!.grade, 1);
    });

    test('only one ride a turn', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final side = engine.state.you;

      expect(engine.canRide(side), isTrue);
      engine.ride(side, engine.rideDeckOption(side)!, fromRideDeck: true);
      expect(engine.canRide(side), isFalse);
    });
  });

  group('calling units', () {
    test('a unit cannot be called above the vanguard grade', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final side = engine.state.you;

      // The vanguard is still grade 0, so a grade 2 beater cannot be called.
      final beater = GameCard(
        999,
        store.cards.firstWhere((c) => c.name == 'Beater'),
      );
      expect(engine.canCall(side, beater, Circle.frontLeft), isFalse);

      engine.ride(side, engine.rideDeckOption(side)!, fromRideDeck: true);
      engine.ride(side, side.rideDeck.first, fromRideDeck: true);
      expect(side.vanguard!.card.grade, 2);
      expect(engine.canCall(side, beater, Circle.frontLeft), isTrue);
    });

    test('nothing may be called onto the vanguard circle', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      final side = engine.state.you;
      final booster = GameCard(
        998,
        store.cards.firstWhere((c) => c.name == 'Booster'),
      );
      expect(engine.canCall(side, booster, Circle.vanguard), isFalse);
    });

    test('calling over a unit sends the old one to the drop', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final side = engine.state.you;
      engine.ride(side, engine.rideDeckOption(side)!, fromRideDeck: true);

      final first = side.hand.firstWhere((c) => c.grade <= 1 && c.isUnit);
      engine.call(side, first, Circle.frontLeft);
      final second = side.hand.firstWhere((c) => c.grade <= 1 && c.isUnit);
      engine.call(side, second, Circle.frontLeft);

      expect(side.field[Circle.frontLeft]!.card, second);
      expect(side.drop, contains(first));
    });
  });

  group('the board', () {
    test('only the front row can attack or be attacked', () {
      expect(Circle.vanguard.isFrontRow, isTrue);
      expect(Circle.frontLeft.isFrontRow, isTrue);
      expect(Circle.backCenter.isFrontRow, isFalse);
      // Which is what keeps a booster safe where it stands.
      expect(Circle.backLeft.isFrontRow, isFalse);
    });

    test('the back row boosts the circle in front of it', () {
      expect(Circle.backCenter.boosts, Circle.vanguard);
      expect(Circle.backLeft.boosts, Circle.frontLeft);
      expect(Circle.vanguard.boostedBy, Circle.backCenter);
      expect(Circle.frontRight.boostedBy, Circle.backRight);
    });
  });

  group('attacking', () {
    /// A game with both sides ridden up to grade 2 and a board to fight with.
    (PlaytestEngine, PlaytestSide, PlaytestSide) readyGame(
      DeckStore store,
      Deck deck,
    ) {
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      final foe = engine.state.opponent;
      for (final side in [you, foe]) {
        while (engine.rideDeckOption(side) != null &&
            (side.vanguard?.card.grade ?? 0) < 2) {
          engine.ride(side, engine.rideDeckOption(side)!, fromRideDeck: true);
        }
      }
      engine.state.phase = PlaytestPhase.battle;
      return (engine, you, foe);
    }

    test('an attack that beats the defence connects', () async {
      final (store, deck) = await buildDeck();
      final (engine, you, foe) = readyGame(store, deck);

      final attack = engine.declareAttack(
        from: Circle.vanguard,
        to: Circle.vanguard,
      );
      // Grade 2 ride deck units are 13000 a side, so an unguarded attack hits.
      expect(attack.attackPower, foe.vanguard!.power);
      expect(attack.connects, isTrue);
    });

    test('shield can hold an attack off', () async {
      final (store, deck) = await buildDeck();
      final (engine, you, foe) = readyGame(store, deck);

      engine.declareAttack(from: Circle.vanguard, to: Circle.vanguard);
      final shield = engine.guardOptions(foe).firstWhere((c) => c.shield > 0);
      engine.addGuardian(shield);

      expect(engine.state.attack!.connects, isFalse);
      expect(foe.hand.contains(shield), isFalse, reason: 'it left the hand');
    });

    test('a sentinel stops an attack whatever its power', () async {
      final (store, deck) = await buildDeck();
      final (engine, you, foe) = readyGame(store, deck);

      engine.declareAttack(from: Circle.vanguard, to: Circle.vanguard);
      engine.addPower(you, Circle.vanguard, 100000);

      final sentinel = GameCard(
        997,
        store.saveCard(
          gameId: 'vanguard',
          name: 'Perfect Guard',
          attributes: {'grade': '1', 'cardType': 'sentinel', 'shield': '0'},
        ),
      );
      foe.hand.add(sentinel);
      engine.addGuardian(sentinel);

      expect(engine.state.attack!.perfectGuarded, isTrue);
      expect(engine.state.attack!.connects, isFalse);
    });

    test('attacking rests the attacker and its booster', () async {
      final (store, deck) = await buildDeck();
      final (engine, you, foe) = readyGame(store, deck);

      final booster = you.hand.firstWhere((c) => c.grade <= 2 && c.isUnit);
      engine.call(you, booster, Circle.backCenter);
      engine.declareAttack(
        from: Circle.vanguard,
        to: Circle.vanguard,
        boost: true,
      );

      expect(you.vanguard!.rested, isTrue);
      expect(you.field[Circle.backCenter]!.rested, isTrue);
      // And a rested unit is no longer offered as an attacker.
      expect(engine.attackers(you), isNot(contains(Circle.vanguard)));
    });

    test('a boost adds the booster power to the attack', () async {
      final (store, deck) = await buildDeck();
      final (engine, you, foe) = readyGame(store, deck);

      final booster = you.hand.firstWhere((c) => c.grade <= 2 && c.isUnit);
      engine.call(you, booster, Circle.backCenter);
      final attack = engine.declareAttack(
        from: Circle.vanguard,
        to: Circle.vanguard,
        boost: true,
      );

      expect(attack.attackPower, you.vanguard!.power + booster.power);
    });

    test(
      'a hit on the vanguard is damage; a hit on a rear-guard retires',
      () async {
        final (store, deck) = await buildDeck();
        final (engine, you, foe) = readyGame(store, deck);

        // A rear-guard on the CPU's front row, weak enough to be run over.
        final weak = foe.hand.firstWhere((c) => c.grade <= 2 && c.isUnit);
        engine.call(foe, weak, Circle.frontLeft);

        engine.declareAttack(from: Circle.vanguard, to: Circle.frontLeft);
        engine.resolveAttack();
        expect(foe.field[Circle.frontLeft], isNull);
        expect(foe.damageCount, 0, reason: 'rear-guards do not deal damage');
        expect(foe.drop, contains(weak));
      },
    );
  });

  group('drive and damage checks', () {
    test('a grade 3 vanguard twin drives', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      while (engine.rideDeckOption(you) != null) {
        engine.ride(you, engine.rideDeckOption(you)!, fromRideDeck: true);
      }
      expect(you.vanguard!.card.grade, 3);
      expect(engine.driveCount(you.vanguard!), 2);

      engine.state.phase = PlaytestPhase.battle;
      engine.declareAttack(from: Circle.vanguard, to: Circle.vanguard);
      final before = you.hand.length;
      final flipped = engine.driveCheck();

      expect(flipped.length, 2);
      expect(you.hand.length, before + 2, reason: 'drive checks join the hand');
    });

    test('a rear-guard attack drive checks nothing', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      engine.ride(you, engine.rideDeckOption(you)!, fromRideDeck: true);
      final unit = you.hand.firstWhere((c) => c.grade <= 1 && c.isUnit);
      engine.call(you, unit, Circle.frontLeft);

      engine.state.phase = PlaytestPhase.battle;
      engine.declareAttack(from: Circle.frontLeft, to: Circle.vanguard);
      expect(engine.driveCheck(), isEmpty);
    });

    test('six damage ends the game', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final foe = engine.state.opponent;

      for (var i = 0; i < 6; i += 1) {
        engine.dealDamage(foe);
      }
      expect(foe.damageCount, 6);
      expect(foe.isDefeated, isTrue);
      expect(engine.state.isOver, isTrue);
      expect(engine.state.winner, engine.state.you);
    });
  });

  group('triggers', () {
    /// A deck whose every main deck card is the trigger under test, so a check
    /// is guaranteed to turn one up.
    Future<(DeckStore, Deck)> deckOfTriggers(String icon) async {
      SharedPreferences.setMockInitialValues({});
      final store = DeckStore();
      await store.load();
      final deck = store.createDeck(name: 'Triggers', formatId: formatStandard);
      for (var grade = 0; grade <= 3; grade += 1) {
        final card = store.saveCard(
          gameId: 'vanguard',
          name: 'Ride $grade',
          attributes: {
            'grade': '$grade',
            'cardType': 'normal',
            'power': '10000',
          },
        );
        store.addToDeck(deck.id, card.id, zoneRide);
      }
      final trigger = store.saveCard(
        gameId: 'vanguard',
        name: '$icon trigger',
        attributes: {
          'grade': '0',
          'cardType': 'trigger',
          'trigger': icon,
          'power': '5000',
          'shield': '15000',
        },
      );
      store.addToDeck(deck.id, trigger.id, zoneMain, quantity: 50);
      return (store, store.decks.first);
    }

    test('a critical trigger adds power and a critical', () async {
      final (store, deck) = await deckOfTriggers('critical');
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      engine.state.phase = PlaytestPhase.battle;

      final before = you.vanguard!.power;
      engine.declareAttack(from: Circle.vanguard, to: Circle.vanguard);
      engine.driveCheck();

      expect(you.vanguard!.power, before + 5000);
      expect(you.vanguard!.critical, 2, reason: 'one more than the base');
    });

    test('a draw trigger draws a card', () async {
      final (store, deck) = await deckOfTriggers('draw');
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      engine.state.phase = PlaytestPhase.battle;

      final before = you.hand.length;
      engine.declareAttack(from: Circle.vanguard, to: Circle.vanguard);
      engine.driveCheck();

      // The checked card and the card it drew both arrive in hand.
      expect(you.hand.length, before + 2);
    });

    test('a front trigger lifts the whole front row', () async {
      final (store, deck) = await deckOfTriggers('front');
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      final wing = you.hand.first;
      engine.call(you, wing, Circle.frontLeft);
      engine.state.phase = PlaytestPhase.battle;

      engine.declareAttack(from: Circle.vanguard, to: Circle.vanguard);
      engine.driveCheck();

      expect(you.vanguard!.powerBonus, 10000);
      expect(you.field[Circle.frontLeft]!.powerBonus, 10000);
    });

    test('a heal trigger heals when you are not ahead', () async {
      final (store, deck) = await deckOfTriggers('heal');
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;

      // Damage placed straight into the zone rather than checked for: in a
      // deck of nothing but heal triggers, every damage check would heal
      // itself back and there would be nothing left to test.
      you.damage.addAll(you.deck.sublist(0, 2));
      you.deck.removeRange(0, 2);
      expect(you.damageCount, 2);
      expect(engine.state.opponent.damageCount, 0, reason: 'you are behind');

      engine.state.phase = PlaytestPhase.battle;
      engine.declareAttack(from: Circle.vanguard, to: Circle.vanguard);
      engine.driveCheck();
      expect(you.damageCount, 1, reason: 'one healed away');
    });

    test('a heal trigger does nothing while you are ahead', () async {
      final (store, deck) = await deckOfTriggers('heal');
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      final foe = engine.state.opponent;

      // The opponent is further behind, so the heal has no claim.
      foe.damage.addAll(foe.deck.sublist(0, 3));
      foe.deck.removeRange(0, 3);
      you.damage.add(you.deck.removeLast());
      expect(you.damageCount, 1);

      engine.state.phase = PlaytestPhase.battle;
      engine.declareAttack(from: Circle.vanguard, to: Circle.vanguard);
      engine.driveCheck();
      expect(you.damageCount, 1, reason: 'no heal while ahead');
      expect(you.vanguard!.powerBonus, 5000, reason: 'the power still applies');
    });

    test('a trigger in damage helps the player taking the hit', () async {
      final (store, deck) = await deckOfTriggers('critical');
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final foe = engine.state.opponent;

      engine.dealDamage(foe);
      // The critical trigger came off their own deck, so their vanguard is
      // the one that grew.
      expect(foe.vanguard!.powerBonus, 5000);
      expect(engine.state.you.vanguard!.powerBonus, 0);
    });

    test('turn effects wear off at end of turn', () async {
      final (store, deck) = await deckOfTriggers('critical');
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      engine.state.phase = PlaytestPhase.battle;
      engine.declareAttack(from: Circle.vanguard, to: Circle.vanguard);
      engine.driveCheck();
      expect(you.vanguard!.powerBonus, greaterThan(0));

      engine.endTurn();
      expect(you.vanguard!.powerBonus, 0);
      expect(you.vanguard!.criticalBonus, 0);
    });
  });

  group('the turn one draw', () {
    test('the player going first draws on turn one', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      final you = engine.state.you;
      expect(you.hand.length, 5, reason: 'the opening hand');

      engine.beginPlay();
      expect(engine.state.turn, 1);
      expect(engine.state.yourTurn, isTrue);
      expect(you.hand.length, 6, reason: 'no skipped first draw');
    });

    test('the player going second draws on their first turn too', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final foe = engine.state.opponent;
      expect(foe.hand.length, 5);

      engine.endTurn();
      expect(engine.state.yourTurn, isFalse);
      expect(foe.hand.length, 6);
    });
  });

  group('the G zone', () {
    final deckWithGZone = buildStrideDeck;

    test('G units go to the G zone, not the main deck', () async {
      final (store, deck) = await deckWithGZone();
      final engine = engineFor(store, deck);
      final you = engine.state.you;

      expect(you.gZone.length, 8);
      expect(you.deck.any((c) => c.cardType == 'g-unit'), isFalse);
      expect(you.hand.any((c) => c.cardType == 'g-unit'), isFalse);
      // And the main deck is still the fifty it should be.
      expect(you.deck.length + you.hand.length, 50);
    });

    test('a G unit can never be called to a circle', () async {
      final (store, deck) = await deckWithGZone();
      final engine = engineFor(store, deck);
      final you = engine.state.you;
      final gUnit = you.gZone.first;

      expect(engine.canCall(you, gUnit, Circle.frontLeft), isFalse);
    });

    test('striding needs a grade 3 vanguard', () async {
      final (store, deck) = await deckWithGZone();
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;

      expect(engine.canStride(you), isFalse, reason: 'grade 0 vanguard');
      while (engine.rideDeckOption(you) != null) {
        engine.ride(you, engine.rideDeckOption(you)!, fromRideDeck: true);
      }
      expect(you.vanguard!.card.grade, 3);
      expect(engine.canStride(you), isTrue);
    });

    test('a stride costs grade 3 from hand and sits on the vanguard', () async {
      final (store, deck) = await deckWithGZone();
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      while (engine.rideDeckOption(you) != null) {
        engine.ride(you, engine.rideDeckOption(you)!, fromRideDeck: true);
      }
      final heart = you.vanguard!.card;
      final gUnit = you.gZone.first;

      // Two grade 2s pay for it; one alone would not.
      expect(engine.isStrideCost([you.hand.first]), isFalse);
      final cost = <GameCard>[];
      var total = 0;
      for (final card in you.hand) {
        if (total >= 3) break;
        cost.add(card);
        total += card.grade;
      }
      engine.stride(you, gUnit, cost);

      expect(you.vanguard!.card, gUnit);
      expect(you.isStriding, isTrue);
      expect(you.heart!.card, heart, reason: 'the ridden unit is underneath');
      expect(you.gZone.contains(gUnit), isFalse);
      for (final paid in cost) {
        expect(you.drop, contains(paid));
      }
    });

    test('a striding vanguard triple drives', () async {
      final (store, deck) = await deckWithGZone();
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      while (engine.rideDeckOption(you) != null) {
        engine.ride(you, engine.rideDeckOption(you)!, fromRideDeck: true);
      }
      expect(engine.driveCount(you.vanguard!), 2, reason: 'twin at grade 3');

      final cost = <GameCard>[];
      var total = 0;
      for (final card in you.hand) {
        if (total >= 3) break;
        cost.add(card);
        total += card.grade;
      }
      engine.stride(you, you.gZone.first, cost);
      expect(engine.driveCount(you.vanguard!), 3);
    });

    test('a stride lasts one turn and the heart comes back', () async {
      final (store, deck) = await deckWithGZone();
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      while (engine.rideDeckOption(you) != null) {
        engine.ride(you, engine.rideDeckOption(you)!, fromRideDeck: true);
      }
      final heart = you.vanguard!.card;
      final gUnit = you.gZone.first;
      final cost = <GameCard>[];
      var total = 0;
      for (final card in you.hand) {
        if (total >= 3) break;
        cost.add(card);
        total += card.grade;
      }
      engine.stride(you, gUnit, cost);

      engine.endTurn();
      expect(you.isStriding, isFalse);
      expect(you.vanguard!.card, heart);
      expect(you.gZone, contains(gUnit), reason: 'it goes back to the G zone');
    });
  });

  group('the zones abilities are paid out of', () {
    test('a counter-blast turns damage face down', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      you.damage.addAll(you.deck.sublist(0, 3));
      you.deck.removeRange(0, 3);

      expect(you.openDamage, 3);
      engine.counterBlast(you, 2);
      expect(you.openDamage, 1);
      // Spent damage still counts towards the six that ends the game.
      expect(you.damageCount, 3);

      engine.counterCharge(you, 1);
      expect(you.openDamage, 2);
    });

    test('a counter-blast cannot spend what is already spent', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      you.damage.addAll(you.deck.sublist(0, 2));
      you.deck.removeRange(0, 2);

      engine.counterBlast(you, 5);
      expect(you.openDamage, 0);
      expect(you.damageCount, 2, reason: 'no damage was invented');
    });

    test('a soul-blast moves a card from soul to drop', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      engine.ride(you, engine.rideDeckOption(you)!, fromRideDeck: true);
      final inSoul = you.soul.single;

      engine.soulBlast(you, inSoul);
      expect(you.soul, isEmpty);
      expect(you.drop, contains(inSoul));
    });

    test('a soul-charge takes off the top of the deck', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      final before = you.deck.length;

      engine.soulCharge(you, 2);
      expect(you.soul.length, 2);
      expect(you.deck.length, before - 2);
    });

    test('searching the deck takes the card and shuffles', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      final wanted = you.deck.firstWhere((c) => c.name == 'Beater');
      final before = you.deck.length;

      engine.searchDeck(you, wanted);
      expect(you.hand, contains(wanted));
      expect(you.deck.contains(wanted), isFalse);
      expect(you.deck.length, before - 1);
    });

    test('a card can be taken back out of the drop zone', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      final pitched = you.hand.first;
      engine.discard(you, pitched);
      expect(you.drop, contains(pitched));

      engine.returnFromDrop(you, pitched);
      expect(you.hand, contains(pitched));
      expect(you.drop.contains(pitched), isFalse);
    });

    test('a card can be put under the deck', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      final card = you.hand.first;

      engine.bottomDeck(you, card);
      expect(you.hand.contains(card), isFalse);
      // Under the deck means it is the last thing that would be drawn.
      expect(you.deck.first, card);
    });
  });

  group('the CPU', () {
    test('rides up its ride deck on its own turn', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      final ai = PlaytestAi(engine);
      engine.beginPlay();
      engine.endTurn();

      expect(engine.state.yourTurn, isFalse);
      final cpu = engine.state.opponent;
      expect(cpu.vanguard!.card.grade, 0);
      ai.takeTurn();
      expect(cpu.vanguard!.card.grade, 1, reason: 'it climbed a grade');
    });

    test('it calls units but keeps cards to guard with', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      final ai = PlaytestAi(engine);
      engine.beginPlay();
      engine.endTurn();
      ai.takeTurn();

      final cpu = engine.state.opponent;
      expect(
        cpu.hand.length,
        greaterThan(1),
        reason: 'it did not dump its hand',
      );
    });

    test('it attacks the vanguard once it has a board', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      final ai = PlaytestAi(engine);
      engine.beginPlay();
      engine.endTurn();
      ai.takeTurn();

      final attack = ai.nextAttack();
      expect(attack, isNotNull);
      expect(attack!.to, Circle.vanguard);
    });

    test('it guards to stay alive when the hit would be lethal', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      final ai = PlaytestAi(engine);
      engine.beginPlay();
      final cpu = engine.state.opponent;

      // Five damage in, so the next hit ends it.
      for (var i = 0; i < 5; i += 1) {
        engine.dealDamage(cpu);
      }
      final sentinel = GameCard(
        996,
        store.saveCard(
          gameId: 'vanguard',
          name: 'Perfect Guard',
          attributes: {'grade': '1', 'cardType': 'sentinel', 'shield': '0'},
        ),
      );
      cpu.hand.add(sentinel);

      engine.state.phase = PlaytestPhase.battle;
      final pending = engine.declareAttack(
        from: Circle.vanguard,
        to: Circle.vanguard,
      );
      engine.addPower(engine.state.you, Circle.vanguard, 50000);
      ai.guard(pending);

      expect(pending.perfectGuarded, isTrue, reason: 'it saved itself');
    });
  });

  group('a whole game', () {
    test('two CPUs can play one out to a winner', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck, seed: 3);
      final ai = PlaytestAi(engine);
      engine.beginPlay();

      // Drive both sides with the same policy until somebody wins. The point
      // is that the rules never deadlock and the game does end.
      var guard = 0;
      while (!engine.state.isOver && guard++ < 400) {
        final side = engine.state.active;
        if (engine.canRide(side)) {
          final option = engine.rideDeckOption(side);
          if (option != null) {
            engine.ride(side, option, fromRideDeck: true);
          }
        }
        for (final circle in [Circle.frontLeft, Circle.backCenter]) {
          final callable = side.hand
              .where((c) => engine.canCall(side, c, circle))
              .toList();
          if (callable.isNotEmpty && side.field[circle] == null) {
            engine.call(side, callable.first, circle);
          }
        }
        engine.state.phase = PlaytestPhase.battle;
        for (final from in engine.attackers(side).toList()) {
          if (engine.state.isOver) break;
          if (side.field[from] == null) continue;
          engine.declareAttack(from: from, to: Circle.vanguard);
          engine.driveCheck();
          engine.resolveAttack();
        }
        if (engine.state.isOver) break;
        engine.endTurn();
      }

      expect(engine.state.isOver, isTrue, reason: 'the game reached an end');
      expect(engine.state.winner, isNotNull);
      expect(ai.state.log, isNotEmpty);
    });
  });
}
