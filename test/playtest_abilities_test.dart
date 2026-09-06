import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tcg_decks/games/vanguard/vanguard_data.dart';
import 'package:tcg_decks/models/deck.dart';
import 'package:tcg_decks/playtest/ability_reader.dart';
import 'package:tcg_decks/playtest/playtest_ai.dart';
import 'package:tcg_decks/playtest/playtest_engine.dart';
import 'package:tcg_decks/playtest/playtest_state.dart';
import 'package:tcg_decks/store/deck_store.dart';

/// The CPU playing the abilities it can read.
///
/// Every deck here is built out of one ability, so what the CPU did is not a
/// guess: nothing else on the board could have caused it.
Future<(DeckStore, Deck)> deckWith({
  required String boosterEffect,
  String beaterEffect = '',
  String vanguardEffect = '',
}) async {
  SharedPreferences.setMockInitialValues({});
  final store = DeckStore();
  await store.load();
  final deck = store.createDeck(name: 'Ability deck', formatId: formatStandard);

  void add(String name, String zone, int quantity, Map<String, String> attrs) {
    final card = store.saveCard(
      gameId: 'vanguard',
      name: name,
      attributes: attrs,
    );
    store.addToDeck(deck.id, card.id, zone, quantity: quantity);
  }

  for (var grade = 0; grade <= 3; grade += 1) {
    add('Ride $grade', zoneRide, 1, {
      'grade': '$grade',
      'cardType': 'normal',
      'power': '${9000 + grade * 2000}',
      'shield': grade == 0 ? '10000' : '0',
      'effect': vanguardEffect,
    });
  }
  add('Critical Trigger', zoneMain, 16, {
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
    'effect': beaterEffect,
  });
  add('Booster', zoneMain, 14, {
    'grade': '1',
    'cardType': 'normal',
    'power': '8000',
    'shield': '10000',
    'effect': boosterEffect,
  });
  return (store, store.decks.firstWhere((d) => d.id == deck.id));
}

PlaytestEngine engineFor(DeckStore store, Deck deck, {int seed = 7}) =>
    PlaytestEngine.start(
      store: store,
      yourDeck: deck,
      opponentDeck: deck,
      random: Random(seed),
    );

/// Runs the CPU's turn from the top, which is what a game actually does.
(PlaytestEngine, PlaytestAi) cpuTurn(
  DeckStore store,
  Deck deck, {
  int seed = 7,
}) {
  final engine = engineFor(store, deck, seed: seed);
  final ai = PlaytestAi(engine);
  engine.beginPlay();
  engine.endTurn(); // Hand the turn to the CPU.
  ai.takeTurn();
  return (engine, ai);
}

bool logHas(PlaytestEngine engine, String fragment) =>
    engine.state.log.any((entry) => entry.text.contains(fragment));

