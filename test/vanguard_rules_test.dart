import 'package:flutter_test/flutter_test.dart';
import 'package:tcg_decks/games/game_definition.dart';
import 'package:tcg_decks/games/vanguard/vanguard_data.dart';
import 'package:tcg_decks/games/vanguard/vanguard_game.dart';
import 'package:tcg_decks/models/card_definition.dart';
import 'package:tcg_decks/models/deck.dart';

const game = VanguardGame();

var _seq = 0;

/// Fixture cards default to a card printed in both the D-series and the
/// V-series, which every format accepts, so that tests about deck size and
/// triggers are not also testing the card pool. Pass `series` to change it.
CardDefinition card(String name, Map<String, String> attributes) {
  _seq += 1;
  return CardDefinition(
    id: 'card-$_seq',
    gameId: 'vanguard',
    name: name,
    attributes: {'series': 'dv', ...attributes},
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
  );
}

/// A mutable slot so tests can tweak one line of a fixture deck.
class Slot {
  Slot(this.card, this.zoneId, this.quantity);

  CardDefinition card;
  String zoneId;
  int quantity;
}

DeckView viewOf(String formatId, List<Slot> slots) {
  final entries = [
    for (final slot in slots)
      DeckEntry(
        cardId: slot.card.id,
        zoneId: slot.zoneId,
        quantity: slot.quantity,
      ),
  ];
  final deck = Deck(
    id: 'deck-1',
    gameId: 'vanguard',
    formatId: formatId,
    name: 'Test deck',
    description: '',
    accent: 'ember',
    favorite: false,
    entries: entries,
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
  );
  return DeckView(
    deck: deck,
    format: game.format(formatId),
    items: [
      for (var i = 0; i < slots.length; i += 1)
        DeckItem(entries[i], slots[i].card),
    ],
  );
}

/// A legal 50 card main deck plus a legal ride deck.
List<Slot> legalStandardDeck() => [
  Slot(card('Ride G0', {'grade': '0', 'cardType': 'normal'}), zoneRide, 1),
  Slot(card('Ride G1', {'grade': '1', 'cardType': 'normal'}), zoneRide, 1),
  Slot(card('Ride G2', {'grade': '2', 'cardType': 'normal'}), zoneRide, 1),
  Slot(card('Ride G3', {'grade': '3', 'cardType': 'normal'}), zoneRide, 1),
  // 16 triggers
  Slot(
    card('Crit A', {
      'grade': '0',
      'cardType': 'trigger',
      'trigger': 'critical',
    }),
    zoneMain,
    4,
  ),
  Slot(
    card('Crit B', {
      'grade': '0',
      'cardType': 'trigger',
      'trigger': 'critical',
    }),
    zoneMain,
    4,
  ),
  Slot(
    card('Draw A', {'grade': '0', 'cardType': 'trigger', 'trigger': 'draw'}),
    zoneMain,
    4,
  ),
  Slot(
    card('Heal A', {'grade': '0', 'cardType': 'trigger', 'trigger': 'heal'}),
    zoneMain,
    4,
  ),
  // 4 sentinels
  Slot(
    card('Perfect Guard', {'grade': '1', 'cardType': 'sentinel'}),
    zoneMain,
    4,
  ),
  // 30 more bodies
  Slot(card('Grade 1 A', {'grade': '1', 'cardType': 'normal'}), zoneMain, 4),
  Slot(card('Grade 1 B', {'grade': '1', 'cardType': 'normal'}), zoneMain, 4),
  Slot(card('Grade 2 A', {'grade': '2', 'cardType': 'normal'}), zoneMain, 4),
  Slot(card('Grade 2 B', {'grade': '2', 'cardType': 'normal'}), zoneMain, 4),
  Slot(card('Grade 2 C', {'grade': '2', 'cardType': 'normal'}), zoneMain, 4),
  Slot(card('Grade 3 A', {'grade': '3', 'cardType': 'normal'}), zoneMain, 4),
  Slot(card('Grade 3 B', {'grade': '3', 'cardType': 'normal'}), zoneMain, 4),
  Slot(card('Grade 3 C', {'grade': '3', 'cardType': 'normal'}), zoneMain, 2),
];

Slot named(List<Slot> slots, String name) =>
    slots.firstWhere((slot) => slot.card.name == name);

List<String> errorsOf(DeckView view) => [
  for (final issue in game.validate(view))
    if (issue.level == IssueLevel.error) issue.message,
];

