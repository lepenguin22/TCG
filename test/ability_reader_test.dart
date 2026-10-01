import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tcg_decks/games/card_catalog.dart';
import 'package:tcg_decks/games/vanguard/vanguard_game.dart';
import 'package:tcg_decks/playtest/ability_reader.dart';

/// The reader holds the half of an ability the board can usefully know: when
/// it fires and what it costs. What it does is left as printed, so most of
/// what is below is about timings, costs and the few things still refused.
void main() {
  group('reading one ability', () {
    PromptedAbility? only(String text) {
      final read = readAbilities(text);
      return read.prompted.isEmpty ? null : read.prompted.first;
    }

    test('an on-attack ability is timed to the attack', () {
      final ability = only(
        '[AUTO](VC):When this unit attacks a vanguard, this unit gets '
        '[Power]+5000 until end of that battle.',
      );
      expect(ability, isNotNull);
      expect(ability!.timing, AbilityTiming.onAttack);
      expect(ability.zones, {'VC'});
      expect(ability.cost.isFree, isTrue);
      expect(ability.oncePerTurn, isFalse);
    });

    test('a placement on one circle can only have meant that circle', () {
      expect(
        only('[AUTO](RC):When placed, draw a card.')!.timing,
        AbilityTiming.onCall,
      );
      expect(
        only('[AUTO](VC):When placed, draw a card.')!.timing,
        AbilityTiming.onRide,
      );
    });

    test('a placement on either stays undecided until it happens', () {
      final ability = only(
        '[AUTO](VC/RC):When this unit is placed on (VC) or (RC), draw a card.',
      );
      expect(ability!.timing, AbilityTiming.onPlaced);
      expect(ability.zones, {'VC', 'RC'});
    });

    test('a [1/Turn] is marked as spent by being used', () {
      final ability = only(
        '[ACT](VC)[1/Turn]:[COST][Counter-Blast 1], choose one of your '
        'rear-guards, and [Stand] it.',
      );
      expect(ability!.oncePerTurn, isTrue);
      expect(ability.timing, AbilityTiming.activated);
    });

    test('the costs the board can spend are read', () {
      expect(
        only('[ACT](VC):[COST][Counter-Blast 2], choose a card, and bind it.')!
            .cost
            .counterBlast,
        2,
      );
      expect(
        only('[ACT](VC):[COST][Soul-Blast 3], choose a card, and bind it.')!
            .cost
            .soulBlast,
        3,
      );
      expect(
        only(
          '[AUTO](VC):When this unit attacks, [COST][Discard a card from '
          'hand], choose one of your units.',
        )!.cost.discard,
        1,
      );
    });

    test('two costs in one bracket are both read', () {
      final cost = only(
        '[ACT](VC):[COST][Counter-Blast 1 & Soul-Blast 1], choose one of your '
        'rear-guards.',
      )!.cost;
      expect(cost.counterBlast, 1);
      expect(cost.soulBlast, 1);
    });

    test('a condition written into the header is kept', () {
      expect(
        only(
          '[AUTO](VC)[Limit-Break 4]:When this unit attacks, choose one of '
          'your opponent\'s rear-guards.',
        )!.condition.damageAtLeast,
        4,
      );
      expect(
        only(
          '[AUTO](VC)[Generation Break 2]:When this unit attacks, choose one '
          'of your rear-guards.',
        )!.condition.generationBreak,
        2,
      );
    });

    test('the Hollow keyword is offered on a call', () {
      final ability = only(
        '[AUTO]:Hollow (When placed on (RC), you may have it become hollowed. '
        'If you do, retire it at the end of turn)',
      );
      expect(ability!.timing, AbilityTiming.onCall);
      expect(ability.zones, {'RC'});
    });

    test('a card discarded for a stride fires on its way to the drop', () {
      expect(
        only(
          '[AUTO]:When this card is discarded from hand while paying the cost '
          'for [Stride], draw a card.',
        )!.timing,
        AbilityTiming.onDiscardedForStride,
      );
    });

    test('two clauses on one card are read separately', () {
      final read = readAbilities(
        '[AUTO](RC):When this unit is placed on (RC), draw a card.\n'
        '[AUTO](VC):When this unit attacks, choose one of your rear-guards.',
      );
      expect(read.prompted, hasLength(2));
      expect(read.prompted.first.timing, AbilityTiming.onCall);
      expect(read.prompted.last.timing, AbilityTiming.onAttack);
    });

    group('what it still refuses', () {
      const refused = <String, String>{
        'a line with no header at all': '[AUTO]:Forerunner',
        'a continuous ability, which has no moment':
            '[CONT](VC):If the number of <Dark Irregulars> in your soul is '
            'six or more, this unit gets [Power]+5000.',
        'a cost it cannot read, since it could not pay it':
            '[ACT](VC):[COST][Put a card from your hand into your soul], '
            'this unit gets [Power]+5000 until end of turn.',
        'a cost that spends the unit itself':
            '[AUTO](RC):When this unit attacks, [COST][Retire this unit], '
            'draw a card.',
        'a timing it has not been taught':
            '[AUTO](VC):At the beginning of your battle phase, draw a card.',
      };

      refused.forEach((description, text) {
        test(description, () {
          final read = readAbilities(text);
          expect(read.prompted, isEmpty);
          expect(read.unread, hasLength(1), reason: 'handed back, not lost');
        });
      });

      test('and it says which part stopped it', () {
        expect(
          refusedPart('[CONT](VC):Your opponent cannot call units to (GC).'),
          contains('continuous'),
        );
      });
    });
  });

  group('against the real card database', () {
    late final List<CatalogCard> cards;

    setUpAll(() {
      const game = VanguardGame();
      cards = parseCatalog(File(game.catalogAsset!).readAsStringSync());
    });

    test('it reaches a useful slice and hands back the rest', () {
      var withAbility = 0;
      var offered = 0;
      for (final card in cards) {
        final text = card.attributes['effect'] ?? '';
        if (text.trim().isEmpty) continue;
        withAbility += 1;
        if (readAbilities(text).prompted.isNotEmpty) offered += 1;
      }

      // The point of the number is that it is known rather than imagined. It
      // is the timing vocabulary that decides it, so it moves when that is
      // widened and these bounds are deliberately loose.
      expect(withAbility, greaterThan(9000));
      expect(offered, greaterThan(2000), reason: 'it reaches real cards');
      expect(
        offered,
        lessThan(withAbility),
        reason: 'and nowhere near all of them',
      );
    });

    test('nothing it offers costs more than the game allows', () {
      for (final card in cards) {
        for (final ability in readAbilities(
          card.attributes['effect'] ?? '',
        ).prompted) {
          // The real maxima in the pool are 4, 15 and 1; these are a little
          // above that, to catch a number read out of the wrong place rather
          // than to pin the card pool down.
          expect(ability.cost.counterBlast, lessThanOrEqualTo(5));
          expect(ability.cost.soulBlast, lessThanOrEqualTo(15));
          expect(ability.cost.discard, lessThanOrEqualTo(3));
          // Never offered: the board pays on accept and the player applies
          // the effect afterwards.
          expect(ability.cost.retireSelf, isFalse);
          expect(ability.cost.selfToSoul, isFalse);
        }
      }
    });
  });
}