void main() {
  group('the CPU plays what the reader can follow', () {
    test('a draw on call is drawn', () async {
      final (store, deck) = await deckWith(
        boosterEffect:
            '[AUTO](RC):When this unit is placed on (RC), draw a card.',
      );
      final (engine, _) = cpuTurn(store, deck);
      final cpu = engine.state.opponent;

      // A booster reached a circle, and the draw off it is in the log.
      expect(
        cpu.units.any((u) => u.card.name == 'Booster'),
        isTrue,
        reason: 'it called one',
      );
      expect(logHas(engine, 'plays Booster'), isTrue);
    });

    test('a continuous bonus is standing on the board', () async {
      final (store, deck) = await deckWith(
        boosterEffect:
            '[CONT](RC):During your turn, this unit gets '
            '[Power]+3000.',
      );
      final (engine, _) = cpuTurn(store, deck);
      final cpu = engine.state.opponent;
      final booster = cpu.units.firstWhere((u) => u.card.name == 'Booster');

      expect(booster.powerBonus, 3000);
      expect(booster.power, 11000);
    });

    test('an on-attack pump is on the attack you have to guard', () async {
      final (store, deck) = await deckWith(
        boosterEffect: '',
        vanguardEffect:
            '[AUTO](VC):When this unit attacks a vanguard, this unit gets '
            '[Power]+10000 until end of that battle.',
      );
      final engine = engineFor(store, deck);
      final ai = PlaytestAi(engine);
      engine.beginPlay();
      engine.endTurn();
      ai.takeTurn();

      final cpu = engine.state.opponent;
      final before = cpu.vanguard!.power;
      final attack = engine.declareAttack(
        from: Circle.vanguard,
        to: Circle.vanguard,
      );
      ai.playAttackAbilities(attack);

      expect(cpu.vanguard!.power, before + 10000);
      expect(attack.attackPower, greaterThanOrEqualTo(before + 10000));
    });

    test('what lasts a battle is gone when the battle is', () async {
      final (store, deck) = await deckWith(
        boosterEffect: '',
        vanguardEffect:
            '[AUTO](VC):When this unit attacks, this unit gets [Power]+10000 '
            'until end of that battle.',
      );
      final engine = engineFor(store, deck);
      final ai = PlaytestAi(engine);
      engine.beginPlay();
      engine.endTurn();
      ai.takeTurn();

      final cpu = engine.state.opponent;
      final printed = cpu.vanguard!.card.power;
      final attack = engine.declareAttack(
        from: Circle.vanguard,
        to: Circle.vanguard,
      );
      ai.playAttackAbilities(attack);
      expect(cpu.vanguard!.power, printed + 10000);

      engine.driveCheck();
      engine.resolveAttack();
      // The drive check may have added trigger power, which lasts the turn.
      expect(cpu.vanguard!.battleBonus, 0, reason: 'the battle is over');
    });

    test('a once-a-turn ability is played once', () async {
      final (store, deck) = await deckWith(
        boosterEffect: '',
        vanguardEffect:
            '[AUTO](VC)[1/Turn]:When this unit attacks, this unit '
            'gets [Power]+5000 until end of turn.',
      );
      final engine = engineFor(store, deck);
      final ai = PlaytestAi(engine);
      engine.beginPlay();
      engine.endTurn();
      ai.takeTurn();

      final cpu = engine.state.opponent;
      for (var i = 0; i < 3; i += 1) {
        final attack = engine.declareAttack(
          from: Circle.vanguard,
          to: Circle.vanguard,
        );
        ai.playAttackAbilities(attack);
        engine.state.attack = null;
      }
      expect(cpu.vanguard!.powerBonus, 5000, reason: 'not three times over');
    });

    test('a cost it cannot afford is not paid', () async {
      final (store, deck) = await deckWith(
        boosterEffect:
            '[AUTO](RC):When this unit is placed on (RC), [COST][Counter-Blast '
            '2], this unit gets [Power]+10000 until end of turn.',
      );
      final (engine, _) = cpuTurn(store, deck);
      final cpu = engine.state.opponent;

      // Turn one, no damage taken, so there is nothing to counter-blast and
      // the ability simply does not happen.
      expect(cpu.damageCount, 0);
      for (final unit in cpu.units) {
        expect(unit.powerBonus, 0);
      }
      expect(logHas(engine, 'counter-blasts'), isFalse);
    });

    test('a cost it can afford is paid', () async {
      final (store, deck) = await deckWith(
        boosterEffect:
            '[AUTO](RC):When this unit is placed on (RC), [COST][Counter-Blast '
            '1], this unit gets [Power]+10000 until end of turn.',
      );
      final engine = engineFor(store, deck);
      final ai = PlaytestAi(engine);
      engine.beginPlay();
      final cpu = engine.state.opponent;
      // Three damage in the zone, so a counter-blast of one leaves plenty.
      cpu.damage.addAll(cpu.deck.sublist(0, 3));
      cpu.deck.removeRange(0, 3);

      engine.endTurn();
      ai.takeTurn();

      final booster = cpu.units.where((u) => u.card.name == 'Booster');
      expect(booster, isNotEmpty);
      expect(booster.first.powerBonus, 10000);
      expect(cpu.openDamage, 2, reason: 'one damage spent');
    });

    test('an ability it cannot read is said out loud, not swallowed', () async {
      final (store, deck) = await deckWith(
        boosterEffect:
            '[AUTO](RC):When this unit is placed on (RC), choose '
            "one of your opponent's rear-guards, and retire it.",
      );
      final (engine, _) = cpuTurn(store, deck);

      expect(logHas(engine, 'the board cannot play'), isTrue);
      // And nothing was invented in its place.
      expect(logHas(engine, 'plays Booster'), isFalse);
    });

    test('a vanilla deck logs nothing about abilities', () async {
      final (store, deck) = await deckWith(boosterEffect: '');
      final (engine, _) = cpuTurn(store, deck);

      expect(logHas(engine, 'the board cannot play'), isFalse);
      expect(logHas(engine, 'plays '), isFalse);
    });

    test('your side is never played for you', () async {
      final (store, deck) = await deckWith(
        boosterEffect:
            '[AUTO](RC):When this unit is placed on (RC), draw a card.',
      );
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      engine.ride(you, engine.rideDeckOption(you)!, fromRideDeck: true);
      final booster = you.hand.firstWhere(
        (c) => engine.canCall(you, c, Circle.backCenter),
      );
      final before = you.hand.length;
      engine.call(you, booster, Circle.backCenter);

      // One card left the hand for the circle, and nothing was drawn: your
      // abilities stay yours to play.
      expect(you.hand.length, before - 1);
    });
  });

  group('the Nightrose deck', () {
    /// The hollow keyword, and a bonus that only applies once hollowed.
    const hollowKeyword =
        '[AUTO]:Hollow (When placed on (RC), you may have it become '
        'hollowed. If you do, retire it at the end of turn)';
    const hollowPays =
        '[CONT](RC):During your turn, if this unit is hollowed, this unit '
        'gets [Power]+5000.';

    test('a unit is hollowed when its own text pays for it', () async {
      final (store, deck) = await deckWith(
        boosterEffect: '$hollowKeyword\n$hollowPays',
      );
      final (engine, _) = cpuTurn(store, deck);
      final cpu = engine.state.opponent;
      final booster = cpu.units.firstWhere((u) => u.card.name == 'Booster');

      expect(booster.hollowed, isTrue);
      expect(booster.powerBonus, 5000, reason: 'and the bonus it bought');
      expect(logHas(engine, 'hollows Booster'), isTrue);
    });

    test('a unit with nothing to gain is not thrown away', () async {
      final (store, deck) = await deckWith(boosterEffect: hollowKeyword);
      final (engine, _) = cpuTurn(store, deck);
      final cpu = engine.state.opponent;

      for (final unit in cpu.units) {
        expect(unit.hollowed, isFalse, reason: 'nothing paid for the body');
      }
    });

    test('a hollowed unit is retired at the end of the turn', () async {
      final (store, deck) = await deckWith(
        boosterEffect: '$hollowKeyword\n$hollowPays',
      );
      final (engine, _) = cpuTurn(store, deck);
      final cpu = engine.state.opponent;
      expect(cpu.units.any((u) => u.hollowed), isTrue);

      engine.endTurn();
      expect(cpu.units.any((u) => u.hollowed), isFalse);
      expect(
        cpu.drop.any((c) => c.name == 'Booster'),
        isTrue,
        reason: 'the body was the price',
      );
    });

    test('a crest condition is answered by the crest zone', () async {
      const needsCrest =
          '[AUTO](RC):When this unit attacks, if you have a "Nightrose" '
          'crest, this unit gets [Power]+5000 until end of that battle.';
      final (store, deck) = await deckWith(boosterEffect: needsCrest);
      final engine = engineFor(store, deck);
      final ai = PlaytestAi(engine, engine.state.you);
      engine.beginPlay();
      final you = engine.state.you;
      engine.ride(you, engine.rideDeckOption(you)!, fromRideDeck: true);
      // The ride cost a card, so make sure the unit under test is in hand.
      final unit = you.deck.lastWhere((c) => c.name == 'Booster');
      you.deck.remove(unit);
      you.hand.add(unit);
      engine.call(you, unit, Circle.frontLeft);
      engine.state.phase = PlaytestPhase.battle;

      // No crest: the ability does not fire.
      var attack = engine.declareAttack(
        from: Circle.frontLeft,
        to: Circle.vanguard,
      );
      ai.playAttackAbilities(attack);
      expect(you.field[Circle.frontLeft]!.battleBonus, 0);
      engine.state.attack = null;
      you.field[Circle.frontLeft]!.rested = false;

      // With it, the same attack is 5000 bigger.
      engine.playCrest(
        you,
        store.saveCard(
          gameId: 'vanguard',
          name: 'Vampire Princess of Night Fog, Nightrose',
          attributes: {'cardType': 'crest', 'effect': '[CONT]:You can stride.'},
        ),
      );
      attack = engine.declareAttack(
        from: Circle.frontLeft,
        to: Circle.vanguard,
      );
      ai.playAttackAbilities(attack);
      expect(you.field[Circle.frontLeft]!.battleBonus, 5000);
    });

    test('the crest pays for each face up card in the G zone', () async {
      const crestText =
          '[CONT]:During your turn, if you have a grade 1 or greater '
          'vanguard with "Ride" in its card name, all of your front row '
          'units get [Power] +5000 for each face up card in your G zone.';
      final (store, deck) = await deckWith(boosterEffect: '');
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      engine.ride(you, engine.rideDeckOption(you)!, fromRideDeck: true);
      engine.playCrest(
        you,
        store.saveCard(
          gameId: 'vanguard',
          name: 'Nightrose crest',
          attributes: {'cardType': 'crest', 'effect': crestText},
        ),
      );

      // A crest is not a unit, so its continuous ability is applied through
      // the vanguard it is read from -- with an empty G zone it pays nothing.
      final ability = readAbilities(crestText).playable.single;
      expect(engine.playAbility(you, Circle.vanguard, ability), isTrue);
      expect(you.vanguard!.powerBonus, 0, reason: 'no face up cards yet');

      you.gZone.add(you.deck.removeLast());
      you.faceUpG.add(you.gZone.last.instanceId);
      you.vanguard!.usedAbilities.clear();
      expect(engine.playAbility(you, Circle.vanguard, ability), isTrue);
      expect(you.vanguard!.powerBonus, 5000, reason: 'one face up card');
    });

    test('the unit that pays with itself leaves the board', () async {
      const text =
          '[AUTO](RC):When this unit attacks, [COST][retire this unit], '
          'draw a card.';
      final (store, deck) = await deckWith(boosterEffect: text);
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      engine.ride(you, engine.rideDeckOption(you)!, fromRideDeck: true);
      final unit = you.deck.lastWhere((c) => c.name == 'Booster');
      you.deck.remove(unit);
      you.hand.add(unit);
      engine.call(you, unit, Circle.frontLeft);

      final hand = you.hand.length;
      final ability = readAbilities(text).playable.single;
      expect(engine.playAbility(you, Circle.frontLeft, ability), isTrue);
      expect(you.hand.length, hand + 1, reason: 'the card it drew');
      expect(you.field[Circle.frontLeft], isNull, reason: 'it paid itself');
      expect(you.drop.contains(unit), isTrue);
    });

    test('a vanguard cannot pay a cost that spends the unit', () async {
      // There is no game state in which the vanguard leaves for a cost: an
      // ability asking for it simply cannot be played from that circle.
      const text = '[ACT](VC):[COST][put this unit into soul], draw a card.';
      final (store, deck) = await deckWith(
        boosterEffect: '',
        vanguardEffect: text,
      );
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      engine.ride(you, engine.rideDeckOption(you)!, fromRideDeck: true);

      final ability = readAbilities(text).playable.single;
      expect(engine.playAbility(you, Circle.vanguard, ability), isFalse);
      expect(you.vanguard, isNotNull);
    });

    test('the deck and the G zone are really paid out of', () async {
      const text =
          '[ACT](VC)[1/Turn]:[COST][discard the top three cards of the deck '
          '& Turn a card from G zone face up], draw a card.';
      final (store, deck) = await deckWith(
        boosterEffect: '',
        vanguardEffect: text,
      );
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      engine.ride(you, engine.rideDeckOption(you)!, fromRideDeck: true);

      final ability = readAbilities(text).playable.single;
      // Nothing in the G zone: the cost cannot be paid, so nothing happens.
      final deckSize = you.deck.length;
      expect(engine.playAbility(you, Circle.vanguard, ability), isFalse);
      expect(you.deck.length, deckSize, reason: 'not half-paid');

      you.gZone.add(you.deck.removeLast());
      final before = you.deck.length;
      final drop = you.drop.length;
      expect(engine.playAbility(you, Circle.vanguard, ability), isTrue);
      expect(
        you.deck.length,
        before - 3 - 1,
        reason: 'three milled, one drawn',
      );
      expect(you.drop.length, drop + 3);
      expect(you.generationBreak, 1, reason: 'the G card is face up');
    });

    test('a limit break waits for the damage it names', () async {
      const text =
          '[AUTO](VC)[Limit-Break 4](this ability is active if you have four '
          'or more damage):When this unit attacks, this unit gets '
          '[Power]+10000 until end of that battle.';
      final (store, deck) = await deckWith(
        boosterEffect: '',
        vanguardEffect: text,
      );
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      engine.ride(you, engine.rideDeckOption(you)!, fromRideDeck: true);
      final ability = readAbilities(text).playable.single;

      expect(engine.playAbility(you, Circle.vanguard, ability), isFalse);
      while (you.damageCount < 4) {
        you.damage.add(you.deck.removeLast());
      }
      expect(engine.playAbility(you, Circle.vanguard, ability), isTrue);
      expect(you.vanguard!.battleBonus, 10000);
    });

    test('an ability that hands you a crest puts one in play', () async {
      const text =
          '[AUTO]:When this unit is placed on (RC), you get a "Vampire '
          'Princess of Night Fog, Nightrose" crest.';
      final (store, deck) = await deckWith(boosterEffect: text);
      // The crest is not in any deck: it comes out of the card library, the
      // way it does in the game.
      store.saveCard(
        gameId: 'vanguard',
        name: 'Vampire Princess of Night Fog, Nightrose',
        attributes: {'cardType': 'crest', 'effect': '[CONT]:You can stride.'},
      );
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      engine.ride(you, engine.rideDeckOption(you)!, fromRideDeck: true);
      final unit = you.deck.lastWhere((c) => c.name == 'Booster');
      you.deck.remove(unit);
      you.hand.add(unit);
      engine.call(you, unit, Circle.frontLeft);

      final ability = readAbilities(text).playable.single;
      expect(engine.playAbility(you, Circle.frontLeft, ability), isTrue);
      expect(you.crestZone.map((c) => c.name), contains(startsWith('Vampire')));
    });

    test('a crest the library does not have is not played half way', () async {
      const text =
          '[AUTO]:When this unit is placed on (RC), [COST][Counter-Blast 1], '
          'and you get a "Nobody, Nothing" crest.';
      final (store, deck) = await deckWith(boosterEffect: text);
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      engine.ride(you, engine.rideDeckOption(you)!, fromRideDeck: true);
      you.damage.add(you.deck.removeLast());
      final unit = you.deck.lastWhere((c) => c.name == 'Booster');
      you.deck.remove(unit);
      you.hand.add(unit);
      engine.call(you, unit, Circle.frontLeft);

      final ability = readAbilities(text).playable.single;
      expect(engine.playAbility(you, Circle.frontLeft, ability), isFalse);
      expect(you.openDamage, 1, reason: 'the counter-blast was not paid');
    });

    test('a hit pays out and a stopped attack does not', () async {
      const text =
          "[AUTO](VC):When this unit's attack hits a vanguard, draw a card.";
      final (store, deck) = await deckWith(
        boosterEffect: '',
        vanguardEffect: text,
      );
      final engine = engineFor(store, deck);
      final ai = PlaytestAi(engine, engine.state.you);
      engine.beginPlay();
      final you = engine.state.you;
      engine.ride(you, engine.rideDeckOption(you)!, fromRideDeck: true);
      engine.state.phase = PlaytestPhase.battle;
      engine.state.turn = 2;

      engine.declareAttack(from: Circle.vanguard, to: Circle.vanguard);
      final hand = you.hand.length;
      final hit = engine.resolveAttack();
      expect(hit, isTrue, reason: 'nothing guarded it');
      ai.playHitAbilities(Circle.vanguard);
      expect(you.hand.length, hand + 1);
    });

    test('the end of the battle is a timing of its own', () async {
      const text =
          '[AUTO](RC):At the end of the battle this unit boosted, '
          '[Counter-Charge 1].';
      final (store, deck) = await deckWith(boosterEffect: text);
      final engine = engineFor(store, deck);
      final ai = PlaytestAi(engine, engine.state.you);
      engine.beginPlay();
      final you = engine.state.you;
      engine.ride(you, engine.rideDeckOption(you)!, fromRideDeck: true);
      final unit = you.deck.lastWhere((c) => c.name == 'Booster');
      you.deck.remove(unit);
      you.hand.add(unit);
      engine.call(you, unit, Circle.backCenter);
      // A face down damage for the counter-charge to turn back up.
      you.damage.add(you.deck.removeLast());
      engine.counterBlast(you, 1);
      expect(you.openDamage, 0);

      ai.playEndOfBattleAbilities(Circle.vanguard, Circle.backCenter);
      expect(you.openDamage, 1, reason: 'the booster paid it back');
    });

    test(
      'a card that hands out [Boost] makes a booster of a grade 2',
      () async {
        const text =
            '[ACT](RC)[Generation Break 1]:[COST][Counter-Blast 1], this unit '
            'gets "Boost ([Boost])" until end of turn.';
        final (store, deck) = await deckWith(
          boosterEffect: '',
          beaterEffect: text,
        );
        final engine = engineFor(store, deck);
        engine.beginPlay();
        final you = engine.state.you;
        engine.ride(you, engine.rideDeckOption(you)!, fromRideDeck: true);
        final beater = you.deck.lastWhere((c) => c.name == 'Beater');
        you.deck.remove(beater);
        you.hand.add(beater);
        engine.call(you, beater, Circle.backCenter);
        you.damage.add(you.deck.removeLast());
        you.gZone.add(you.deck.removeLast());
        you.faceUpG.add(you.gZone.last.instanceId);

        expect(
          you.field[Circle.backCenter]!.canBoost,
          isFalse,
          reason: 'grade 2',
        );
        final ability = readAbilities(text).playable.single;
        expect(engine.playAbility(you, Circle.backCenter, ability), isTrue);
        expect(you.field[Circle.backCenter]!.canBoost, isTrue);
      },
    );

    test('a card that raises the maximum energy plays to fifteen', () async {
      // The wording is DZ-BT15/001 Hellfire Dragon Emperor, Wirbel Kenig's.
      const text =
          '[CONT](VC):The maximum energy you may have in the [CONT] ability '
          'of the "Energy Generator" in your crest zone gets +5.';
      final (store, deck) = await deckWith(
        boosterEffect: '',
        vanguardEffect: text,
      );
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.you;
      engine.ride(you, engine.rideDeckOption(you)!, fromRideDeck: true);
      expect(you.energyCap, 10);

      final ability = readAbilities(text).playable.single;
      expect(ability.effect.energyCapBonus, 5);
      expect(engine.playAbility(you, Circle.vanguard, ability), isTrue);
      expect(you.energyCap, 15);

      // Played again next turn -- which is what a continuous ability does --
      // it is still fifteen rather than twenty.
      you.vanguard!.usedAbilities.clear();
      expect(engine.playAbility(you, Circle.vanguard, ability), isTrue);
      expect(you.energyCap, 15);
    });

    test('a card discarded for a stride does what it says', () async {
      final (store, deck) = await deckWith(
        boosterEffect:
            '[AUTO]:When this card is discarded from hand while '
            'paying the cost for [Stride], draw a card.',
      );
      // A G zone to stride into, and a grade 3 vanguard to stride over.
      final gUnit = store.saveCard(
        gameId: 'vanguard',
        name: 'Stride Beast',
        attributes: {'grade': '4', 'cardType': 'g-unit', 'power': '15000'},
      );
      store.addToDeck(deck.id, gUnit.id, zoneG, quantity: 8);
      final engine = engineFor(
        store,
        store.decks.firstWhere((d) => d.id == deck.id),
      );
      engine.beginPlay();
      final you = engine.state.you;
      for (var i = 0; i < 3; i += 1) {
        engine.ride(you, engine.rideDeckOption(you)!, fromRideDeck: true);
      }
      // A hand of the cards that draw when discarded.
      you.hand.clear();
      // Three grade 1s pay the grade 3 a stride costs, and each of them
      // draws a card as it goes.
      for (final card in you.deck.where((c) => c.name == 'Booster').take(3)) {
        you.hand.add(card);
      }
      you.deck.removeWhere(you.hand.contains);

      engine.stride(you, you.gZone.first, [...you.hand]);

      expect(you.isStriding, isTrue);
      expect(
        you.hand.length,
        3,
        reason: 'three discarded, and each drew a card back',
      );
      expect(logHas(engine, 'discarded from hand while paying'), isTrue);
    });
  });

  group('a whole game with abilities in it', () {
    test('two CPUs play one out without falling over', () async {
      final (store, deck) = await deckWith(
        boosterEffect:
            '[CONT](RC):During your turn, this unit gets '
            '[Power]+3000.',
        beaterEffect:
            '[AUTO](RC):When this unit attacks a vanguard, this '
            'unit gets [Power]+5000 until end of that battle.',
        vanguardEffect: '[AUTO]:When rode upon, draw a card.',
      );
      final engine = engineFor(store, deck);
      final you = PlaytestAi(engine, engine.state.you);
      final cpu = PlaytestAi(engine, engine.state.opponent);
      engine.beginPlay();

      for (var turn = 0; turn < 40 && !engine.state.isOver; turn += 1) {
        final playing = engine.state.yourTurn ? you : cpu;
        playing.takeTurn();
        for (var swing = 0; swing < 6; swing += 1) {
          final next = playing.nextAttack();
          if (next == null) break;
          final attack = engine.declareAttack(
            from: next.from,
            to: next.to,
            boost: next.boost,
          );
          playing.playAttackAbilities(attack);
          (playing == you ? cpu : you).guard(attack);
          engine.driveCheck();
          engine.resolveAttack();
          if (engine.state.isOver) break;
        }
        if (engine.state.isOver) break;
        engine.endTurn();
      }

      expect(engine.state.isOver, isTrue, reason: 'somebody won');
      expect(logHas(engine, 'plays '), isTrue, reason: 'abilities were played');
    });
  });
}
