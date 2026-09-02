import '../games/card_catalog.dart';
import '../games/games.dart';
import '../games/vanguard/vanguard_data.dart';
import '../import/decklog.dart';
import '../models/deck.dart';
import 'deck_store.dart';

/// What an import produced, so the user can be told what came across and what
/// did not rather than being handed a deck that quietly lost cards.
class DecklogImportResult {
  const DecklogImportResult({
    required this.deck,
    required this.matched,
    required this.cardsAdded,
    required this.unmatched,
  });

  final Deck deck;

  /// Distinct cards found in the card database.
  final int matched;

  /// Total copies added across every zone.
  final int cardsAdded;

  /// Names of cards the database did not recognise. They are still added, from
  /// the name and count Deck Log gave, so the deck is never silently short.
  final List<String> unmatched;
}

/// Which zone a Deck Log card belongs in.
///
/// Deck Log keeps its sections apart, so the list a card came from is evidence
/// rather than a guess. What the card *is* still wins where the two disagree: a
/// G unit can only live in the G zone and a ride deck crest only in the ride
/// deck, whichever list Deck Log filed them under.
String _zoneFor(DecklogCard card, CatalogCard? match) {
  final type = match?.attributes['cardType'];
  final grade = match?.attributes['grade'];
  if (type == 'ride-deck-crest') return zoneRide;
  if (type == 'g-unit' || grade == '4') return zoneG;
  return card.source == DecklogList.sub ? zoneRide : zoneMain;
}

/// Builds a deck in the library from a Deck Log payload.
///
/// Cards are matched to the bundled database by card number first and name
/// second, so an imported deck arrives with grades, triggers, abilities and
/// images already filled in and can be checked against the format rules.
Future<DecklogImportResult> importDecklogDeck(
  DeckStore store,
  CardCatalog catalog,
  DecklogDeck source, {
  String? name,
  String gameId = 'vanguard',
  String formatId = formatStandard,
}) async {
  final game = gameById(gameId);
  final asset = game.catalogAsset;
  final entries = asset == null
      ? const <CatalogCard>[]
      : await catalog.load(asset);

  final byNumber = <String, CatalogCard>{};
  final byName = <String, CatalogCard>{};
  for (final entry in entries) {
    final number = entry.cardNo?.trim().toLowerCase();
    if (number != null && number.isNotEmpty) {
      byNumber.putIfAbsent(number, () => entry);
    }
    byName.putIfAbsent(entry.lowerName, () => entry);
  }

  final deck = store.createDeck(
    name: name?.trim().isNotEmpty == true
        ? name!.trim()
        : (source.name ?? 'Deck Log ${source.code}'),
    gameId: gameId,
    formatId: formatId,
    description: 'Imported from Deck Log (${source.code}).',
  );

  var matched = 0;
  var cardsAdded = 0;
  final unmatched = <String>[];

  for (final card in source.cards) {
    final number = card.cardNumber?.trim().toLowerCase();
    final match =
        (number != null && number.isNotEmpty ? byNumber[number] : null) ??
        byName[card.name.trim().toLowerCase()];

    if (match != null) {
      matched += 1;
    } else {
      unmatched.add(card.name);
    }

    // An unmatched card still goes in, carrying whatever Deck Log knew, so the
    // deck has the right number of cards and can be corrected by hand.
    final attributes = <String, String>{
      ...?match?.attributes,
      if (card.cardNumber != null && match == null) 'cardNo': card.cardNumber!,
    };

    final libraryCard = store.ensureCard(
      gameId: gameId,
      name: match?.name ?? card.name,
      attributes: attributes,
    );
    store.addToDeck(
      deck.id,
      libraryCard.id,
      _zoneFor(card, match),
      quantity: card.quantity,
    );
    cardsAdded += card.quantity;
  }

  return DecklogImportResult(
    deck: store.deckById(deck.id) ?? deck,
    matched: matched,
    cardsAdded: cardsAdded,
    unmatched: unmatched,
  );
}
