import 'package:flutter_test/flutter_test.dart';
import 'package:tcg_decks/games/game_definition.dart';
import 'package:tcg_decks/games/vanguard/vanguard_data.dart';
import 'package:tcg_decks/models/card_definition.dart';
import 'package:tcg_decks/models/deck.dart';
import 'package:tcg_decks/utils/deck_cost.dart';

var _seq = 0;

DeckItem item(String? price, {int quantity = 1}) {
  _seq += 1;
  return DeckItem(
    DeckEntry(cardId: 'card-$_seq', zoneId: zoneMain, quantity: quantity),
    CardDefinition(
      id: 'card-$_seq',
      gameId: 'vanguard',
      name: 'Card $_seq',
      attributes: {'grade': '1', 'cardType': 'normal', 'price': ?price},
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
    ),
  );
}

DeckView viewOf(List<DeckItem> items) => DeckView(
  deck: Deck(
    id: 'deck',
    gameId: 'vanguard',
    formatId: formatStandard,
    name: 'Deck',
    description: '',
    accent: 'ember',
    favorite: false,
    entries: [for (final each in items) each.entry],
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
  ),
  format: vanguardFormats.first,
  items: items,
);

void main() {
  group('reading a price', () {
    test('a plain number is the price', () {
      expect(parsePrice('4.50'), 4.5);
    });

    test('the currency written around it is ignored', () {
      expect(parsePrice(r'$4.50'), 4.5);
      expect(parsePrice('RM 12'), 12);
      expect(parsePrice('12 SGD'), 12);
    });

    test('a comma before two digits is a decimal point', () {
      // Half of Europe writes it this way, and reading it as thousands would
      // turn four and a half into four hundred and fifty.
      expect(parsePrice('4,50'), 4.5);
    });

    test('a comma anywhere else separates thousands', () {
      expect(parsePrice('1,200'), 1200);
      expect(parsePrice('1,200.50'), 1200.5);
    });

    test('something with no number in it is not a price', () {
      expect(parsePrice('ask at the counter'), isNull);
      expect(parsePrice(''), isNull);
      expect(parsePrice(null), isNull);
    });

    test('the currency is whatever is written around the number', () {
      expect(currencyOf(r'$4.50'), r'$');
      expect(currencyOf('RM 12'), 'RM');
      expect(currencyOf('4.50'), '');
    });
  });

  group('what a deck costs', () {
    test('every copy counts, not every card', () {
      final cost = deckCostOf(
        viewOf([item('2.00', quantity: 4), item('0.50', quantity: 2)]),
      );
      expect(cost.total, 9);
      expect(cost.priced, 6);
      expect(cost.unpriced, 0);
    });

    test('cards with no price are counted, not guessed at', () {
      final cost = deckCostOf(
        viewOf([item('2.00', quantity: 2), item(null, quantity: 3)]),
      );
      expect(cost.total, 4);
      expect(cost.unpriced, 3, reason: 'copies, not distinct cards');
    });

    test('a deck nobody has priced has nothing to say', () {
      expect(deckCostOf(viewOf([item(null), item(null)])).isEmpty, isTrue);
    });

    test('the currency comes through when the prices agree', () {
      final cost = deckCostOf(viewOf([item(r'$2.00'), item(r'$1.50')]));
      expect(cost.currency, r'$');
      expect(cost.mixedCurrency, isFalse);
      expect(cost.label, r'$3.50');
    });

    test('a word sits off the number, a symbol against it', () {
      expect(deckCostOf(viewOf([item('RM 12')])).label, 'RM 12.00');
      expect(deckCostOf(viewOf([item('12')])).label, '12.00');
    });

    test('prices in two currencies are added but flagged', () {
      // Adding them is still the most useful thing to do -- the alternative
      // is no total at all -- but the number means nothing without saying so.
      final cost = deckCostOf(viewOf([item(r'$2.00'), item('RM 12')]));
      expect(cost.total, 14);
      expect(cost.mixedCurrency, isTrue);
      expect(cost.currency, isNull);
      expect(cost.label, '14.00');
    });

    test('a price with no currency does not count as disagreeing', () {
      final cost = deckCostOf(viewOf([item(r'$2.00'), item('1.50')]));
      expect(cost.mixedCurrency, isFalse);
      expect(cost.label, r'$3.50');
    });
  });
}
