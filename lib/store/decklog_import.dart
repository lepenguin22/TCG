import '../games/card_catalog.dart';
import '../games/games.dart';
import '../games/vanguard/vanguard_data.dart';
import '../import/decklog.dart';
import '../models/deck.dart';
import 'deck_store.dart';

/// A card number reduced to what the Japanese and English printings share.
///
/// The two releases of a set number their cards identically apart from the EN
/// the English ones carry: `D-BT02/001` and `D-BT02/001EN` are the same card.
/// Dropping that marker is therefore the whole trick behind importing a deck
/// from the Japanese site and showing it in English -- the number bridges the
/// languages, where the name cannot.
String decklogNumberKey(String raw) =>
    raw.trim().toLowerCase().replaceFirst(RegExp(r'en(?=$|[^a-z0-9])'), '');

/// The same, with a printing's variant marker dropped too: the `-W` of an
/// alternate art, or the ` SGR` of a rarity. Two printings of one card can
/// share this key, so it is only ever used where it picks out a single card.
String decklogLooseNumberKey(String raw) =>
    decklogNumberKey(raw)
        .replaceFirst(RegExp(r'\s+\S+$'), '')
        .replaceFirst(RegExp(r'-[a-z]$'), '');

/// The trigger already on a catalogue card, if any. Only the over triggers
/// carry one, so this is nearly always blank.
String? attributesTriggerType(CatalogCard? match) =>
    match?.attributes['trigger'];

/// A ride deck is four units, one of each grade 0-3, plus at most one crest.
const _rideDeckLimit = 5;

/// What an import produced, so the user can be told what came across and what
/// did not rather than being handed a deck that quietly lost cards.
class DecklogImportResult {
  const DecklogImportResult({
    required this.deck,
    required this.matched,
    required this.cardsAdded,
    required this.unmatched,
    required this.zoneCounts,
    required this.rideDeckFound,
  });

  final Deck deck;

  /// Distinct cards found in the card database.
  final int matched;

  /// Total copies added across every zone.
  final int cardsAdded;

  /// Names of cards the database did not recognise. They are still added, from
  /// the name and count Deck Log gave, so the deck is never silently short.
  final List<String> unmatched;

  /// How many cards landed in each zone, so the import can show where the deck
  /// went instead of leaving the user to find out on the deck screen.
  final Map<String, int> zoneCounts;

  /// Whether a ride deck could be picked out of the payload's sections.
  final bool rideDeckFound;
}

/// The zone a card belongs in by virtue of what it is, whatever section of the
/// payload it arrived in. A G unit is only ever legal in the G zone and a ride
/// deck crest only in the ride deck, so neither needs the payload's help.
String? _zoneFromCard(CatalogCard? match) {
  final type = match?.attributes['cardType'];
  if (type == 'ride-deck-crest') return zoneRide;
  if (type == 'g-unit' || match?.attributes['grade'] == '4') return zoneG;
  return null;
}

