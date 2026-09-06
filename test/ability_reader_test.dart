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

    test('a condition about the crest is read, not refused', () {
      final ability = only(
        '[AUTO](RC):When this unit attacks, if you have a "Vampire Princess '
        'of Night Fog, Nightrose" crest, this unit gets [Power]+5000 until '
        'end of that battle.',
      );
      expect(ability, isNotNull);
      expect(
        ability!.condition.crestNamed,
        'vampire princess of night fog, nightrose',
        reason: 'names are folded; the board matches without case',
      );
      expect(ability.effect.selfPower, 5000);
    });

    test('a Generation Break in the header is a condition', () {
      final ability = only(
        '[CONT](RC)[Generation Break 2]:During your turn, if this unit is '
        'hollowed, this unit gets [Power]+10000.',
      );
      expect(ability!.condition.generationBreak, 2);
      expect(ability.condition.hollowed, isTrue);
      expect(ability.timing, AbilityTiming.continuous);
    });

    test('the Hollow keyword is an ability of its own', () {
      final ability = only(
        '[AUTO]:Hollow (When placed on (RC), you may have it become '
        'hollowed. If you do, retire it at the end of turn)',
      );
      expect(ability!.timing, AbilityTiming.onCall);
      expect(ability.effect.becomeHollowed, isTrue);
      expect(ability.zones, {'RC'});
    });

    test('power for each face up card in the G zone scales', () {
      final ability = only(
        '[CONT]:During your turn, if you have a grade 3 or greater vanguard '
        'with "Nightrose" in its card name, all of your front row units get '
        '[Power] +5000 for each face up card in your G zone.',
      );
      expect(ability!.effect.frontRowPower, 5000);
      expect(ability.effect.perFaceUpG, isTrue);
      expect(ability.condition.vanguardGrade, 3);
      expect(ability.condition.vanguardNamed, 'nightrose');
    });

    test('the stride discard is a timing', () {
      final ability = only(
        '[AUTO]:When this card is discarded from hand while paying the cost '
        'for [Stride], draw a card.',
      );
      expect(ability!.timing, AbilityTiming.onDiscardedForStride);
      expect(ability.effect.draw, 1);
    });

    test('a drop count is read where the card spells the number', () {
      final ability = only(
        '[AUTO](RC):When this unit attacks, if your drop has ten or more '
        'cards, this unit gets [Power]+10000 until end of that battle.',
      );
      expect(ability!.condition.dropAtLeast, 10);
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
            '[CONT](VC):If the number of <Dark Irregulars> in your soul is '
            'six or more, this unit gets [Power]+5000.',
        'a condition about a zone it does not count':
            '[CONT](RC):If your order zone has three or more set orders, '
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

    group('the shapes the reader has since learned', () {
      test("the opponent's vanguard grade is a condition it can check", () {
        final ability = only(
          "[CONT](VC):If your opponent's vanguard is grade 3 or greater, "
          'this unit gets [Power]+5000.',
        );
        expect(ability!.condition.foeVanguardGrade, 3);
      });

      test('a limit break is four damage and nothing more', () {
        final ability = only(
          '[AUTO](VC)[Limit-Break 4](this ability is active if you have four '
          'or more damage):When this unit attacks a vanguard, this unit gets '
          '[Power]+5000 until end of that battle.',
        );
        expect(ability!.condition.damageAtLeast, 4);
        expect(ability.timing, AbilityTiming.onAttack);
      });

      test('the board sizes it can count are read', () {
        expect(
          only(
            '[CONT](VC):If your hand has three or more cards, this unit gets '
            '[Power]+2000.',
          )!.condition.handAtLeast,
          3,
        );
        expect(
          only(
            '[CONT](VC):If your damage zone has four or more cards, this '
            'unit gets [Power]+2000.',
          )!.condition.damageAtLeast,
          4,
        );
        expect(
          only(
            '[CONT](VC):If you have three or more rear-guards, this unit '
            'gets [Power]+2000.',
          )!.condition.rearGuardsAtLeast,
          3,
        );
      });

      test('two costs in one bracket are both paid', () {
        final ability = only(
          '[AUTO](VC):When this unit attacks, [COST][Counter-Blast 1 & '
          'Soul-Blast 1], draw a card.',
        );
        expect(ability!.cost.counterBlast, 1);
        expect(ability.cost.soulBlast, 1);
        expect(ability.effect.draw, 1);
      });

      test('the costs that spend the unit itself are read', () {
        expect(
          only('[ACT](RC):[COST][[Rest] this unit], draw a card.')!
              .cost
              .restSelf,
          isTrue,
        );
        expect(
          only('[ACT](RC):[COST][put this unit into soul], draw a card.')!
              .cost
              .selfToSoul,
          isTrue,
        );
        expect(
          only(
            '[AUTO](RC):When this unit attacks, [COST][retire this unit], '
            'draw a card.',
          )!.cost.retireSelf,
          isTrue,
        );
      });

      test('a unit is never retired to give itself power', () {
        // Half-reading this would leave the bonus on a unit that is not
        // there any more, so the whole clause is refused instead.
        expect(
          only(
            '[AUTO](RC):When this unit attacks, [COST][retire this unit], '
            'this unit gets [Power]+5000 until end of turn.',
          ),
          isNull,
        );
      });

      test('the deck and the G zone can be paid out of', () {
        expect(
          only(
            '[ACT](VC):[COST][discard the top three cards of the deck], '
            'draw a card.',
          )!.cost.mill,
          3,
        );
        expect(
          only(
            '[ACT](VC)[1/Turn]:[COST][Turn a card from G zone face up], '
            'draw a card.',
          )!.cost.flipG,
          1,
        );
      });

      test('a cost whose number it cannot read is refused, not made free', () {
        expect(
          only(
            '[ACT](VC):[COST][choose several cards from hand, and discard '
            'them], draw a card.',
          ),
          isNull,
        );
      });

      test('the crest an ability hands you is read by name', () {
        final ability = only(
          '[AUTO]:When this unit is placed on (VC), draw a card, and you get '
          'a "Vampire Princess of Night Fog, Nightrose" crest.',
        );
        expect(
          ability!.effect.crestNamed,
          'vampire princess of night fog, nightrose',
        );
        expect(ability.effect.draw, 1);
      });

      test('the timings it has learned fire on the right thing', () {
        expect(
          only(
            "[AUTO](VC):When this unit's attack hits a vanguard, "
            '[COST][Counter-Blast 1], draw a card.',
          )!.timing,
          AbilityTiming.onHit,
        );
        expect(
          only('[AUTO](RC):At the end of your turn, [Counter-Charge 1].')!
              .timing,
          AbilityTiming.endOfTurn,
        );
        expect(
          only(
            '[AUTO](RC):When your G unit [Stride] during your turn, this '
            'unit gets [Power]+5000 until end of turn.',
          )!.timing,
          AbilityTiming.onStride,
        );
        expect(
          only(
            '[AUTO]:When this unit is placed on (RC) from hand, draw a card.',
          )!.timing,
          AbilityTiming.onCall,
        );
        expect(
          only('[AUTO]:When this unit is placed on (VC) or (RC), draw a card.')!
              .timing,
          AbilityTiming.onPlaced,
        );
      });

      test('power and critical given together are both read', () {
        final ability = only(
          '[AUTO](VC):When this unit attacks a vanguard, this unit gets '
          '[Power]+10000/[Critical]+1 until end of that battle.',
        );
        expect(ability!.effect.selfPower, 10000);
        expect(ability.effect.critical, 1);
        expect(ability.effect.untilEndOfBattle, isTrue);
      });

      test('two cards drawn are two, not one', () {
        expect(
          only('[AUTO]:When rode upon, draw three cards.')!.effect.draw,
          3,
        );
      });

      test('a misprinted bracket is straightened out rather than refused', () {
        // The card mirror prints "[Counter-Blast]1]" on a few hundred cards.
        final ability = only(
          '[AUTO](VC):When this unit attacks, [COST][Counter-Blast]1], '
          'draw a card.',
        );
        expect(ability!.cost.counterBlast, 1);
      });

      test('the refused part says which phrase to teach it next', () {
        expect(
          refusedPart(
            '[AUTO](VC):When this unit attacks, choose one of your '
            'rear-guards, and it gets [Power]+5000 until end of turn.',
          ),
          'choose one of your rear-guards',
        );
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
