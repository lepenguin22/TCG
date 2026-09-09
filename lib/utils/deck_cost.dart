import '../games/game_definition.dart';
import '../models/card_definition.dart';

/// What a deck costs to buy, worked out from the prices written on its cards.
///
/// Nothing here is fetched or looked up: a price is whatever the player last
/// wrote down, so this only adds up what is there and says plainly how much
/// of the deck it could not account for.
class DeckCost {
  const DeckCost({
    required this.total,
    required this.priced,
    required this.unpriced,
    required this.currency,
    required this.mixedCurrency,
  });

  /// The sum of price × copies, over the cards that carry a price.
  final double total;

  /// How many copies were counted, and how many were left out for having no
  /// price. Copies rather than distinct cards: three of a card you have not
  /// priced is three cards missing from the total.
  final int priced;
  final int unpriced;

  /// What the prices were written in -- "$", "RM", "" -- when they agree.
  /// Null when they do not, or when nothing carries one.
  final String? currency;

  /// Whether the deck's prices were written in more than one currency, which
  /// makes a single total a number the player has to interpret themselves.
  final bool mixedCurrency;

  bool get isEmpty => priced == 0;

  /// The total, with the currency the prices were written in.
  String get label {
    final amount = total.toStringAsFixed(2);
    final symbol = currency ?? '';
    if (symbol.isEmpty) return amount;
    // "$4.50" but "RM 4.50": a symbol sits against the number, a word does
    // not. Anything that is not a letter counts as a symbol.
    final joined = RegExp(r'[A-Za-z]$').hasMatch(symbol) ? '$symbol ' : symbol;
    return '$joined$amount';
  }
}

/// The number in a price, whatever is written around it.
///
/// A price is free text so it can be written in any currency, which means
/// "$4.50", "RM12" and "4,50" all have to give up their number. Anything with
/// no number in it at all is not a price.
double? parsePrice(String? price) {
  if (price == null) return null;
  final match = RegExp(r'\d[\d.,]*').firstMatch(price);
  if (match == null) return null;
  var digits = match.group(0)!;
  // A comma before the last two digits is a decimal point -- "4,50" is four
  // and a half in half of Europe -- and any other comma separates thousands.
  digits = RegExp(r',\d{2}$').hasMatch(digits)
      ? '${digits.substring(0, digits.length - 3)}.${digits.substring(digits.length - 2)}'
      : digits.replaceAll(',', '');
  return double.tryParse(digits.replaceAll(',', ''));
}

/// What is written around the number: the currency, as far as the app knows.
String currencyOf(String price) {
  final match = RegExp(r'\d[\d.,]*').firstMatch(price);
  if (match == null) return '';
  return (price.substring(0, match.start) + price.substring(match.end))
      .replaceAll(RegExp(r'\s+'), '')
      .trim();
}

/// Adds up a deck, copies and all.
DeckCost deckCostOf(DeckView view) {
  var total = 0.0;
  var priced = 0;
  var unpriced = 0;
  final currencies = <String>{};
  for (final item in view.items) {
    final price = parsePrice(item.card.attribute('price'));
    if (price == null) {
      unpriced += item.entry.quantity;
      continue;
    }
    total += price * item.entry.quantity;
    priced += item.entry.quantity;
    currencies.add(currencyOf(item.card.attribute('price')!));
  }
  final agreed = currencies.where((c) => c.isNotEmpty).toSet();
  return DeckCost(
    total: total,
    priced: priced,
    unpriced: unpriced,
    // One currency written on every price that names one, or none at all.
    currency: agreed.length == 1 ? agreed.first : null,
    mixedCurrency: agreed.length > 1,
  );
}

/// The price of one card, as the deck list shows it: what a copy costs and
/// where from. Either half stands on its own -- a price with no shop, or a
/// shop you have not priced yet -- and a card with neither says nothing.
String? buyingLine(CardDefinition card) {
  final parts = [?card.attribute('price'), ?card.attribute('store')];
  return parts.isEmpty ? null : parts.join(' · ');
}
