import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../games/card_catalog.dart';
import '../games/game_definition.dart';
import '../games/games.dart';
import '../models/card_definition.dart';
import '../models/deck.dart';

const _decksKey = 'tcgdecks.v1.decks';
const _cardsKey = 'tcgdecks.v1.cards';
const _backfillKey = 'tcgdecks.v1.backfill';

/// Bumped whenever the catalog starts carrying something worth filling into
/// cards that were saved before it existed. Cards entered before the catalog
/// shipped have no series, card text or image; without those the rules engine
/// cannot tell which format they belong to.
/// Bumped whenever the catalogue's derived data changes in a way saved cards
/// should pick up. Version 2 carries corrected eras and the new "known to
/// predate the D-series" answer.
const cardBackfillVersion = 2;

/// How many decks and cards an import brought in.
class ImportResult {
  const ImportResult(this.decks, this.cards);

  final int decks;
  final int cards;
}

/// Everything the app stores, held in memory and mirrored to shared
/// preferences. There is no account and no network call.
class DeckStore extends ChangeNotifier {
  SharedPreferences? _preferences;
  final _random = Random();

  bool _ready = false;
  List<Deck> _decks = [];
  List<CardDefinition> _cards = [];

  bool get ready => _ready;
  List<Deck> get decks => List.unmodifiable(_decks);
  List<CardDefinition> get cards => List.unmodifiable(_cards);

  Future<void> load() async {
    final preferences = _preferences ??= await SharedPreferences.getInstance();
    _decks = _decode(preferences.getString(_decksKey), Deck.fromJson);
    _cards = _decode(preferences.getString(_cardsKey), CardDefinition.fromJson);
    _ready = true;
    notifyListeners();
  }

