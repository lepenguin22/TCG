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
List<String> orderTokenNamesIn(Iterable<String> effects) =>
    _namesIn(_namedToken, effects);

List<String> _namesIn(RegExp pattern, Iterable<String> effects) {
  final names = <String>[];
  for (final effect in effects) {
    for (final match in pattern.allMatches(effect)) {
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
  final tokens = _onePerName(catalog.where(isOrderZoneToken));
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

// ------------------------------------------------------------------ markers

/// A marker an ability puts on a circle: "choose one of your (RC) without
/// any X-ceed NET markers, and put an X-ceed NET marker". It belongs to the
/// circle, not the unit, so it stays when the unit leaves.
bool isMarkerCard(CatalogCard card) => card.attributes['cardType'] == 'marker';

final _namedMarker = RegExp(
  r'put (?:a|an) "?([^,\[\]"]+?)"? marker',
  caseSensitive: false,
);

/// The markers [effects] put on a circle, by name, first named first.
List<String> markerNamesIn(Iterable<String> effects) =>
    _namesIn(_namedMarker, effects);

/// The markers the card database has, the ones [effects] name first.
List<CatalogCard> markerChoices(
  List<CatalogCard> catalog,
  Iterable<String> effects,
) {
  final named = [for (final n in markerNamesIn(effects)) n.toLowerCase()];
  final markers = catalog.where(isMarkerCard).toList();
  int rank(CatalogCard card) {
    final at = named.indexOf(card.name.toLowerCase());
    return at < 0 ? named.length : at;
  }

  markers.sort((a, b) {
    final byRank = rank(a).compareTo(rank(b));
    return byRank != 0 ? byRank : a.name.compareTo(b.name);
  });
  return markers;
}

/// A marker the card database has no card for, made from its name alone.
CardDefinition namedMarker(String name, String gameId) => CardDefinition(
  id: 'marker:${name.trim()}',
  gameId: gameId,
  name: name.trim(),
  attributes: const {'cardType': 'marker'},
  createdAt: DateTime.fromMillisecondsSinceEpoch(0),
  updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
);

/// A marker as a card to put on a circle, read off the card database.
CardDefinition markerFromCatalog(CatalogCard card, String gameId) =>
    CardDefinition(
      id: 'marker:${card.attributes['cardNo'] ?? card.name}',
      gameId: gameId,
      name: card.name,
      attributes: card.attributes,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

// -------------------------------------------------------------- token units

/// A token unit an ability calls to a circle: "call up to four Plant tokens
/// to (RC)". The card database files most as tokens; Shadow Army is filed as
/// a normal unit, and says what it is in its text.
bool isUnitTokenCard(CatalogCard card) =>
    card.attributes['cardType'] == 'token' ||
    (card.attributes['cardType'] == 'normal' &&
        (card.attributes['effect'] ?? '').contains(
          'token, and cannot be put in a deck',
        ));

final _calledToken = RegExp(
  r'call (?:up to )?(?:the same number of |a |an |one |two |three |four '
  r'|five |six )?"?([^,\[\]".()]+?)"? tokens? to',
  caseSensitive: false,
);

/// The token units [effects] call, by name, first named first.
List<String> unitTokenNamesIn(Iterable<String> effects) =>
    _namesIn(_calledToken, effects);

/// The token units the card database has, the ones [effects] call first.
List<CatalogCard> unitTokenChoices(
  List<CatalogCard> catalog,
  Iterable<String> effects,
) {
  final named = [for (final n in unitTokenNamesIn(effects)) n.toLowerCase()];
  final tokens = _onePerName(catalog.where(isUnitTokenCard));
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

/// A token unit as a card to call, read off the card database.
CardDefinition unitTokenFromCatalog(CatalogCard card, String gameId) =>
    CardDefinition(
      id: 'token:${card.attributes['cardNo'] ?? card.name}',
      gameId: gameId,
      name: card.name,
      attributes: {...card.attributes, 'token': 'true'},
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

/// A token unit the card database has no card for, made from its name and
/// whatever the calling card's reminder text says it is: "(Plant tokens are
/// grade 0/[Power] 5000/[Critical] 1 and have boost)", "(Shadow Army has
/// [Power] 15000 and Boost)".
CardDefinition namedUnitToken(
  String name,
  String gameId,
  Iterable<String> effects,
) {
  final escaped = RegExp.escape(name.trim());
  final graded = RegExp(
    '$escaped tokens? (?:are|is) grade (\\d+)\\s*/\\s*\\[Power\\]\\s*\\+?\\s*(\\d+)',
    caseSensitive: false,
  );
  final powered = RegExp(
    '$escaped (?:has|have) \\[Power\\]\\s*\\+?\\s*(\\d+)',
    caseSensitive: false,
  );
  String? grade;
  String? power;
  for (final effect in effects) {
    final g = graded.firstMatch(effect);
    if (g != null) {
      grade = g.group(1);
      power = g.group(2);
      break;
    }
    power ??= powered.firstMatch(effect)?.group(1);
  }
  return CardDefinition(
    id: 'token:${name.trim()}',
    gameId: gameId,
    name: name.trim(),
    attributes: {
      'cardType': 'token',
      'token': 'true',
      'grade': grade ?? '0',
      'power': ?power,
    },
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );
}

/// [namedToken] and [namedMarker] with the shape the picker asks for.
CardDefinition namedTokenFor(String name, String gameId, Iterable<String> _) =>
    namedToken(name, gameId);
CardDefinition namedMarkerFor(String name, String gameId, Iterable<String> _) =>
    namedMarker(name, gameId);

/// One card per name: a Plant or SYSTEM CODE: X-ceed is printed in several
/// sets, and the one printed most is the plain one -- a Plant "strengthened
/// and called by a special ability" at 10000 is the odd one out.
List<CatalogCard> _onePerName(Iterable<CatalogCard> cards) {
  final byName = <String, CatalogCard>{};
  for (final card in cards) {
    final key = card.name.toLowerCase();
    final held = byName[key];
    if (held == null || card.allNumbers.length > held.allNumbers.length) {
      byName[key] = card;
    }
  }
  return byName.values.toList();
}
