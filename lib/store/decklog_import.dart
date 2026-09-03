import '../games/card_catalog.dart';
import '../games/games.dart';
import '../games/vanguard/vanguard_data.dart';
import '../games/vanguard/vanguard_numbers.dart';
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

/// The same, reduced further to the set and the printed number, with every
/// letter after the digits dropped.
///
/// This is what bridges a Japanese number to an English one. Where the English
/// printing carries EN, the Japanese one carries its rarity in the same place:
/// `DZ-SS14/001R` and `DZ-SS14/001EN` are the same card, and only stripping
/// both down to `dz-ss14/001` finds it. Variant markers go too -- the `-W` of
/// an alternate art, the ` SGR` of a rarity.
///
/// Two printings can share this key, so it is only ever used where it picks
/// out a single card.
String decklogLooseNumberKey(String raw) => raw
    .trim()
    .toLowerCase()
    .replaceFirst(RegExp(r'\s+\S+$'), '')
    .replaceFirst(RegExp(r'-[a-z]$'), '')
    .replaceFirstMapped(RegExp(r'^(.*\d)[a-z]+$'), (match) => match[1]!);

/// A card image reduced to what identifies the card: the filename, without its
/// folder, extension or the EN some English printings carry.
///
/// Both of Deck Log's sites draw the same artwork for a card from the same
/// filename, so this bridges the two languages even when nothing else does --
/// the image is the one field a Deck Log card row is known to always have.
String decklogImageKey(String raw) {
  final base = raw.trim().split('?').first.split('/').last.toLowerCase();
  return base
      .replaceFirst(RegExp(r'\.[a-z0-9]+$'), '')
      .replaceFirst(RegExp(r'en$'), '');
}

/// The number of the printing the deck actually names.
///
/// A card can have twenty printings and the database shows one of them, so a
/// deck naming any other one used to come out reading a number its owner had
/// never entered: the right card, under the wrong printing. Where the number
/// given matches one the card is known by, that printing's number is what the
/// deck records -- in the catalogue's own English form, so a Japanese deck
/// still reads as English.
String? printedNumberFor(CatalogCard match, String? given) {
  final asked = given?.trim() ?? '';
  if (asked.isEmpty) return null;
  final strict = decklogNumberKey(asked);
  for (final number in match.allNumbers) {
    if (decklogNumberKey(number) == strict) return number;
  }
  final loose = decklogLooseNumberKey(asked);
  for (final number in match.allNumbers) {
    if (decklogLooseNumberKey(number) == loose) return number;
  }
  // A printing the database has never seen. The deck still says what it says.
  return asked;
}

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

  /// Cards the database did not recognise, named as Deck Log gave them and
  /// followed by their card number where there is one. They are still added,
  /// so the deck is never silently short, and the number is what says why a
  /// card was missed -- a set the English release has not reached yet reads
  /// very differently from a number in a shape the app failed to handle.
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
    // A card the payload or the database has already placed says nothing
    // about what its section is for.
    if (_zoneFromCard(matches[card]) != null) continue;
    if (card.isRideDeck || card.isCrest) continue;
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
  var bestScore = 0;
  for (final entry in sections.entries) {
    if (entry.key == mainSection) continue;
    final score = _rideDeckScore(entry.value, matches);
    if (score > bestScore) {
      bestScore = score;
      best = entry.key;
    }
  }
  return best;
}

