import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tcg_decks/games/vanguard/vanguard_data.dart';
import 'package:tcg_decks/models/deck.dart';
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
