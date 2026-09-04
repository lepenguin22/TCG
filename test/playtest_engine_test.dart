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
  final (store, deck) = await buildEnergyDeck();
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

/// The same deck with the real Energy Generator crest in its ride deck, text
/// and all, so the energy rules are read off the card rather than assumed.
Future<(DeckStore, Deck)> buildEnergyDeck() async {
  final (store, deck) = await buildDeck();
  final crest = store.saveCard(
    gameId: 'vanguard',
    name: 'Energy Generator',
    attributes: {
      'cardType': 'ride-deck-crest',
      'effect':
          '(You may only have one ride deck crest in a ride deck)\n'
          '[AUTO]Ride Deck:When you ride, put this card into the crest zone, '
          'and if you went second, [Energy-Charge 3].\n'
          '[CONT]:You may have up to ten energy.\n'
          '[AUTO]:At the beginning of your ride phase, [Energy-Charge 3].\n'
          '[ACT][1/Turn]:[COST][[Energy-Blast 7]], and draw a card.',
    },
  );
  store.addToDeck(deck.id, crest.id, zoneRide);
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

  group('moving between the rows of a column', () {
    /// A game in the main phase with a grade 2 vanguard to call under.
    (PlaytestEngine, PlaytestSide) inMain(DeckStore store, Deck deck) {
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      while (engine.rideDeckOption(you) != null &&
          (you.vanguard?.card.grade ?? 0) < 2) {
        engine.ride(you, engine.rideDeckOption(you)!, fromRideDeck: true);
      }
      engine.state.phase = PlaytestPhase.main;
      return (engine, you);
    }

    test('the left and right columns pair front to back', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);

      expect(engine.moveTargetOf(Circle.frontLeft), Circle.backLeft);
      expect(engine.moveTargetOf(Circle.backLeft), Circle.frontLeft);
      expect(engine.moveTargetOf(Circle.frontRight), Circle.backRight);
      expect(engine.moveTargetOf(Circle.backRight), Circle.frontRight);
    });

    test('the middle column cannot move', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);

      // Nothing moves onto the vanguard circle, so the unit behind it is
      // stuck where it stands, and the vanguard itself never moves.
      expect(engine.moveTargetOf(Circle.backCenter), isNull);
      expect(engine.moveTargetOf(Circle.vanguard), isNull);
    });

    test('a unit moves into the empty circle of its column', () async {
      final (store, deck) = await buildDeck();
      final (engine, you) = inMain(store, deck);

      final unit = you.hand.firstWhere(
        (c) => engine.canCall(you, c, Circle.backLeft),
      );
      engine.call(you, unit, Circle.backLeft);

      expect(engine.canMove(you, Circle.backLeft), isTrue);
      engine.moveUnit(you, Circle.backLeft);

      expect(you.field[Circle.frontLeft]!.card, unit);
      expect(you.field[Circle.backLeft], isNull);
    });

    test('two units in a column swap places', () async {
      final (store, deck) = await buildDeck();
      final (engine, you) = inMain(store, deck);

      final front = you.hand.firstWhere(
        (c) => engine.canCall(you, c, Circle.frontRight),
      );
      engine.call(you, front, Circle.frontRight);
      final back = you.hand.firstWhere(
        (c) => engine.canCall(you, c, Circle.backRight),
      );
      engine.call(you, back, Circle.backRight);

      engine.moveUnit(you, Circle.frontRight);
      expect(you.field[Circle.frontRight]!.card, back);
      expect(you.field[Circle.backRight]!.card, front);
    });

    test('a moved unit keeps everything about itself', () async {
      final (store, deck) = await buildDeck();
      final (engine, you) = inMain(store, deck);

      final unit = you.hand.firstWhere(
        (c) => engine.canCall(you, c, Circle.backLeft),
      );
      engine.call(you, unit, Circle.backLeft);
      engine.addPower(you, Circle.backLeft, 5000);
      you.field[Circle.backLeft]!.rested = true;

      engine.moveUnit(you, Circle.backLeft);
      final moved = you.field[Circle.frontLeft]!;
      expect(moved.card, unit);
      expect(moved.powerBonus, 5000, reason: 'the power travels with it');
      expect(moved.rested, isTrue, reason: 'and moving does not stand it');
    });

    test('moving is a main phase action only', () async {
      final (store, deck) = await buildDeck();
      final (engine, you) = inMain(store, deck);
      final unit = you.hand.firstWhere(
        (c) => engine.canCall(you, c, Circle.backLeft),
      );
      engine.call(you, unit, Circle.backLeft);

      engine.state.phase = PlaytestPhase.battle;
      expect(engine.canMove(you, Circle.backLeft), isFalse);
      engine.moveUnit(you, Circle.backLeft);
      expect(
        you.field[Circle.backLeft],
        isNotNull,
        reason: 'the board cannot be rearranged mid-battle',
      );
    });

    test('an empty circle has nothing to move', () async {
      final (store, deck) = await buildDeck();
      final (engine, you) = inMain(store, deck);
      expect(engine.canMove(you, Circle.backRight), isFalse);
    });

    test('a moved unit can then attack from the front', () async {
      final (store, deck) = await buildDeck();
      final (engine, you) = inMain(store, deck);

      final unit = you.hand.firstWhere(
        (c) => engine.canCall(you, c, Circle.backLeft),
      );
      engine.call(you, unit, Circle.backLeft);
      // Stuck in the back row, it is not an attacker.
      engine.state.phase = PlaytestPhase.battle;
      expect(engine.attackers(you), isNot(contains(Circle.backLeft)));

      engine.state.phase = PlaytestPhase.main;
      engine.moveUnit(you, Circle.backLeft);
      engine.state.phase = PlaytestPhase.battle;
      expect(engine.attackers(you), contains(Circle.frontLeft));
    });
  });

  group('calling from somewhere other than hand', () {
    (PlaytestEngine, PlaytestSide) ready(DeckStore store, Deck deck) {
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      while (engine.rideDeckOption(you) != null &&
          (you.vanguard?.card.grade ?? 0) < 2) {
        engine.ride(you, engine.rideDeckOption(you)!, fromRideDeck: true);
      }
      engine.state.phase = PlaytestPhase.main;
      return (engine, you);
    }

    test('a unit can be called straight out of the deck', () async {
      final (store, deck) = await buildDeck();
      final (engine, you) = ready(store, deck);

      final wanted = you.deck.firstWhere((c) => c.name == 'Beater');
      final before = you.deck.length;
      engine.call(you, wanted, Circle.frontLeft);

      expect(you.field[Circle.frontLeft]!.card, wanted);
      expect(you.deck.contains(wanted), isFalse);
      expect(you.deck.length, before - 1);
      expect(you.hand.contains(wanted), isFalse, reason: 'it never went there');
    });

    test('calling out of the deck shuffles it', () async {
      final (store, deck) = await buildDeck();
      final (engine, you) = ready(store, deck);

      // Looking through the deck to find a card means shuffling afterwards.
      final orderBefore = [...you.deck];
      final wanted = you.deck.firstWhere((c) => c.name == 'Beater');
      engine.call(you, wanted, Circle.frontLeft);

      final remaining = orderBefore.where((c) => c != wanted).toList();
      expect(you.deck.toSet(), remaining.toSet(), reason: 'same cards');
      expect(
        you.deck.map((c) => c.instanceId).toList(),
        isNot(remaining.map((c) => c.instanceId).toList()),
        reason: 'but not in the same order',
      );
    });

    test('a unit can be called back out of the drop zone', () async {
      final (store, deck) = await buildDeck();
      final (engine, you) = ready(store, deck);

      final pitched = you.hand.firstWhere((c) => c.grade <= 2 && c.isUnit);
      engine.discard(you, pitched);
      expect(you.drop, contains(pitched));

      engine.call(you, pitched, Circle.backLeft);
      expect(you.field[Circle.backLeft]!.card, pitched);
      expect(you.drop.contains(pitched), isFalse);
    });

    test('a unit can be called out of the soul', () async {
      final (store, deck) = await buildDeck();
      final (engine, you) = ready(store, deck);

      // Riding puts the unit ridden over into the soul.
      final inSoul = you.soul.first;
      engine.call(you, inSoul, Circle.backRight);

      expect(you.field[Circle.backRight]!.card, inSoul);
      expect(you.soul.contains(inSoul), isFalse);
    });

    test('the grade limit still applies wherever it came from', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      // Vanguard is still grade 0, so a grade 2 cannot be called from
      // anywhere at all.
      final beater = you.deck.firstWhere((c) => c.name == 'Beater');
      expect(engine.canCall(you, beater, Circle.frontLeft), isFalse);
    });

    test('a card in no zone at all calls nothing', () async {
      final (store, deck) = await buildDeck();
      final (engine, you) = ready(store, deck);

      final stranger = GameCard(
        920,
        store.saveCard(
          gameId: 'vanguard',
          name: 'Not in the game',
          attributes: {'grade': '1', 'cardType': 'normal', 'power': '8000'},
        ),
      );
      engine.call(you, stranger, Circle.frontRight);
      expect(you.field[Circle.frontRight], isNull);
    });

    test('calling over a unit still drops the old one', () async {
      final (store, deck) = await buildDeck();
      final (engine, you) = ready(store, deck);

      final first = you.hand.firstWhere((c) => c.grade <= 2 && c.isUnit);
      engine.call(you, first, Circle.frontLeft);
      final fromDeck = you.deck.firstWhere((c) => c.name == 'Beater');
      engine.call(you, fromDeck, Circle.frontLeft);

      expect(you.field[Circle.frontLeft]!.card, fromDeck);
      expect(you.drop, contains(first));
    });

    test('a unit called mid-battle can attack from the front row', () async {
      final (store, deck) = await buildDeck();
      final (engine, you) = ready(store, deck);
      engine.state.phase = PlaytestPhase.battle;

      // The abilities this exists for fire during the battle phase.
      final fromDeck = you.deck.firstWhere((c) => c.name == 'Beater');
      engine.call(you, fromDeck, Circle.frontLeft);

      expect(engine.attackers(you), contains(Circle.frontLeft));
      expect(you.field[Circle.frontLeft]!.rested, isFalse);
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

  group('drive given by an ability', () {
    (PlaytestEngine, PlaytestSide) atGrade(
      DeckStore store,
      Deck deck,
      int grade,
    ) {
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      while (engine.rideDeckOption(you) != null &&
          (you.vanguard?.card.grade ?? 0) < grade) {
        engine.ride(you, engine.rideDeckOption(you)!, fromRideDeck: true);
      }
      engine.state.phase = PlaytestPhase.battle;
      return (engine, you);
    }

    test('drive comes from the grade to begin with', () async {
      final (store, deck) = await buildDeck();
      final (engine, you) = atGrade(store, deck, 2);
      expect(engine.driveCount(you.vanguard!), 1);

      final (engine3, you3) = atGrade(store, deck, 3);
      expect(engine3.driveCount(you3.vanguard!), 2, reason: 'twin drive');
    });

    test('an ability can add a check', () async {
      final (store, deck) = await buildDeck();
      final (engine, you) = atGrade(store, deck, 3);

      engine.addDrive(you, Circle.vanguard, 1);
      expect(engine.driveCount(you.vanguard!), 3);
    });

    test('the extra check really is flipped', () async {
      final (store, deck) = await buildDeck();
      final (engine, you) = atGrade(store, deck, 3);
      engine.addDrive(you, Circle.vanguard, 1);

      engine.declareAttack(from: Circle.vanguard, to: Circle.vanguard);
      final before = you.hand.length;
      final flipped = engine.driveCheck();

      expect(flipped.length, 3, reason: 'twin drive plus the one given');
      expect(you.hand.length, greaterThanOrEqualTo(before + 3));
    });

    test('it can be taken away, and stops at none', () async {
      final (store, deck) = await buildDeck();
      final (engine, you) = atGrade(store, deck, 3);

      engine.addDrive(you, Circle.vanguard, -1);
      expect(engine.driveCount(you.vanguard!), 1);
      engine.addDrive(you, Circle.vanguard, -1);
      expect(engine.driveCount(you.vanguard!), 0);
      engine.addDrive(you, Circle.vanguard, -3);
      expect(engine.driveCount(you.vanguard!), 0, reason: 'no further');
    });

    test('a vanguard on no drive checks nothing', () async {
      final (store, deck) = await buildDeck();
      final (engine, you) = atGrade(store, deck, 3);
      engine.addDrive(you, Circle.vanguard, -2);

      engine.declareAttack(from: Circle.vanguard, to: Circle.vanguard);
      expect(engine.driveCheck(), isEmpty);
    });

    test('it wears off at end of turn', () async {
      final (store, deck) = await buildDeck();
      final (engine, you) = atGrade(store, deck, 3);

      engine.addDrive(you, Circle.vanguard, 1);
      expect(engine.driveCount(you.vanguard!), 3);
      engine.endTurn();
      expect(engine.driveCount(you.vanguard!), 2);
      expect(you.vanguard!.driveBonus, 0);
    });

    test('a rear-guard drive checks nothing whatever it is given', () async {
      final (store, deck) = await buildDeck();
      final (engine, you) = atGrade(store, deck, 2);

      final unit = you.hand.firstWhere(
        (c) => engine.canCall(you, c, Circle.frontLeft),
      );
      engine.call(you, unit, Circle.frontLeft);
      engine.addDrive(you, Circle.frontLeft, 2);

      engine.declareAttack(from: Circle.frontLeft, to: Circle.vanguard);
      expect(
        engine.driveCheck(),
        isEmpty,
        reason: 'only the vanguard drive checks at all',
      );
    });

    test('a striding vanguard keeps its triple drive on top', () async {
      final (store, deck) = await buildStrideDeck();
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      while (engine.rideDeckOption(you) != null) {
        engine.ride(you, engine.rideDeckOption(you)!, fromRideDeck: true);
      }
      final cost = <GameCard>[];
      var total = 0;
      for (final card in you.hand) {
        if (total >= 3) break;
        cost.add(card);
        total += card.grade;
      }
      engine.stride(you, you.gZone.first, cost);
      expect(engine.driveCount(you.vanguard!), 3);

      engine.addDrive(you, Circle.vanguard, 1);
      expect(engine.driveCount(you.vanguard!), 4);
    });
  });

  group('critical given by an ability', () {
    /// A game in battle with a grade 2 vanguard on each side.
    (PlaytestEngine, PlaytestSide, PlaytestSide) ready(
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

    test('a unit starts on one critical', () async {
      final (store, deck) = await buildDeck();
      final (engine, you, _) = ready(store, deck);
      expect(you.vanguard!.critical, 1);
      expect(you.vanguard!.criticalBonus, 0);
    });

    test('critical can be given by hand', () async {
      final (store, deck) = await buildDeck();
      final (engine, you, _) = ready(store, deck);

      engine.addCritical(you, Circle.vanguard, 1);
      expect(you.vanguard!.critical, 2);
      engine.addCritical(you, Circle.vanguard, 2);
      expect(you.vanguard!.critical, 4);
    });

    test('the extra critical is extra damage', () async {
      final (store, deck) = await buildDeck();
      final (engine, you, foe) = ready(store, deck);

      engine.addCritical(you, Circle.vanguard, 2);
      engine.addPower(you, Circle.vanguard, 50000);
      engine.declareAttack(from: Circle.vanguard, to: Circle.vanguard);
      engine.resolveAttack();

      expect(foe.damageCount, 3, reason: 'one base plus the two given');
    });

    test('it can be taken away, but not below none', () async {
      final (store, deck) = await buildDeck();
      final (engine, you, _) = ready(store, deck);

      engine.addCritical(you, Circle.vanguard, 1);
      engine.addCritical(you, Circle.vanguard, -1);
      expect(you.vanguard!.critical, 1);

      engine.addCritical(you, Circle.vanguard, -1);
      expect(you.vanguard!.critical, 0, reason: 'a card can remove the last');
      engine.addCritical(you, Circle.vanguard, -5);
      expect(you.vanguard!.critical, 0, reason: 'and no further');
    });

    test('a unit on no critical deals no damage', () async {
      final (store, deck) = await buildDeck();
      final (engine, you, foe) = ready(store, deck);

      engine.addCritical(you, Circle.vanguard, -1);
      engine.addPower(you, Circle.vanguard, 50000);
      engine.declareAttack(from: Circle.vanguard, to: Circle.vanguard);
      engine.resolveAttack();

      expect(foe.damageCount, 0);
    });

    test('it wears off at end of turn, as power does', () async {
      final (store, deck) = await buildDeck();
      final (engine, you, _) = ready(store, deck);

      engine.addCritical(you, Circle.vanguard, 2);
      expect(you.vanguard!.critical, 3);

      engine.endTurn();
      expect(you.vanguard!.critical, 1);
      expect(you.vanguard!.criticalBonus, 0);
    });

    test('a critical trigger stacks on top of it', () async {
      final (store, deck) = await buildDeck();
      final (engine, you, _) = ready(store, deck);

      engine.addCritical(you, Circle.vanguard, 1);
      engine.declareAttack(from: Circle.vanguard, to: Circle.vanguard);
      engine.driveCheck();

      // Every card in this deck's trigger slot is a critical trigger, so the
      // check adds one more on top of the one the ability gave.
      expect(you.vanguard!.critical, greaterThanOrEqualTo(2));
    });

    test('an empty circle is left alone', () async {
      final (store, deck) = await buildDeck();
      final (engine, you, _) = ready(store, deck);
      // No unit there, so nothing to give critical to and nothing to crash on.
      engine.addCritical(you, Circle.backRight, 1);
      expect(you.field[Circle.backRight], isNull);
    });
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

  group('the guardian circle and the trigger zone', () {
    (PlaytestEngine, PlaytestSide, PlaytestSide) ready(
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

    test('cards called to guard are held, not just counted', () async {
      final (store, deck) = await buildDeck();
      final (engine, you, foe) = ready(store, deck);

      final attack = engine.declareAttack(
        from: Circle.vanguard,
        to: Circle.vanguard,
      );
      expect(attack.guardians, isEmpty);

      final shield = engine.guardOptions(foe).firstWhere((c) => c.shield > 0);
      engine.addGuardian(shield);

      expect(attack.guardians.single, shield, reason: 'the card itself');
      expect(attack.shield, shield.shield);
    });

    test('the guardians go to the drop when the battle ends', () async {
      final (store, deck) = await buildDeck();
      final (engine, you, foe) = ready(store, deck);

      engine.declareAttack(from: Circle.vanguard, to: Circle.vanguard);
      final shield = engine.guardOptions(foe).firstWhere((c) => c.shield > 0);
      engine.addGuardian(shield);
      engine.resolveAttack();

      expect(foe.drop, contains(shield));
    });

    test('a drive check lands in the trigger zone', () async {
      final (store, deck) = await buildDeck();
      final (engine, you, _) = ready(store, deck);
      expect(engine.state.triggerZone, isEmpty);

      engine.declareAttack(from: Circle.vanguard, to: Circle.vanguard);
      final flipped = engine.driveCheck();

      expect(engine.state.triggerZone.length, flipped.length);
      expect(engine.state.triggerZone.first.kind, CheckKind.drive);
      expect(engine.state.triggerZone.first.sideName, you.name);
    });

    test('a damage check lands there too, named for whoever took it', () async {
      final (store, deck) = await buildDeck();
      final (engine, you, foe) = ready(store, deck);

      engine.declareAttack(from: Circle.vanguard, to: Circle.vanguard);
      engine.addPower(you, Circle.vanguard, 50000);
      engine.driveCheck();
      engine.resolveAttack();

      final damage = engine.state.triggerZone
          .where((c) => c.kind == CheckKind.damage)
          .toList();
      expect(damage, isNotEmpty, reason: 'the hit was checked for');
      expect(damage.first.sideName, foe.name, reason: 'they took it');
    });

    test('both kinds sit there together, in the order checked', () async {
      final (store, deck) = await buildDeck();
      final (engine, you, _) = ready(store, deck);

      engine.declareAttack(from: Circle.vanguard, to: Circle.vanguard);
      engine.addPower(you, Circle.vanguard, 50000);
      engine.driveCheck();
      engine.resolveAttack();

      final kinds = engine.state.triggerZone.map((c) => c.kind).toList();
      expect(kinds, contains(CheckKind.drive));
      expect(kinds, contains(CheckKind.damage));
      expect(
        kinds.indexOf(CheckKind.drive),
        lessThan(kinds.lastIndexOf(CheckKind.damage)),
        reason: 'the drive check happens first',
      );
    });

    test('the damage stays visible after the attack resolves', () async {
      final (store, deck) = await buildDeck();
      final (engine, you, _) = ready(store, deck);

      engine.declareAttack(from: Circle.vanguard, to: Circle.vanguard);
      engine.addPower(you, Circle.vanguard, 50000);
      engine.driveCheck();
      engine.resolveAttack();

      // Resolving ends the battle but must not clear what it revealed, or
      // the card would be gone before it could be read.
      expect(engine.state.attack, isNull);
      expect(engine.state.triggerZone, isNotEmpty);
    });

    test('the next attack clears the zone', () async {
      final (store, deck) = await buildDeck();
      final (engine, you, _) = ready(store, deck);

      engine.declareAttack(from: Circle.vanguard, to: Circle.vanguard);
      engine.driveCheck();
      expect(engine.state.triggerZone, isNotEmpty);

      final unit = you.hand.firstWhere(
        (c) => engine.canCall(you, c, Circle.frontLeft),
      );
      engine.call(you, unit, Circle.frontLeft);
      engine.declareAttack(from: Circle.frontLeft, to: Circle.vanguard);
      expect(engine.state.triggerZone, isEmpty, reason: 'a new battle');
    });

    test('a vanguard on no drive still counts as having checked', () async {
      final (store, deck) = await buildDeck();
      final (engine, you, _) = ready(store, deck);

      engine.addDrive(you, Circle.vanguard, -1);
      final attack = engine.declareAttack(
        from: Circle.vanguard,
        to: Circle.vanguard,
      );
      expect(attack.driveChecked, isFalse);
      expect(engine.driveCheck(), isEmpty);
      expect(
        attack.driveChecked,
        isTrue,
        reason: 'so the board does not wait on a check that cannot happen',
      );
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

  group('the energy the crest charges', () {
    test('the crest waits in the ride deck until the first ride', () async {
      final (store, deck) = await buildEnergyDeck();
      final engine = engineFor(store, deck);
      final you = engine.state.you;

      expect(you.crest, isNotNull, reason: 'the deck brought one');
      expect(you.crestInPlay, isFalse, reason: 'not in the crest zone yet');
      expect(you.energy, 0);
    });

    test('going first charges nothing on turn one', () async {
      final (store, deck) = await buildEnergyDeck();
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;

      expect(you.goesFirst, isTrue);
      expect(engine.state.turn, 1);
      // The charge happens at the beginning of the ride phase, and the crest
      // does not reach the crest zone until the ride itself.
      expect(you.energy, 0);

      engine.ride(you, engine.rideDeckOption(you)!, fromRideDeck: true);
      expect(you.crestInPlay, isTrue);
      expect(you.energy, 0, reason: 'and going first pays nothing on arrival');
    });

    test('going second is paid three when the crest lands', () async {
      final (store, deck) = await buildEnergyDeck();
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final foe = engine.state.opponent;
      expect(foe.goesFirst, isFalse);

      engine.endTurn();
      expect(engine.state.yourTurn, isFalse);
      expect(foe.energy, 0, reason: 'still nothing at the start of the phase');

      engine.ride(foe, engine.rideDeckOption(foe)!, fromRideDeck: true);
      expect(foe.energy, 3, reason: 'the going-second clause');
    });

    test('three arrives every turn after the crest is down', () async {
      final (store, deck) = await buildEnergyDeck();
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      engine.ride(you, engine.rideDeckOption(you)!, fromRideDeck: true);
      expect(you.energy, 0);

      // Round the table back to you: the crest is in play, so the beginning
      // of your ride phase charges.
      engine.endTurn();
      engine.endTurn();
      expect(engine.state.yourTurn, isTrue);
      expect(you.energy, 3);

      engine.endTurn();
      engine.endTurn();
      expect(you.energy, 6);
    });

    test('the player who went first stays a charge behind', () async {
      final (store, deck) = await buildEnergyDeck();
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      final foe = engine.state.opponent;

      // Six turns, three each, riding on the first of them.
      for (var turn = 1; turn <= 6; turn += 1) {
        final side = engine.state.active;
        if (!side.crestInPlay) {
          engine.ride(side, engine.rideDeckOption(side)!, fromRideDeck: true);
        }
        if (turn < 6) engine.endTurn();
      }

      // Both have charged twice off the crest. The three paid for going
      // second is the whole of the difference between them.
      expect(you.energy, 6);
      expect(foe.energy, 9);
    });

    test('the cap eventually closes that gap', () async {
      final (store, deck) = await buildEnergyDeck();
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      final foe = engine.state.opponent;

      // Left long enough, the player who went second reaches ten first and
      // waits there, so the head start stops being one.
      for (var turn = 1; turn <= 20; turn += 1) {
        final side = engine.state.active;
        if (!side.crestInPlay) {
          engine.ride(side, engine.rideDeckOption(side)!, fromRideDeck: true);
        }
        engine.endTurn();
      }
      expect(you.energy, 10);
      expect(foe.energy, 10);
    });

    test('energy stops at the ten the crest allows', () async {
      final (store, deck) = await buildEnergyDeck();
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      engine.ride(you, engine.rideDeckOption(you)!, fromRideDeck: true);

      for (var i = 0; i < 20; i += 1) {
        engine.endTurn();
      }
      expect(you.energy, PlaytestSide.energyCap);
      expect(you.energy, 10);
    });

    test('a deck with no crest never charges', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      expect(you.crest, isNull);

      engine.ride(you, engine.rideDeckOption(you)!, fromRideDeck: true);
      for (var i = 0; i < 6; i += 1) {
        engine.endTurn();
      }
      expect(you.energy, 0);
    });

    test('the charge is read off the crest text', () async {
      final (store, deck) = await buildEnergyDeck();
      final engine = engineFor(store, deck);
      expect(engine.crestCharge(engine.state.you), 3);

      // A crest printing a different number is followed, not overruled.
      final (otherStore, otherDeck) = await buildDeck();
      final crest = otherStore.saveCard(
        gameId: 'vanguard',
        name: 'Bigger Generator',
        attributes: {
          'cardType': 'ride-deck-crest',
          'effect':
              '[AUTO]:At the beginning of your ride phase, '
              '[Energy-Charge 5].',
        },
      );
      otherStore.addToDeck(otherDeck.id, crest.id, zoneRide);
      final other = engineFor(
        otherStore,
        otherStore.decks.firstWhere((d) => d.id == otherDeck.id),
      );
      expect(other.crestCharge(other.state.you), 5);
    });

    test(
      'spending energy by hand cannot go past the cap or below zero',
      () async {
        final (store, deck) = await buildEnergyDeck();
        final engine = engineFor(store, deck);
        final you = engine.state.you;

        engine.setEnergy(you, 7);
        expect(you.energy, 7);
        engine.setEnergy(you, 50);
        expect(you.energy, 10);
        engine.setEnergy(you, -4);
        expect(you.energy, 0);
      },
    );
  });

  group('who goes first', () {
    test('you take turn one by default', () async {
      final (store, deck) = await buildEnergyDeck();
      final engine = engineFor(store, deck);
      engine.beginPlay();

      expect(engine.state.you.goesFirst, isTrue);
      expect(engine.state.opponent.goesFirst, isFalse);
      expect(engine.state.yourTurn, isTrue);
    });

    test('the CPU can be given the first turn instead', () async {
      final (store, deck) = await buildEnergyDeck();
      final engine = PlaytestEngine.start(
        store: store,
        yourDeck: deck,
        opponentDeck: deck,
        turnOrder: TurnOrder.cpuFirst,
        random: Random(7),
      );
      engine.beginPlay();

      expect(engine.state.opponent.goesFirst, isTrue);
      expect(engine.state.you.goesFirst, isFalse);
      expect(engine.state.yourTurn, isFalse, reason: 'turn one is the CPU\'s');
      expect(engine.state.turn, 1);
    });

    test('the energy follows whoever actually went second', () async {
      final (store, deck) = await buildEnergyDeck();
      final engine = PlaytestEngine.start(
        store: store,
        yourDeck: deck,
        opponentDeck: deck,
        turnOrder: TurnOrder.cpuFirst,
        random: Random(7),
      );
      engine.beginPlay();
      final you = engine.state.you;
      final cpu = engine.state.opponent;

      // The CPU has turn one now, so it is the one that charges nothing.
      engine.ride(cpu, engine.rideDeckOption(cpu)!, fromRideDeck: true);
      expect(cpu.energy, 0);

      engine.endTurn();
      engine.ride(you, engine.rideDeckOption(you)!, fromRideDeck: true);
      expect(you.energy, 3, reason: 'you went second this time');
    });

    test('random settles on one side or the other', () async {
      var sawYouFirst = false;
      var sawCpuFirst = false;
      for (var seed = 0; seed < 20; seed += 1) {
        final (store, deck) = await buildDeck();
        final engine = PlaytestEngine.start(
          store: store,
          yourDeck: deck,
          opponentDeck: deck,
          turnOrder: TurnOrder.random,
          random: Random(seed),
        );
        // Exactly one of them goes first, whichever way it fell.
        expect(engine.state.you.goesFirst, !engine.state.opponent.goesFirst);
        if (engine.state.you.goesFirst) {
          sawYouFirst = true;
        } else {
          sawCpuFirst = true;
        }
      }
      expect(sawYouFirst, isTrue);
      expect(sawCpuFirst, isTrue);
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

    test('a card in the drop zone goes under the deck too', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      final card = you.hand.first;
      engine.discard(you, card);
      expect(you.drop, contains(card));

      engine.bottomDeck(you, card);
      expect(you.drop.contains(card), isFalse);
      expect(you.deck.first, card);
      expect(
        engine.state.log.last.text,
        contains('from the drop zone'),
        reason: 'where it came from is worth reading',
      );
    });

    test('a card in the soul goes under the deck too', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      engine.soulCharge(you, 1);
      final card = you.soul.first;

      engine.bottomDeck(you, card);
      expect(you.soul.contains(card), isFalse);
      expect(you.deck.first, card);
    });

    test('the deck is never raided to put a card under itself', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      final card = you.deck.last;
      final size = you.deck.length;

      engine.bottomDeck(you, card);
      expect(you.deck.length, size, reason: 'nothing moved');
      expect(you.deck.last, card, reason: 'still on top');
    });

    test('a rear-guard can be put under the deck', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      engine.ride(you, engine.rideDeckOption(you)!, fromRideDeck: true);
      final unit = you.hand.firstWhere(
        (c) => engine.canCall(you, c, Circle.backLeft),
      );
      engine.call(you, unit, Circle.backLeft);

      engine.bottomDeckUnit(you, Circle.backLeft);
      expect(you.field[Circle.backLeft], isNull);
      expect(you.deck.first, unit);
      expect(you.drop.contains(unit), isFalse, reason: 'not a retire');
    });

    test('an empty circle puts nothing under the deck', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      final size = you.deck.length;

      engine.bottomDeckUnit(you, Circle.backLeft);
      expect(you.deck.length, size);
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

  group('the CPU repositions', () {
    test('it moves a stranded booster up to attack', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      final ai = PlaytestAi(engine);
      engine.beginPlay();
      final cpu = engine.state.opponent;

      // A unit in the back row with nothing in front of it is boosting
      // nobody, so it may as well be an attacker.
      final unit = GameCard(
        910,
        store.saveCard(
          gameId: 'vanguard',
          name: 'Stranded',
          attributes: {'grade': '1', 'cardType': 'normal', 'power': '9000'},
        ),
      );
      cpu.field[Circle.backLeft] = FieldUnit(unit);
      expect(cpu.field[Circle.frontLeft], isNull);

      engine.endTurn();
      // With nothing to call, moving is the only way the front row fills --
      // given cards it would rather call a bigger unit in front and leave
      // this one boosting it.
      cpu.hand.clear();
      ai.takeTurn();

      expect(cpu.field[Circle.frontLeft], isNotNull);
      expect(cpu.field[Circle.frontLeft]!.card, unit);
    });

    test('it leaves a booster alone when it has something to boost', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      final ai = PlaytestAi(engine);
      engine.beginPlay();
      final cpu = engine.state.opponent;

      final booster = GameCard(
        911,
        store.saveCard(
          gameId: 'vanguard',
          name: 'Booster',
          attributes: {'grade': '1', 'cardType': 'normal', 'power': '8000'},
        ),
      );
      final attacker = GameCard(
        912,
        store.saveCard(
          gameId: 'vanguard',
          name: 'Attacker',
          attributes: {'grade': '2', 'cardType': 'normal', 'power': '13000'},
        ),
      );
      cpu.field[Circle.backLeft] = FieldUnit(booster);
      cpu.field[Circle.frontLeft] = FieldUnit(attacker);

      engine.endTurn();
      ai.takeTurn();

      expect(cpu.field[Circle.backLeft]!.card, booster, reason: 'left be');
      expect(cpu.field[Circle.frontLeft]!.card, attacker);
    });
  });

  group('the CPU thinks about its attacks', () {
    test('it does not make an attack that cannot connect', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      final ai = PlaytestAi(engine);
      engine.beginPlay();
      final cpu = engine.state.opponent;
      final you = engine.state.you;

      // A tiny rear-guard against a vanguard far above it. Swinging achieves
      // nothing: the defender simply declines to guard.
      final weak = GameCard(
        900,
        store.saveCard(
          gameId: 'vanguard',
          name: 'Tiny',
          attributes: {'grade': '1', 'cardType': 'normal', 'power': '5000'},
        ),
      );
      cpu.field[Circle.frontLeft] = FieldUnit(weak);
      cpu.field.remove(Circle.vanguard);
      engine.addPower(you, Circle.vanguard, 20000);
      engine.state.phase = PlaytestPhase.battle;

      expect(ai.nextAttack(), isNull, reason: 'no attack was worth making');
    });

    test('it does attack when the swing can actually land', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      final ai = PlaytestAi(engine);
      engine.beginPlay();
      final cpu = engine.state.opponent;

      final big = GameCard(
        901,
        store.saveCard(
          gameId: 'vanguard',
          name: 'Big',
          attributes: {'grade': '2', 'cardType': 'normal', 'power': '25000'},
        ),
      );
      cpu.field[Circle.frontLeft] = FieldUnit(big);
      engine.state.phase = PlaytestPhase.battle;

      final attack = ai.nextAttack();
      expect(attack, isNotNull);
      expect(attack!.to, Circle.vanguard);
    });

    test('it kills a rear-guard worth killing', () async {
      final (store, deck) = await buildDeck();
      final (engine, ai) = (() {
        final e = engineFor(store, deck);
        return (e, PlaytestAi(e));
      })();
      engine.beginPlay();
      final cpu = engine.state.opponent;
      final you = engine.state.you;

      final attacker = GameCard(
        902,
        store.saveCard(
          gameId: 'vanguard',
          name: 'Hunter',
          attributes: {'grade': '2', 'cardType': 'normal', 'power': '20000'},
        ),
      );
      cpu.field[Circle.frontLeft] = FieldUnit(attacker);

      // A real threat on their front row, and a vanguard out of reach.
      final threat = GameCard(
        903,
        store.saveCard(
          gameId: 'vanguard',
          name: 'Threat',
          attributes: {'grade': '2', 'cardType': 'normal', 'power': '15000'},
        ),
      );
      you.field[Circle.frontLeft] = FieldUnit(threat);
      engine.state.phase = PlaytestPhase.battle;

      final attack = ai.nextAttack();
      expect(attack, isNotNull);
      expect(attack!.from, Circle.frontLeft);
      expect(attack.to, Circle.frontLeft, reason: 'the threat is the target');
    });

    test('it ignores a rear-guard too small to be worth the attack', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      final ai = PlaytestAi(engine);
      engine.beginPlay();
      final cpu = engine.state.opponent;
      final you = engine.state.you;

      cpu.field[Circle.frontLeft] = FieldUnit(
        GameCard(
          904,
          store.saveCard(
            gameId: 'vanguard',
            name: 'Hunter',
            attributes: {'grade': '2', 'cardType': 'normal', 'power': '20000'},
          ),
        ),
      );
      // A 5000 body is not worth diverting an attack away from the vanguard.
      you.field[Circle.frontLeft] = FieldUnit(
        GameCard(
          905,
          store.saveCard(
            gameId: 'vanguard',
            name: 'Chaff',
            attributes: {'grade': '0', 'cardType': 'normal', 'power': '5000'},
          ),
        ),
      );
      engine.state.phase = PlaytestPhase.battle;

      final attack = ai.nextAttack();
      expect(attack!.to, Circle.vanguard);
    });
  });

  group('the CPU thinks about guarding', () {
    /// An attack of [power] against the CPU's vanguard.
    PendingAttack swing(
      PlaytestEngine engine,
      DeckStore store,
      int power, {
      int critical = 1,
    }) {
      final you = engine.state.you;
      engine.state.phase = PlaytestPhase.battle;
      final attack = engine.declareAttack(
        from: Circle.vanguard,
        to: Circle.vanguard,
      );
      final gap = power - attack.attackPower;
      if (gap != 0) engine.addPower(you, Circle.vanguard, gap);
      you.vanguard!.criticalBonus = critical - 1;
      return attack;
    }

    test(
      'it takes an expensive early hit rather than spending its hand',
      () async {
        final (store, deck) = await buildDeck();
        final engine = engineFor(store, deck);
        final ai = PlaytestAi(engine);
        engine.beginPlay();
        final cpu = engine.state.opponent;
        final before = cpu.hand.length;

        // Undamaged, and the attack needs more than one card to answer.
        final attack = swing(engine, store, cpu.vanguard!.power + 25000);
        ai.guard(attack);

        expect(cpu.hand.length, before, reason: 'it kept its cards');
        expect(attack.connects, isTrue, reason: 'and took the damage');
      },
    );

    test('it answers a cheap attack once the damage matters', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      final ai = PlaytestAi(engine);
      engine.beginPlay();
      final cpu = engine.state.opponent;

      // Undamaged this same attack goes through -- the damage is worth more
      // than the card. Three damage in, the trade turns over.
      cpu.damage.addAll(cpu.deck.sublist(0, 3));
      cpu.deck.removeRange(0, 3);

      final attack = swing(engine, store, cpu.vanguard!.power + 4000);
      ai.guard(attack);

      expect(attack.connects, isFalse);
      expect(attack.guardians.length, 1, reason: 'and no more than needed');
    });

    test('deep in damage it spends more to stay alive', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      final ai = PlaytestAi(engine);
      engine.beginPlay();
      final cpu = engine.state.opponent;

      // The same attack it would have taken at zero damage.
      cpu.damage.addAll(cpu.deck.sublist(0, 4));
      cpu.deck.removeRange(0, 4);
      final attack = swing(engine, store, cpu.vanguard!.power + 25000);
      ai.guard(attack);

      expect(attack.connects, isFalse, reason: 'four damage is not five');
    });

    test('a small early attack is taken, not guarded away', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      final ai = PlaytestAi(engine);
      engine.beginPlay();
      final cpu = engine.state.opponent;
      final before = cpu.hand.length;

      // The reported case: a turn one attack from a grade 0 vanguard, and a
      // hand holding fifteen thousand shield triggers. Answering it costs a
      // card and buys nothing, so it goes through.
      engine.state.phase = PlaytestPhase.battle;
      final attack = engine.declareAttack(
        from: Circle.vanguard,
        to: Circle.vanguard,
      );
      expect(cpu.damageCount, 0);
      ai.guard(attack);

      expect(attack.guardians, isEmpty, reason: 'nothing spent on it');
      expect(cpu.hand.length, before);
      expect(attack.connects, isTrue, reason: 'so the damage lands');
    });

    test('the same attack is answered at four damage', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      final ai = PlaytestAi(engine);
      engine.beginPlay();
      final cpu = engine.state.opponent;

      cpu.damage.addAll(cpu.deck.sublist(0, 4));
      cpu.deck.removeRange(0, 4);

      engine.state.phase = PlaytestPhase.battle;
      final attack = engine.declareAttack(
        from: Circle.vanguard,
        to: Circle.vanguard,
      );
      ai.guard(attack);

      expect(attack.guardians, isNotEmpty, reason: 'four damage is different');
      expect(attack.connects, isFalse);
    });

    test('it saves the perfect guard for the hit that would kill it', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      final ai = PlaytestAi(engine);
      engine.beginPlay();
      final cpu = engine.state.opponent;

      final sentinel = GameCard(
        906,
        store.saveCard(
          gameId: 'vanguard',
          name: 'Perfect Guard',
          attributes: {'grade': '1', 'cardType': 'sentinel', 'shield': '0'},
        ),
      );
      cpu.hand.add(sentinel);

      // A big attack, but not a lethal one: the sentinel stays in hand.
      final attack = swing(engine, store, cpu.vanguard!.power + 40000);
      ai.guard(attack);
      expect(cpu.hand, contains(sentinel));
      expect(attack.perfectGuarded, isFalse);
    });

    test('it lets a rear-guard die rather than guard for it', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      final ai = PlaytestAi(engine);
      engine.beginPlay();
      final cpu = engine.state.opponent;
      final you = engine.state.you;
      final before = cpu.hand.length;

      cpu.field[Circle.frontLeft] = FieldUnit(
        GameCard(
          907,
          store.saveCard(
            gameId: 'vanguard',
            name: 'Body',
            attributes: {'grade': '1', 'cardType': 'normal', 'power': '8000'},
          ),
        ),
      );
      engine.state.phase = PlaytestPhase.battle;
      final attack = engine.declareAttack(
        from: Circle.vanguard,
        to: Circle.frontLeft,
      );
      engine.addPower(you, Circle.vanguard, 10000);
      ai.guard(attack);

      expect(cpu.hand.length, before, reason: 'a body is not worth cards');
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