/// How much a section looks like a ride deck. Zero rules it out.
int _rideDeckScore(
  List<DecklogCard> group,
  Map<DecklogCard, CatalogCard?> matches,
) {
  final total = group.fold(0, (sum, card) => sum + card.quantity);
  if (total == 0 || total > _rideDeckLimit) return 0;
  if (group.any((card) => card.quantity != 1)) return 0;

  // A card the database does not know raises no objection: an unreadable
  // grade is not evidence against, only the absence of evidence for.
  final grades = <int>{};
  for (final card in group) {
    final grade = int.tryParse(
      matches[card]?.attributes['grade'] ?? card.grade ?? '',
    );
    if (grade == null) continue;
    if (grade > 3 || !grades.add(grade)) return 0;
  }

  // Known grades are the strongest evidence, and a full four or five cards
  // the next best. Size matters most for a deck imported from the Japanese
  // site, where a card the English database has never seen has no grade to
  // read: without it every candidate section used to tie, and the first one
  // encountered won -- which is not the same as the right one.
  return grades.length * 10 + (total == 4 || total == 5 ? 5 : 0) + total;
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
  final byImage = <String, CatalogCard>{};
  final imageCounts = <String, int>{};
  for (final entry in entries) {
    // Every printing's number, not just the one shown: a deck can name any of
    // them, and matching only the shown one sent the rest down to matching by
    // name, where a card sharing a name with a different one takes its place.
    for (final printed in entry.allNumbers) {
      final number = printed.trim();
      if (number.isEmpty) continue;
      byNumber.putIfAbsent(decklogNumberKey(number), () => entry);
      final loose = decklogLooseNumberKey(number);
      looseCounts[loose] = (looseCounts[loose] ?? 0) + 1;
      byLooseNumber.putIfAbsent(loose, () => entry);
    }
    final image = entry.attributes['imageUrl'];
    if (image != null && image.isNotEmpty) {
      final key = decklogImageKey(image);
      imageCounts[key] = (imageCounts[key] ?? 0) + 1;
      byImage.putIfAbsent(key, () => entry);
    }
    byName.putIfAbsent(entry.lowerName, () => entry);
  }
  byLooseNumber.removeWhere((key, _) => (looseCounts[key] ?? 0) > 1);
  byImage.removeWhere((key, _) => (imageCounts[key] ?? 0) > 1);

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
    // Then the image, which identifies a card even where the number is
    // written differently, or is not in the payload at all.
    final image = card.image;
    if (image != null && image.isNotEmpty) {
      final match = byImage[decklogImageKey(image)];
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
      final number = card.cardNumber?.trim() ?? '';
      unmatched.add(number.isEmpty ? card.name : '${card.name} ($number)');
    }

    // An unmatched card still goes in, carrying whatever Deck Log knew, so the
    // deck has the right number of cards and can be corrected by hand.
    final numberEra = match == null && card.cardNumber != null
        ? seriesFromCardNumber(card.cardNumber!)
        : null;
    // The printing the deck names, not the one the database happens to show
    // for this card -- its number and its artwork both follow from it.
    final printedNo = match == null
        ? card.cardNumber?.trim()
        : printedNumberFor(match, card.cardNumber);
    final attributes = <String, String>{
      ...?match?.attributes,
      'cardNo': ?printedNo,
      if (match != null) 'imageUrl': ?match.imageFor(printedNo),
      // A card the database has never seen still has a number, and the number
      // says which era it is from. Japanese sets run ahead of the English
      // ones, so an imported Japanese deck is full of these -- without this
      // every one of them reported that it could not be checked against the
      // format, which is not true when the number is right there.
      'series': ?numberEra,
      // The card database knows a card is a trigger unit but not which
      // trigger, so if Deck Log said, that answer is worth keeping -- it is
      // one the user would otherwise have to give by hand.
      if (card.trigger != null &&
          (attributesTriggerType(match) ?? '').isEmpty &&
          (match?.attributes['cardType'] ?? '') == 'trigger')
        'trigger': card.trigger!,
      // Deck Log carries a grade and a card type for every card, which is most
      // of what the rules need. For a card the database has never seen -- and
      // a Japanese deck is full of them -- it is the difference between a deck
      // that can be checked and one that cannot.
      if (match == null) ...{
        'grade': ?card.grade,
        if (card.isCrest) 'cardType': 'ride-deck-crest',
        if (card.isOver) ...{'cardType': 'trigger', 'trigger': 'over'},
      },
    };

    final libraryCard = store.ensureCard(
      gameId: gameId,
      name: match?.name ?? card.name,
      attributes: attributes,
    );
    // What the card is wins, then what Deck Log filed it as, and only then
    // the shape of the section it arrived in.
    final zone =
        _zoneFromCard(match) ??
        (card.isCrest || card.isRideDeck
            ? zoneRide
            : (card.section == rideSection ? zoneRide : zoneMain));
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