  static List<T> _decode<T>(
    String? raw,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded.whereType<Map<String, dynamic>>().map(fromJson).toList();
    } on FormatException {
      return [];
    }
  }

  Future<void> _persistDecks() async {
    await _preferences?.setString(
      _decksKey,
      jsonEncode(_decks.map((deck) => deck.toJson()).toList()),
    );
  }

  Future<void> _persistCards() async {
    await _preferences?.setString(
      _cardsKey,
      jsonEncode(_cards.map((card) => card.toJson()).toList()),
    );
  }

  String _createId(String prefix) {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final suffix = _random.nextInt(1 << 32).toRadixString(36);
    return '${prefix}_$now$suffix';
  }

  Deck? deckById(String id) {
    for (final deck in _decks) {
      if (deck.id == id) return deck;
    }
    return null;
  }

  CardDefinition? cardById(String id) {
    for (final card in _cards) {
      if (card.id == id) return card;
    }
    return null;
  }

  List<CardDefinition> cardsForGame(String gameId) =>
      _cards.where((card) => card.gameId == gameId).toList();

  /// The deck paired with its resolved cards, ready for rules and stats.
  DeckView viewOf(Deck deck) {
    final game = gameById(deck.gameId);
    final byId = {for (final card in _cards) card.id: card};
    final items = <DeckItem>[];
    for (final entry in deck.entries) {
      final card = byId[entry.cardId];
      if (card != null) items.add(DeckItem(entry, card));
    }
    return DeckView(
      deck: deck,
      format: game.format(deck.formatId),
      items: items,
    );
  }

  Deck createDeck({
    required String name,
    String? gameId,
    String? formatId,
    String description = '',
    String accent = 'ember',
  }) {
    final resolvedGameId = gameId ?? defaultGameId;
    final now = DateTime.now();
    final deck = Deck(
      id: _createId('deck'),
      gameId: resolvedGameId,
      formatId: formatId ?? gameById(resolvedGameId).defaultFormatId,
      name: name.trim().isEmpty ? 'Untitled deck' : name.trim(),
      description: description.trim(),
      accent: accent,
      favorite: false,
      entries: const [],
      createdAt: now,
      updatedAt: now,
    );
    _decks = [deck, ..._decks];
    _save(decks: true);
    return deck;
  }

  void updateDeck(
    String deckId, {
    String? name,
    String? description,
    String? formatId,
    String? accent,
  }) {
    _replaceDeck(
      deckId,
      (deck) => deck.copyWith(
        name: name,
        description: description,
        formatId: formatId,
        accent: accent,
      ),
    );
  }

  void deleteDeck(String deckId) {
    _decks = _decks.where((deck) => deck.id != deckId).toList();
    _save(decks: true);
  }

  Deck? duplicateDeck(String deckId) {
    final source = deckById(deckId);
    if (source == null) return null;
    final now = DateTime.now();
    final copy = Deck(
      id: _createId('deck'),
      gameId: source.gameId,
      formatId: source.formatId,
      name: '${source.name} (copy)',
      description: source.description,
      accent: source.accent,
      favorite: false,
      entries: [...source.entries],
      createdAt: now,
      updatedAt: now,
    );
    _decks = [copy, ..._decks];
    _save(decks: true);
    return copy;
  }

  void toggleFavorite(String deckId) {
    final deck = deckById(deckId);
    if (deck == null) return;
    _replaceDeck(deckId, (d) => d.copyWith(favorite: !deck.favorite));
  }

  /// Creates a card, or replaces one when [id] names an existing card.
  CardDefinition saveCard({
    String? id,
    required String gameId,
    required String name,
    required Map<String, String> attributes,
  }) {
    final now = DateTime.now();
    if (id != null) {
      final existing = cardById(id);
      if (existing != null) {
        final updated = existing.copyWith(
          name: name.trim(),
          attributes: attributes,
          updatedAt: now,
        );
        _cards = [for (final card in _cards) card.id == id ? updated : card];
        _save(cards: true);
        return updated;
      }
    }
    final card = CardDefinition(
      id: _createId('card'),
      gameId: gameId,
      name: name.trim(),
      attributes: attributes,
      createdAt: now,
      updatedAt: now,
    );
    _cards = [card, ..._cards];
    _save(cards: true);
    return card;
  }

  /// Whether the library has yet to be filled in from the current catalog.
  bool get needsCardBackfill =>
      (_preferences?.getInt(_backfillKey) ?? 0) < cardBackfillVersion;

  /// Records that the backfill has run, so it never loads the catalog again
  /// just to find nothing to do. Cards the catalog does not know stay as they
  /// are, and would otherwise make the app retry on every launch.
  void markCardBackfillDone() {
    unawaited(
      _preferences?.setInt(_backfillKey, cardBackfillVersion) ?? Future.value(),
    );
  }

  /// Fills attributes the catalog knows into library cards that are missing
  /// them, matching on card number first and name second.
  ///
  /// Only blanks are filled. Anything already on the card wins, including a
  /// trigger you picked, a name you corrected and your own notes, so this can
  /// never undo an edit. Returns how many cards changed.
  int backfillFromCatalog({
    required String gameId,
    required List<CatalogCard> catalog,
  }) {
    final byNumber = <String, CatalogCard>{};
    final byName = <String, CatalogCard>{};
    for (final entry in catalog) {
      // Every printing, not just the one the catalogue shows: a card saved
      // under any other printing's number would otherwise match nothing here
      // and never be repaired.
      for (final printed in entry.allNumbers) {
        final number = printed.trim().toLowerCase();
        if (number.isNotEmpty) byNumber.putIfAbsent(number, () => entry);
      }
      byName.putIfAbsent(entry.lowerName, () => entry);
    }

    var changed = 0;
    final updated = <CardDefinition>[];
    for (final card in _cards) {
      final number = card.attributes['cardNo']?.trim().toLowerCase();
      CatalogCard? match;
      if (card.gameId == gameId) {
        match = (number != null && number.isNotEmpty) ? byNumber[number] : null;
        // Fall back to the name only when the card has no number of its own,
        // so a card identified by number is never matched to a different one.
        match ??= (number == null || number.isEmpty)
            ? byName[card.name.trim().toLowerCase()]
            : null;
      }
      if (match == null) {
        updated.add(card);
        continue;
      }

      final merged = Map<String, String>.from(match.attributes);
      for (final attribute in card.attributes.entries) {
        if (attribute.value.isNotEmpty) merged[attribute.key] = attribute.value;
      }
      // The era is worked out by the app rather than entered by hand, so the
      // catalogue's answer replaces what an older build wrote -- and removes
      // it when a card that used to be dated turns out not to be datable.
      for (final key in const ['series', 'possibleSeries']) {
        final value = match.attributes[key];
        if (value == null || value.isEmpty) {
          merged.remove(key);
        } else {
          merged[key] = value;
        }
      }
      // The artwork follows from the printing, not from hand entry either --
      // recomputed the same way an import would, so a card saved before
      // printings had their own images self-heals here.
      final image = match.imageFor(card.attributes['cardNo']?.trim());
      if (image == null || image.isEmpty) {
        merged.remove('imageUrl');
      } else {
        merged['imageUrl'] = image;
      }
      if (_sameAttributes(merged, card.attributes)) {
        updated.add(card);
        continue;
      }
      changed += 1;
      updated.add(card.copyWith(attributes: merged, updatedAt: card.updatedAt));
    }

    if (changed > 0) {
      _cards = updated;
      _save(cards: true);
    }
    return changed;
  }

  static bool _sameAttributes(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  /// The library card matching [cardNo], or [name] when there is no number.
  CardDefinition? findCard({
    required String gameId,
    String? cardNo,
    String? name,
  }) {
    final wantedNo = cardNo?.trim().toLowerCase();
    final wantedName = name?.trim().toLowerCase();
    for (final card in _cards) {
      if (card.gameId != gameId) continue;
      final cardNumber = card.attributes['cardNo']?.trim().toLowerCase();
      if (wantedNo != null && wantedNo.isNotEmpty && cardNumber == wantedNo) {
        return card;
      }
      if (wantedNo == null || wantedNo.isEmpty || cardNumber == null) {
        if (wantedName != null &&
            card.name.trim().toLowerCase() == wantedName) {
          return card;
        }
      }
    }
    return null;
  }

  /// Returns the library card for this printing, adding it to the library the
  /// first time it is used. Picking the same catalogue card twice reuses the
  /// one library entry, so edits to it apply everywhere.
  CardDefinition ensureCard({
    required String gameId,
    required String name,
    required Map<String, String> attributes,
  }) {
    final existing = findCard(
      gameId: gameId,
      cardNo: attributes['cardNo'],
      name: name,
    );
    if (existing != null) return existing;
    return saveCard(gameId: gameId, name: name, attributes: attributes);
  }

  /// Removes a card from the library and from every deck that used it.
  void deleteCard(String cardId) {
    _cards = _cards.where((card) => card.id != cardId).toList();
    _decks = [
      for (final deck in _decks)
        if (deck.entries.any((entry) => entry.cardId == cardId))
          deck.copyWith(
            entries: deck.entries
                .where((entry) => entry.cardId != cardId)
                .toList(),
          )
        else
          deck,
    ];
    _save(decks: true, cards: true);
  }

  void addToDeck(
    String deckId,
    String cardId,
    String zoneId, {
    int quantity = 1,
  }) {
    _replaceDeck(deckId, (deck) {
      final index = deck.entries.indexWhere(
        (entry) => entry.cardId == cardId && entry.zoneId == zoneId,
      );
      final entries = [...deck.entries];
      if (index >= 0) {
        entries[index] = entries[index].copyWith(
          quantity: entries[index].quantity + quantity,
        );
      } else {
        entries.add(
          DeckEntry(cardId: cardId, zoneId: zoneId, quantity: quantity),
        );
      }
      return deck.copyWith(entries: entries);
    });
  }

  void setQuantity(String deckId, String cardId, String zoneId, int quantity) {
    _replaceDeck(deckId, (deck) {
      if (quantity <= 0) {
        return deck.copyWith(
          entries: deck.entries
              .where(
                (entry) => !(entry.cardId == cardId && entry.zoneId == zoneId),
              )
              .toList(),
        );
      }
      final index = deck.entries.indexWhere(
        (entry) => entry.cardId == cardId && entry.zoneId == zoneId,
      );
      final entries = [...deck.entries];
      if (index >= 0) {
        entries[index] = entries[index].copyWith(quantity: quantity);
      } else {
        entries.add(
          DeckEntry(cardId: cardId, zoneId: zoneId, quantity: quantity),
        );
      }
      return deck.copyWith(entries: entries);
    });
  }

  void moveEntry(String deckId, String cardId, String fromZone, String toZone) {
    _replaceDeck(deckId, (deck) {
      DeckEntry? moving;
      for (final entry in deck.entries) {
        if (entry.cardId == cardId && entry.zoneId == fromZone) {
          moving = entry;
          break;
        }
      }
      if (moving == null) return deck;
      final entries = deck.entries
          .where(
            (entry) => !(entry.cardId == cardId && entry.zoneId == fromZone),
          )
          .toList();
      final index = entries.indexWhere(
        (entry) => entry.cardId == cardId && entry.zoneId == toZone,
      );
      if (index >= 0) {
        entries[index] = entries[index].copyWith(
          quantity: entries[index].quantity + moving.quantity,
        );
      } else {
        entries.add(moving.copyWith(zoneId: toZone));
      }
      return deck.copyWith(entries: entries);
    });
  }

  Map<String, dynamic> exportBackup() => {
    'app': 'tcg-decks',
    'version': 1,
    'exportedAt': DateTime.now().millisecondsSinceEpoch,
    'decks': _decks.map((deck) => deck.toJson()).toList(),
    'cards': _cards.map((card) => card.toJson()).toList(),
  };

  /// Adds anything in [payload] that this device does not already have.
  /// Existing decks and cards are never overwritten.
  ImportResult importBackup(Map<String, dynamic> payload) {
    final incomingDecks = (payload['decks'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(Deck.fromJson)
        .toList();
    final incomingCards = (payload['cards'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(CardDefinition.fromJson)
        .toList();

    final knownCards = _cards.map((card) => card.id).toSet();
    final knownDecks = _decks.map((deck) => deck.id).toSet();
    final newCards = incomingCards
        .where((card) => !knownCards.contains(card.id))
        .toList();
    final newDecks = incomingDecks
        .where((deck) => !knownDecks.contains(deck.id))
        .toList();

    _cards = [...newCards, ..._cards];
    _decks = [...newDecks, ..._decks];
    _save(decks: true, cards: true);
    return ImportResult(newDecks.length, newCards.length);
  }

  void resetAll() {
    _decks = [];
    _cards = [];
    _save(decks: true, cards: true);
  }

  void _replaceDeck(String deckId, Deck Function(Deck deck) update) {
    final index = _decks.indexWhere((deck) => deck.id == deckId);
    if (index < 0) return;
    final decks = [..._decks];
    decks[index] = update(decks[index]).copyWith(updatedAt: DateTime.now());
    _decks = decks;
    _save(decks: true);
  }

  void _save({bool decks = false, bool cards = false}) {
    if (decks) unawaited(_persistDecks());
    if (cards) unawaited(_persistCards());
    notifyListeners();
  }
}
