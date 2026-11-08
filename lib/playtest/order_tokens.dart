/// Tokens that go into the order zone.
///
/// "Put a SYSTEM CODE: X-ceed token into your order zone": a card's ability
/// makes the token out of nothing, so it is in no deck -- its own text says
/// it "cannot be put in a deck" -- and the board has to be able to make one.
library;

import '../games/card_catalog.dart';
import '../models/card_definition.dart';

/// Whether [card] is a token that sits in the order zone: the card database
/// files them as set orders whose text says they represent a token.
bool isOrderZoneToken(CatalogCard card) =>
    card.attributes['cardType'] == 'order-set' &&
    (card.attributes['effect'] ?? '').contains('cannot be put in a deck');

/// Whether a card on the board is a token, from what it says about itself or
/// the mark a token made by name carries. A token leaving the order zone
/// does not go anywhere: it stops existing.
bool isTokenCard(CardDefinition card) =>
    card.attributes['token'] == 'true' ||
    (card.attributes['effect'] ?? '').contains('cannot be put in a deck');

final _namedToken = RegExp(
  r'put (?:a|an) "?([^,\[\]"]+?)"? token (?:into|in) (?:your|the) order zone',
  caseSensitive: false,
);

/// The tokens [effects] put into the order zone, by name, in the order they
/// are first named.
List<String> orderTokenNamesIn(Iterable<String> effects) {
  final names = <String>[];
  for (final effect in effects) {
    for (final match in _namedToken.allMatches(effect)) {
      final name = match.group(1)!.trim();
      if (!names.any((n) => n.toLowerCase() == name.toLowerCase())) {
        names.add(name);
      }
    }
  }
  return names;
}

/// A token as a card to put on the board, read off the card database.
CardDefinition tokenFromCatalog(CatalogCard card, String gameId) =>
    CardDefinition(
      id: 'token:${card.attributes['cardNo'] ?? card.name}',
      gameId: gameId,
      name: card.name,
      attributes: {...card.attributes, 'token': 'true'},
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

/// A token the card database has no card for, made from its name alone.
/// Its text is on the card that makes it, so the name is what matters.
CardDefinition namedToken(String name, String gameId) => CardDefinition(
  id: 'token:${name.trim()}',
  gameId: gameId,
  name: name.trim(),
  attributes: const {'cardType': 'order-set', 'token': 'true'},
  createdAt: DateTime.fromMillisecondsSinceEpoch(0),
  updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
);

/// The order zone tokens the card database has, the ones [effects] name
/// first.
List<CatalogCard> orderTokenChoices(
  List<CatalogCard> catalog,
  Iterable<String> effects,
) {
  final named = [
    for (final name in orderTokenNamesIn(effects)) name.toLowerCase(),
  ];
  final tokens = catalog.where(isOrderZoneToken).toList();
  int rank(CatalogCard card) {
    final at = named.indexOf(card.name.toLowerCase());
    return at < 0 ? named.length : at;
  }

  tokens.sort((a, b) {
    final byRank = rank(a).compareTo(rank(b));
    return byRank != 0 ? byRank : a.name.compareTo(b.name);
  });
  return tokens;
}
