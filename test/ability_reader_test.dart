import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tcg_decks/games/card_catalog.dart';
import 'package:tcg_decks/games/vanguard/vanguard_game.dart';
import 'package:tcg_decks/playtest/ability_reader.dart';

/// The reader is only worth having if it refuses more than it accepts, so
/// most of what is below is about what it will *not* play.
void main() {
  group('reading one ability', () {
    Ability? only(String text) {
      final read = readAbilities(text);
      return read.playable.isEmpty ? null : read.playable.first;
    }

    test('an on-attack pump is read whole', () {
      final ability = only(
        '[AUTO](VC):When this unit attacks a vanguard, this unit gets '
        '[Power]+5000 until end of that battle.',
      );
      expect(ability, isNotNull);
      expect(ability!.timing, AbilityTiming.onAttack);
      expect(ability.zones, {'VC'});
      expect(ability.effect.selfPower, 5000);
      expect(ability.effect.untilEndOfBattle, isTrue);
      expect(ability.cost.isFree, isTrue);
    });

    test('a continuous bonus is read', () {
      final ability = only(
        '[CONT](RC):During your turn, this unit gets [Power]+3000.',
      );
      expect(ability!.timing, AbilityTiming.continuous);
      expect(ability.effect.selfPower, 3000);
    });

    test('the draw on being ridden over is read', () {
      final ability = only('[AUTO]:When rode upon, draw a card.');
      expect(ability!.timing, AbilityTiming.onRodeUpon);
      expect(ability.effect.draw, 1);
      expect(ability.zones, isEmpty);
    });

    test('a cost is read along with what it buys', () {
      final ability = only(
        '[AUTO](VC)[1/Turn]:When placed, [COST][Counter-Blast 1], '
        'this unit gets [Power]+10000 until end of turn.',
      );
      expect(ability!.cost.counterBlast, 1);
      expect(ability.oncePerTurn, isTrue);
      expect(ability.effect.selfPower, 10000);
      expect(ability.timing, AbilityTiming.onRide, reason: '(VC) placement');
    });

    test('the spacing the database actually uses is read', () {
      // The real text is "[Power] +5000", not "[Power]+5000".
      final ability = only(
        '[AUTO](RC):When this unit boosts, this unit gets [Power] +4000 '
        'until end of that battle.',
      );
      expect(ability!.effect.selfPower, 4000);
      expect(ability.timing, AbilityTiming.onBoost);
    });

    test('reminder text does not confuse it', () {
      final ability = only(
        '[AUTO](VC):When this unit attacks, this unit gets [Power]+2000 '
        'until end of that battle. (This is a note for the player that runs '
        'on for a while and means nothing mechanically)',
      );
      expect(ability!.effect.selfPower, 2000);
    });

    group('refuses what it cannot follow', () {
      const refused = <String, String>{
        'a choice of target':
            '[AUTO](VC):When this unit attacks, choose one of your '
            'rear-guards, and it gets [Power]+5000 until end of turn.',
        'a search':
            '[ACT](VC):[COST][Counter-Blast 1], look at seven cards from the '
            'top of your deck, search for one card, and call it to (RC).',
        'a retire':
            '[AUTO](VC):When this unit is placed, choose one of your '
            "opponent's rear-guards, and retire it.",
        'an optional cost':
            '[AUTO](VC):When this unit attacks, you may pay the cost. If you '
            'do, draw a card.',
        'a condition it cannot check':
            "[CONT](VC):If your opponent's vanguard is grade 3 or greater, "
            'this unit gets [Power]+5000.',
        'a cost it cannot pay':
            '[ACT](VC):[COST][Put a card from your hand into your soul], '
            'this unit gets [Power]+5000 until end of turn.',
        'an effect with no timing': '[AUTO]:Forerunner',
        'a zone it does not play from':
            '[CONT](Hand):While you are paying the cost for [Stride], this '
            'card gets grade +1.',
      };

      refused.forEach((description, text) {
        test(description, () {
          final read = readAbilities(text);
          expect(read.playable, isEmpty);
          expect(read.unread, hasLength(1), reason: 'handed back, not lost');
        });
      });
    });

    test('a card with two abilities can have one of each', () {
      final read = readAbilities(
        '[AUTO](VC):When this unit attacks a vanguard, this unit gets '
        '[Power]+5000 until end of that battle.\n'
        '[ACT](VC):[COST][Counter-Blast 1], choose one of your opponent\'s '
        'rear-guards, and retire it.',
      );
      expect(read.playable, hasLength(1));
      expect(read.unread, hasLength(1));
    });
  });

  group('against the real card database', () {
    late final List<CatalogCard> cards;

    setUpAll(() {
      const game = VanguardGame();
      cards = parseCatalog(File(game.catalogAsset!).readAsStringSync());
    });

    test('it reads a useful slice and refuses the rest', () {
      var withAbility = 0;
      var readable = 0;
      for (final card in cards) {
        final text = card.attributes['effect'] ?? '';
        if (text.trim().isEmpty) continue;
        withAbility += 1;
        if (readAbilities(text).playable.isNotEmpty) readable += 1;
      }

      // The point of the number is that it is small and known rather than
      // imagined: this is a reader for the simple shapes, and a card outside
      // them is left to the player.
      expect(withAbility, greaterThan(9000));
      expect(readable, greaterThan(150), reason: 'it does reach real cards');
      expect(
        readable,
        lessThan(withAbility ~/ 10),
        reason: 'and it is nowhere near all of them',
      );
    });

    test('nothing it accepts is wildly out of range', () {
      for (final card in cards) {
        for (final ability in readAbilities(
          card.attributes['effect'] ?? '',
        ).playable) {
          final effect = ability.effect;
          expect(effect.selfPower, lessThanOrEqualTo(30000));
          expect(effect.allPower, lessThanOrEqualTo(30000));
          expect(effect.frontRowPower, lessThanOrEqualTo(30000));
          expect(effect.critical, lessThanOrEqualTo(2));
          expect(effect.draw, lessThanOrEqualTo(2));
          expect(ability.cost.counterBlast, lessThanOrEqualTo(3));
        }
      }
    });
  });
}
