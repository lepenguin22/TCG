import 'package:flutter_test/flutter_test.dart';
import 'package:tcg_decks/games/game_definition.dart';
import 'package:tcg_decks/games/vanguard/vanguard_data.dart';
import 'package:tcg_decks/games/vanguard/vanguard_game.dart';
import 'package:tcg_decks/models/card_definition.dart';
import 'package:tcg_decks/models/deck.dart';

const game = VanguardGame();

var _seq = 0;

CardDefinition card(String name, Map<String, String> attributes) {
  _seq += 1;
  return CardDefinition(
    id: 'card-$_seq',
    gameId: 'vanguard',
    name: name,
    attributes: attributes,
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

    test('G units are rejected', () {
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
        contains(contains('Premium only')),
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