/// Works out which section of the payload holds the ride deck.
///
/// Deck Log serves every game it hosts through one endpoint, and its sections
/// are named `list`, `sub_list` and `p_list` rather than after what they hold.
/// Nothing in the payload says which is a Vanguard ride deck, and reading the
/// names the wrong way round is exactly how ride decks ended up in the main
/// deck, so the names are not consulted at all.
///
/// The shape decides instead, and a ride deck is unmistakable: a handful of
/// cards, one copy of each, no two of the same grade and nothing above grade 3.
/// A fifty card main deck cannot be mistaken for that, and neither can a G
/// zone. Whichever section fits best is the ride deck.
String? _rideDeckSection(
  List<DecklogCard> cards,
  Map<DecklogCard, CatalogCard?> matches,
) {
  // Cards that place themselves say nothing about what their section is for.
  final sections = <String, List<DecklogCard>>{};
  for (final card in cards) {
    if (_zoneFromCard(matches[card]) != null) continue;
    sections.putIfAbsent(card.section, () => []).add(card);
  }

  // One section is a flat list of the whole deck. There is nothing to compare
  // it against, and peeling a ride deck out of it would be guesswork.
  if (sections.length < 2) return null;

  int total(List<DecklogCard> group) =>
      group.fold(0, (sum, card) => sum + card.quantity);

  // The largest section is the main deck, whatever it happens to be called.
  final mainSection = sections.entries
      .reduce((a, b) => total(b.value) > total(a.value) ? b : a)
      .key;

  String? best;
  var bestGrades = -1;
  for (final entry in sections.entries) {
    if (entry.key == mainSection) continue;
    final group = entry.value;
    if (total(group) > _rideDeckLimit) continue;
    if (group.any((card) => card.quantity != 1)) continue;

    // A card the database does not know raises no objection: an unreadable
    // grade is not evidence against, only the absence of evidence for.
    final grades = <int>{};
    var ruledOut = false;
    for (final card in group) {
      final grade = int.tryParse(matches[card]?.attributes['grade'] ?? '');
      if (grade == null) continue;
      if (grade > 3 || !grades.add(grade)) ruledOut = true;
    }
    if (ruledOut) continue;

    if (grades.length > bestGrades) {
      bestGrades = grades.length;
      best = entry.key;
    }
  }
  return best;
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
  // Built alongside a count, so a loose key shared by two printings is thrown
  // away rather than matching one of them arbitrarily.
  final byLooseNumber = <String, CatalogCard>{};
  final looseCounts = <String, int>{};
  for (final entry in entries) {
    final number = entry.cardNo?.trim();
    if (number != null && number.isNotEmpty) {
      byNumber.putIfAbsent(decklogNumberKey(number), () => entry);
      final loose = decklogLooseNumberKey(number);
      looseCounts[loose] = (looseCounts[loose] ?? 0) + 1;
      byLooseNumber.putIfAbsent(loose, () => entry);
    }
    byName.putIfAbsent(entry.lowerName, () => entry);
  }
  byLooseNumber.removeWhere((key, _) => (looseCounts[key] ?? 0) > 1);

  /// Number first and name second. For a Japanese deck the number is the only
  /// thing that can match at all, since the names arrive in Japanese.
  CatalogCard? lookUp(DecklogCard card) {
    final number = card.cardNumber?.trim();
    if (number != null && number.isNotEmpty) {
      final match =
          byNumber[decklogNumberKey(number)] ??
          byLooseNumber[decklogLooseNumberKey(number)];
      if (match != null) return match;
    }
    return byName[card.name.trim().toLowerCase()];
  }

  // Match everything first: the ride deck can only be picked out once the
  // grades are known.
  final matches = <DecklogCard, CatalogCard?>{
    for (final card in source.cards) card: lookUp(card),
  };
  final rideSection = _rideDeckSection(source.cards, matches);

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
  final zoneCounts = <String, int>{};

  for (final card in source.cards) {
    final match = matches[card];
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
      // The card database knows a card is a trigger unit but not which
      // trigger, so if Deck Log said, that answer is worth keeping -- it is
      // one the user would otherwise have to give by hand.
      if (card.trigger != null &&
          (attributesTriggerType(match) ?? '').isEmpty &&
          (match?.attributes['cardType'] ?? '') == 'trigger')
        'trigger': card.trigger!,
    };

    final libraryCard = store.ensureCard(
      gameId: gameId,
      name: match?.name ?? card.name,
      attributes: attributes,
    );
    final zone =
        _zoneFromCard(match) ??
        (card.section == rideSection ? zoneRide : zoneMain);
    store.addToDeck(deck.id, libraryCard.id, zone, quantity: card.quantity);
    cardsAdded += card.quantity;
    zoneCounts[zone] = (zoneCounts[zone] ?? 0) + card.quantity;
  }

  return DecklogImportResult(
    deck: store.deckById(deck.id) ?? deck,
    matched: matched,
    cardsAdded: cardsAdded,
    unmatched: unmatched,
    zoneCounts: zoneCounts,
    rideDeckFound: rideSection != null,
  );
}