List<String> warningsOf(DeckView view) => [
  for (final issue in game.validate(view))
    if (issue.level == IssueLevel.warning) issue.message,
];

void main() {
  group('standard format', () {
    test('a legal deck reports no issues', () {
      final issues = game.validate(viewOf(formatStandard, legalStandardDeck()));
      expect(
        issues.map((i) => i.message),
        isEmpty,
        reason: 'unexpected issues on a legal deck',
      );
    });

    test('main deck must hold exactly 50 cards', () {
      final slots = legalStandardDeck();
      named(slots, 'Grade 3 C').quantity = 1; // 49 cards
      expect(
        errorsOf(viewOf(formatStandard, slots)),
        contains(contains('49 cards')),
      );
    });

    test('ride deck needs one of each grade 0 to 3', () {
      final slots = legalStandardDeck()
        ..removeWhere((slot) => slot.card.name == 'Ride G2');
      expect(
        errorsOf(viewOf(formatStandard, slots)),
        contains(contains('missing its grade 2')),
      );
    });

    test('a second card of one grade in the ride deck is illegal', () {
      final slots = legalStandardDeck();
      named(slots, 'Ride G2').card = card('Ride G3 again', {
        'grade': '3',
        'cardType': 'normal',
      });
      expect(
        errorsOf(viewOf(formatStandard, slots)),
        contains(contains('2 grade 3 cards')),
      );
    });

    test('trigger units cannot sit in the ride deck', () {
      final slots = legalStandardDeck();
      named(slots, 'Ride G0').card = card('Trigger Ride', {
        'grade': '0',
        'cardType': 'trigger',
        'trigger': 'critical',
      });
      expect(
        errorsOf(viewOf(formatStandard, slots)),
        contains(contains('cannot go in the ride deck')),
      );
    });

    test('the main deck must hold exactly 16 triggers', () {
      final slots = legalStandardDeck();
      named(slots, 'Draw A').quantity = 3;
      named(slots, 'Grade 2 A').quantity = 5; // keep the deck at 50
      expect(
        errorsOf(viewOf(formatStandard, slots)),
        contains(contains('15 trigger units')),
      );
    });

    test('more than four copies of a card name is illegal', () {
      final slots = legalStandardDeck();
      named(slots, 'Grade 2 A').quantity = 5;
      named(slots, 'Grade 3 C').quantity = 1;
      expect(
        errorsOf(viewOf(formatStandard, slots)),
        contains(contains('appears 5 times')),
      );
    });

    test('copies of a name are counted across the ride and main decks', () {
      final slots = legalStandardDeck();
      // "Grade 1 A" is already at 4 in the main deck.
      named(slots, 'Ride G1').card = card('Grade 1 A', {
        'grade': '1',
        'cardType': 'normal',
      });
      expect(
        errorsOf(viewOf(formatStandard, slots)),
        contains(contains('appears 5 times')),
      );
    });

    test('heal triggers are capped at four', () {
      final slots = legalStandardDeck();
      named(slots, 'Crit A').card = card('Heal B', {
        'grade': '0',
        'cardType': 'trigger',
        'trigger': 'heal',
      });
      expect(
        errorsOf(viewOf(formatStandard, slots)),
        contains(contains('8 heal triggers')),
      );
    });

    test('a crest put into play by an ability cannot be in a deck', () {
      final slots = legalStandardDeck();
      named(slots, 'Grade 3 C').card = card('Nightrose crest', {
        'cardType': 'crest',
        'effect': '[CONT]:You can perform [Stride], and cannot ride...',
      });
      expect(
        errorsOf(viewOf(formatStandard, slots)),
        contains(contains('put into play by an ability')),
      );
    });

    test('over triggers are capped at one', () {
      final slots = legalStandardDeck();
      final crit = named(slots, 'Crit B')
        ..card = card('Over Trigger', {
          'grade': '0',
          'cardType': 'trigger',
          'trigger': 'over',
        })
        ..quantity = 2;
      expect(crit.quantity, 2);
      named(slots, 'Grade 3 C').quantity = 4; // keep the deck at 50
      expect(
        errorsOf(viewOf(formatStandard, slots)),
        contains(contains('2 over triggers')),
      );
    });

    // The card data records that a card is a trigger unit but not which
    // trigger it is, so every card added from the database, and every imported
    // deck, arrives with the icon unset. Counting only cards whose icon was
    // known reported a legal sixteen trigger deck as having one.
    group('trigger units whose icon is not set', () {
      /// The legal deck with every trigger icon stripped, as the database and
      /// an import actually deliver them.
      List<Slot> withoutIcons() {
        final slots = legalStandardDeck();
        for (final name in ['Crit A', 'Crit B', 'Draw A', 'Heal A']) {
          final slot = named(slots, name);
          slot.card = card(name, {'grade': '0', 'cardType': 'trigger'});
        }
        return slots;
      }

      test('still count towards the sixteen', () {
        expect(
          errorsOf(viewOf(formatStandard, withoutIcons())),
          isNot(contains(contains('trigger units'))),
        );
      });

      test('a deck short of sixteen is still caught', () {
        final slots = withoutIcons();
        named(slots, 'Crit A').quantity = 3;
        named(slots, 'Grade 3 C').quantity = 5;
        expect(
          errorsOf(viewOf(formatStandard, slots)),
          contains(contains('15 trigger units')),
        );
      });

      test('the heal and over caps are declared unchecked', () {
        expect(
          warningsOf(viewOf(formatStandard, withoutIcons())),
          contains(contains('16 trigger units have no trigger set')),
        );
      });

      test('no such warning once every icon is set', () {
        expect(
          warningsOf(viewOf(formatStandard, legalStandardDeck())),
          isNot(contains(contains('no trigger set'))),
        );
      });

      test('one still reads as a unit rather than units', () {
        final slots = legalStandardDeck();
        named(slots, 'Heal A')
          ..card = card('Heal A', {'grade': '0', 'cardType': 'trigger'})
          ..quantity = 1;
        named(slots, 'Grade 3 C').quantity = 7;
        expect(
          warningsOf(viewOf(formatStandard, slots)),
          contains(contains('1 trigger unit has no trigger set')),
        );
      });

      test('cannot sit in the ride deck either', () {
        // This was missed too: a trigger unit with no icon was not recognised
        // as a trigger unit anywhere, the ride deck check included.
        final slots = legalStandardDeck();
        named(slots, 'Ride G0').card = card('Trigger In Ride', {
          'grade': '0',
          'cardType': 'trigger',
        });
        expect(
          errorsOf(viewOf(formatStandard, slots)),
          contains(contains('cannot go in the ride deck')),
        );
      });

      test('the breakdown counts them rather than losing them', () {
        final groups = game.stats(viewOf(formatStandard, withoutIcons()));
        final triggers = groups.firstWhere((g) => g.title == 'Triggers');
        expect(triggers.caption, '16 of 16');
        expect(
          triggers.bars.fold<int>(0, (sum, bar) => sum + bar.value),
          16,
          reason: 'the spread must not look complete while hiding cards',
        );
        expect(
          triggers.bars.firstWhere((bar) => bar.label == 'Not set').value,
          16,
        );
      });

      test('a heal cap is still enforced on the icons that are set', () {
        // A mixed deck: some icons answered, some not. The cap has to hold on
        // what is known instead of being abandoned because the rest is not.
        final slots = withoutIcons();
        named(slots, 'Heal A').card = card('Heal A', {
          'grade': '0',
          'cardType': 'trigger',
          'trigger': 'heal',
        });
        named(slots, 'Crit A').card = card('Heal B', {
          'grade': '0',
          'cardType': 'trigger',
          'trigger': 'heal',
        });
        expect(
          errorsOf(viewOf(formatStandard, slots)),
          contains(contains('8 heal triggers')),
        );
      });
    });

    test('a G unit in the main deck belongs in the G zone', () {
      final slots = legalStandardDeck()
        ..add(
          Slot(
            card('Some G Unit', {'grade': '4', 'cardType': 'g-unit'}),
            zoneMain,
            1,
          ),
        );
      expect(
        errorsOf(viewOf(formatStandard, slots)),
        contains(contains('belongs in the G zone')),
      );
    });

    test('a G zone is allowed, because stride came to Standard', () {
      // The Stride Decksets are D-series products, so a Standard deck can
      // stride and carry a G zone of its own.
      final slots = legalStandardDeck();
      for (var i = 0; i < 4; i += 1) {
        slots.add(
          Slot(
            card('G Unit $i', {'grade': '4', 'cardType': 'g-unit'}),
            zoneG,
            4,
          ),
        );
      }
      expect(errorsOf(viewOf(formatStandard, slots)), isEmpty);
    });

    test('a short G zone is not complained about', () {
      // Sixteen is a ceiling, not a requirement: a deck that strides on
      // twelve is a legal deck and nothing is said about it.
      final slots = legalStandardDeck();
      for (var i = 0; i < 3; i += 1) {
        slots.add(
          Slot(
            card('G Unit $i', {'grade': '4', 'cardType': 'g-unit'}),
            zoneG,
            4,
          ),
        );
      }
      final view = viewOf(formatStandard, slots);
      expect(errorsOf(view), isEmpty);
      expect(
        warningsOf(view).where((w) => w.contains('G zone')),
        isEmpty,
        reason: '12 of a possible 16 is a deck, not a problem',
      );
    });

    test('a deck with no G zone is still fine', () {
      expect(errorsOf(viewOf(formatStandard, legalStandardDeck())), isEmpty);
    });

    test('the G zone is still capped at sixteen', () {
      final slots = legalStandardDeck();
      for (var i = 0; i < 4; i += 1) {
        slots.add(
          Slot(
            card('G Unit $i', {'grade': '4', 'cardType': 'g-unit'}),
            zoneG,
            4,
          ),
        );
      }
      slots.add(
        Slot(
          card('G Unit extra', {'grade': '4', 'cardType': 'g-unit'}),
          zoneG,
          1,
        ),
      );
      expect(
        errorsOf(viewOf(formatStandard, slots)),
        contains(contains('17 cards')),
      );
    });

    test('a missing perfect guard is advice, not an error', () {
      final slots = legalStandardDeck();
      named(slots, 'Perfect Guard').card = card('Grade 1 C', {
        'grade': '1',
        'cardType': 'normal',
      });
      final issues = game.validate(viewOf(formatStandard, slots));
      expect(errorsOf(viewOf(formatStandard, slots)), isEmpty);
      expect(
        issues
            .where((i) => i.level == IssueLevel.warning)
            .map((i) => i.message),
        contains(contains('sentinels')),
      );
    });
  });

  group('premium format', () {
    List<Slot> premiumBase() =>
        legalStandardDeck()..removeWhere((slot) => slot.zoneId == zoneRide);

    test('rejects a non G unit in the G zone', () {
      final slots = premiumBase()
        ..add(
          Slot(
            card('Not A G Unit', {'grade': '3', 'cardType': 'normal'}),
            zoneG,
            1,
          ),
        );
      expect(
        errorsOf(viewOf(formatPremium, slots)),
        contains(contains('cannot go in the G zone')),
      );
    });

    test('allows sixteen G units', () {
      final slots = premiumBase();
      for (var i = 0; i < 4; i += 1) {
        slots.add(
          Slot(
            card('G Unit $i', {'grade': '4', 'cardType': 'g-unit'}),
            zoneG,
            4,
          ),
        );
      }
      expect(errorsOf(viewOf(formatPremium, slots)), isEmpty);
    });

    test('rejects a seventeenth G unit', () {
      final slots = premiumBase();
      for (var i = 0; i < 4; i += 1) {
        slots.add(
          Slot(
            card('G Unit $i', {'grade': '4', 'cardType': 'g-unit'}),
            zoneG,
            4,
          ),
        );
      }
      slots.add(
        Slot(
          card('G Unit extra', {'grade': '4', 'cardType': 'g-unit'}),
          zoneG,
          1,
        ),
      );
      expect(
        errorsOf(viewOf(formatPremium, slots)),
        contains(contains('17 cards')),
      );
    });

    test('needs a grade 0 in the main deck as the first vanguard', () {
      final slots = premiumBase()
        ..removeWhere((slot) => slot.card.attributes['grade'] == '0');
      expect(
        errorsOf(viewOf(formatPremium, slots)),
        contains(contains('first vanguard')),
      );
    });
  });

  group('the ride deck crest', () {
    // Divinez added a fifth, optional ride deck card. Its own text reads
    // "You may only have one ride deck crest in a ride deck", which caps it
    // at one rather than requiring one.
    Slot crest([String name = 'Energy Generator']) => Slot(
      card(name, {'cardType': 'ride-deck-crest', 'series': 'd'}),
      zoneRide,
      1,
    );

    test('a ride deck of four units and no crest is legal', () {
      expect(errorsOf(viewOf(formatStandard, legalStandardDeck())), isEmpty);
    });

    test('a ride deck of four units and one crest is legal', () {
      final slots = legalStandardDeck()..add(crest());
      expect(errorsOf(viewOf(formatStandard, slots)), isEmpty);
    });

    test('two crests are not allowed', () {
      final slots = legalStandardDeck()
        ..add(crest())
        ..add(crest('Another Crest'));
      expect(
        errorsOf(viewOf(formatStandard, slots)),
        contains(contains('2 ride deck crests')),
      );
    });

    test('a crest does not fill a ride deck grade slot', () {
      // Four units are still required alongside the crest.
      final slots = legalStandardDeck()
        ..removeWhere((slot) => slot.card.name == 'Ride G2')
        ..add(crest());
      final errors = errorsOf(viewOf(formatStandard, slots));
      expect(errors, contains(contains('missing its grade 2')));
      expect(errors, contains(contains('holds 3 units')));
    });

    test('a crest is not counted as a grade 0 unit', () {
      // The crest has no grade at all, so it must not collide with the ride
      // deck's grade 0.
      final slots = legalStandardDeck()..add(crest());
      expect(
        errorsOf(viewOf(formatStandard, slots)),
        isNot(contains(contains('grade 0 cards'))),
      );
    });

    test('a crest in the main deck belongs in the ride deck', () {
      final slots = legalStandardDeck()
        ..add(
          Slot(
            card('Energy Generator', {
              'cardType': 'ride-deck-crest',
              'series': 'd',
            }),
            zoneMain,
            1,
          ),
        );
      expect(
        errorsOf(viewOf(formatStandard, slots)),
        contains(contains('belongs in the ride deck')),
      );
    });

    test('the ride deck may hold five cards', () {
      expect(game.format(formatStandard).targets[zoneRide]?.max, 5);
    });
  });

  group('the card pool each format draws from', () {
    // Standard is the D-series format. It used to be described as taking
    // V-series cards too, which is what this group pins down.
    test('Standard rejects a V-series card', () {
      final slots = legalStandardDeck();
      named(slots, 'Grade 2 A').card = card('V Only Card', {
        'grade': '2',
        'cardType': 'normal',
        'series': 'v',
      });
      expect(
        errorsOf(viewOf(formatStandard, slots)),
        contains(contains('is not a Standard card')),
      );
    });

    test('Standard rejects an original series card', () {
      final slots = legalStandardDeck();
      named(slots, 'Grade 2 A').card = card('Very Old Card', {
        'grade': '2',
        'cardType': 'normal',
        'series': 'o',
      });
      expect(
        errorsOf(viewOf(formatStandard, slots)),
        contains(contains('is not a Standard card')),
      );
    });

    test('Standard accepts a card reprinted into the D-series', () {
      // An old card given a D-series printing is legal again, which is why
      // legality is tracked across every printing rather than the newest one.
      final slots = legalStandardDeck();
      named(slots, 'Grade 2 A').card = card('Reprinted Card', {
        'grade': '2',
        'cardType': 'normal',
        'series': 'dgov',
      });
      expect(errorsOf(viewOf(formatStandard, slots)), isEmpty);
    });

    test('the message says which eras the card is actually in', () {
      final slots = legalStandardDeck();
      named(slots, 'Grade 2 A').card = card('Old Card', {
        'grade': '2',
        'cardType': 'normal',
        'series': 'gv',
      });
      expect(
        errorsOf(viewOf(formatStandard, slots)),
        contains(contains('only in G-series and V-series')),
      );
    });

    test('V Premium rejects a D-series card', () {
      final slots = legalStandardDeck()
        ..removeWhere((slot) => slot.zoneId == zoneRide);
      named(slots, 'Grade 2 A').card = card('D Only Card', {
        'grade': '2',
        'cardType': 'normal',
        'series': 'd',
      });
      expect(
        errorsOf(viewOf(formatVPremium, slots)),
        contains(contains('is not a V Premium card')),
      );
    });

    test('Premium rejects a D-series card', () {
      final slots = legalStandardDeck()
        ..removeWhere((slot) => slot.zoneId == zoneRide);
      named(slots, 'Grade 2 A').card = card('D Only Card', {
        'grade': '2',
        'cardType': 'normal',
        'series': 'd',
      });
      expect(
        errorsOf(viewOf(formatPremium, slots)),
        contains(contains('is not a Premium card')),
      );
    });

    test('Premium accepts G-series and original series cards', () {
      final slots = legalStandardDeck()
        ..removeWhere((slot) => slot.zoneId == zoneRide);
      named(slots, 'Grade 2 A').card = card('G Era Card', {
        'grade': '2',
        'cardType': 'normal',
        'series': 'g',
      });
      named(slots, 'Grade 2 B').card = card('Original Card', {
        'grade': '2',
        'cardType': 'normal',
        'series': 'o',
      });
      expect(errorsOf(viewOf(formatPremium, slots)), isEmpty);
    });

    test('the casual format does not police the card pool', () {
      final slots = [
        Slot(
          card('Any Era', {'grade': '3', 'cardType': 'normal', 'series': 'o'}),
          zoneMain,
          1,
        ),
      ];
      expect(errorsOf(viewOf(formatCasual, slots)), isEmpty);
    });

    /// The legal deck with [count] of its main deck cards stripped of an era,
    /// as a card missing from the database or an undatable promo arrives.
    List<Slot> withUndated(int count) {
      final slots = legalStandardDeck();
      // In deck order, so the message lists them in the order the deck
      // screen shows them.
      const names = ['Grade 1 A', 'Grade 1 B', 'Grade 2 A', 'Grade 2 B'];
      for (var i = 0; i < count; i += 1) {
        named(slots, names[i]).card = CardDefinition(
          id: 'undated-$i',
          gameId: 'vanguard',
          name: 'Undated ${i + 1}',
          attributes: const {'grade': '2', 'cardType': 'normal'},
          createdAt: DateTime(2024),
          updatedAt: DateTime(2024),
        );
      }
      return slots;
    }

    /// A card the app can only place before the D-series: it knows the era is
    /// one of these, not that the card was printed in all of them.
    CardDefinition preDSeriesCard(String name) => CardDefinition(
      id: 'pre-d-$name',
      gameId: 'vanguard',
      name: name,
      attributes: const {
        'grade': '2',
        'cardType': 'normal',
        'possibleSeries': 'gopv',
      },
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    );

    group('a card known only to predate the D-series', () {
      test('is an error in Standard, which is D-series only', () {
        final slots = legalStandardDeck();
        named(slots, 'Grade 2 A').card = preDSeriesCard('Old Promo');
        expect(
          errorsOf(viewOf(formatStandard, slots)),
          contains(
            allOf(
              contains('"Old Promo" is not a Standard card'),
              contains('before the D-series'),
            ),
          ),
        );
      });

      test('passes Premium in silence, which takes every older era', () {
        final slots = legalStandardDeck()
          ..removeWhere((slot) => slot.zoneId == zoneRide);
        named(slots, 'Grade 2 A').card = preDSeriesCard('Old Promo');
        final view = viewOf(formatPremium, slots);
        expect(errorsOf(view), isEmpty);
        expect(
          warningsOf(view),
          isNot(contains(contains('Old Promo'))),
          reason: 'every era it could be from is in the pool',
        );
      });

      test('is a warning in V Premium, where the era would matter', () {
        // It could be a V-series card, or a G-series one. Saying either would
        // be a guess, so the app says it cannot tell.
        final slots = legalStandardDeck()
          ..removeWhere((slot) => slot.zoneId == zoneRide);
        for (final slot in slots) {
          slot.card = card(slot.card.name, {
            ...slot.card.attributes,
            'series': 'v',
          });
        }
        named(slots, 'Grade 2 A').card = preDSeriesCard('Old Promo');
        final view = viewOf(formatVPremium, slots);
        expect(errorsOf(view), isNot(contains(contains('Old Promo'))));
        expect(
          warningsOf(view),
          contains(
            allOf(contains('"Old Promo"'), contains('predates the D-series')),
          ),
        );
      });
    });

    test('an unchecked card is named, not just counted', () {
      // A bare count left no way to tell which cards were unchecked.
      expect(
        warningsOf(viewOf(formatStandard, withUndated(1))),
        contains(allOf(contains('"Undated 1"'), contains('it is from'))),
      );
    });

    test('two unchecked cards are both named', () {
      expect(
        warningsOf(viewOf(formatStandard, withUndated(2))),
        contains(
          allOf(
            contains('"Undated 1" and "Undated 2"'),
            contains('they are from'),
          ),
        ),
      );
    });

    test('three are named in a list', () {
      expect(
        warningsOf(viewOf(formatStandard, withUndated(3))),
        contains(contains('"Undated 1", "Undated 2" and "Undated 3"')),
      );
    });

    test('more than three name a few and count the rest', () {
      expect(
        warningsOf(viewOf(formatStandard, withUndated(4))),
        contains(contains('"Undated 1", "Undated 2" and 2 others')),
      );
    });

    test('the warning says why a card could not be dated', () {
      expect(
        warningsOf(viewOf(formatStandard, withUndated(1))),
        contains(
          allOf(contains('missing from the card database'), contains('promos')),
        ),
      );
    });

    test('a card of unknown era is a warning, never an error', () {
      final slots = legalStandardDeck();
      named(slots, 'Grade 2 A').card = CardDefinition(
        id: 'undated',
        gameId: 'vanguard',
        name: 'Undated Card',
        attributes: const {'grade': '2', 'cardType': 'normal'},
        createdAt: DateTime(2024),
        updatedAt: DateTime(2024),
      );
      final view = viewOf(formatStandard, slots);
      expect(errorsOf(view), isEmpty);
      expect(
        game.validate(view).map((i) => i.message),
        contains(contains('could not be checked')),
      );
    });
  });

  group('V Premium format', () {
    List<Slot> vPremiumBase() {
      final slots = legalStandardDeck()
        ..removeWhere((slot) => slot.zoneId == zoneRide);
      for (final slot in slots) {
        slot.card = card(slot.card.name, {
          ...slot.card.attributes,
          'series': 'v',
        });
      }
      return slots;
    }

    test('a V-series deck of fifty cards is legal', () {
      expect(errorsOf(viewOf(formatVPremium, vPremiumBase())), isEmpty);
    });

    test('G units are rejected, because V Premium has no stride', () {
      final slots = vPremiumBase()
        ..add(
          Slot(
            card('Some G Unit', {
              'grade': '4',
              'cardType': 'g-unit',
              'series': 'v',
            }),
            zoneMain,
            1,
          ),
        );
      expect(
        errorsOf(viewOf(formatVPremium, slots)),
        contains(contains('V Premium has no stride')),
      );
    });

    test('it needs a grade 0 for the first vanguard', () {
      final slots = vPremiumBase()
        ..removeWhere((slot) => slot.card.attributes['grade'] == '0');
      expect(
        errorsOf(viewOf(formatVPremium, slots)),
        contains(contains('first vanguard')),
      );
    });

    test('it uses no ride deck', () {
      final format = game.format(formatVPremium);
      expect(format.zoneIds, [zoneMain]);
      expect(format.name, 'V Premium');
    });
  });

  group('casual format', () {
    test('does not enforce deck size', () {
      final slots = [
        Slot(
          card('Just one card', {'grade': '3', 'cardType': 'normal'}),
          zoneMain,
          1,
        ),
      ];
      expect(errorsOf(viewOf(formatCasual, slots)), isEmpty);
    });
  });

  group('stats', () {
    test('the grade curve and trigger count cover the main deck', () {
      final groups = game.stats(viewOf(formatStandard, legalStandardDeck()));
      final curve = groups.firstWhere((g) => g.title == 'Grade curve');
      final triggers = groups.firstWhere((g) => g.title == 'Triggers');
      expect(curve.bars.fold<int>(0, (sum, bar) => sum + bar.value), 50);
      expect(triggers.bars.fold<int>(0, (sum, bar) => sum + bar.value), 16);
    });
  });

  group('presentation', () {
    test('a trigger badge shows the trigger, not the grade', () {
      final badge = game.badgeOf(
        card('Crit', {
          'grade': '0',
          'cardType': 'trigger',
          'trigger': 'critical',
        }),
      );
      expect(badge?.text, 'C');
      expect(
        game.badgeOf(card('Body', {'grade': '3', 'cardType': 'normal'}))?.text,
        'G3',
      );
    });

    test('cards sort by grade then trigger then name', () {
      final cards = [
        card('Zeta', {'grade': '3', 'cardType': 'normal'}),
        card('Alpha', {'grade': '1', 'cardType': 'normal'}),
        card('Beta', {'grade': '1', 'cardType': 'normal'}),
      ]..sort(game.compareCards);
      expect(cards.map((c) => c.name), ['Alpha', 'Beta', 'Zeta']);
    });
  });
}
