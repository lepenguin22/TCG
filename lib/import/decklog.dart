/// A client for Bushiroad's Deck Log, the official deck sharing site also
/// reached through Fighter Navigator.
///
/// A shared deck lives at `https://decklog-en.bushiroad.com/view/<CODE>`, or
/// on the Japanese site at `https://decklog.bushiroad.com/view/<CODE>`. The
/// page itself is a script driven app, but it is fed by a JSON endpoint that
/// takes the same code, and that is what this reads.
///
/// Both sites are supported. A Japanese deck's cards come back with Japanese
/// names, which the English card database cannot match -- but the two releases
/// of a set number their cards alike, so the number bridges them and the deck
/// arrives in English.
///
/// The network call is deliberately kept behind [DecklogFetcher] so that
/// everything interesting -- pulling a code out of whatever the user pasted,
/// reading the payload, and turning it into cards -- is testable without a
/// socket.
library;

import 'dart:convert';
import 'dart:io';

/// Deck Log runs one site per language. They share a layout and a deck code
/// space, but a code on one is not a code on the other.
const decklogEnHost = 'decklog-en.bushiroad.com';
const decklogJpHost = 'decklog.bushiroad.com';

const decklogViewUrl = 'https://$decklogEnHost/view/';

String decklogApiUrlOn(String host, String code) =>
    'https://$host/system/app/api/view/$code';

String decklogViewUrlOn(String host, String code) => 'https://$host/view/$code';

/// A deck code, and the site it came from.
class DecklogCode {
  const DecklogCode(this.code, {this.host});

  final String code;

  /// The site the link named, or null when a bare code was pasted: either
  /// site could hold it, so both are tried.
  final String? host;

  bool get isJapanese => host == decklogJpHost;

  List<String> get hosts =>
      host == null ? const [decklogEnHost, decklogJpHost] : [host!];

  @override
  String toString() => host == null ? code : '$code on $host';

  @override
  bool operator ==(Object other) =>
      other is DecklogCode && other.code == code && other.host == host;

  @override
  int get hashCode => Object.hash(code, host);
}

/// Deck Log's id for Cardfight!! Vanguard, used to reject a deck from one of
/// the other games it hosts.
const decklogVanguardTitleId = '1';

/// One card as Deck Log reports it.
class DecklogCard {
  const DecklogCard({
    required this.name,
    required this.quantity,
    this.cardNumber,
    this.trigger,
    this.image,
    required this.section,
  });

  final String name;
  final int quantity;

  /// The printed card number, when the payload carries one. It identifies a
  /// card far more reliably than its name.
  final String? cardNumber;

  /// Which trigger this is, when the payload says so: one of `critical`,
  /// `draw`, `front`, `heal`, `stand` or `over`.
  final String? trigger;

  /// The card's image, as the payload names it. Both of Deck Log's sites draw
  /// the same artwork from the same filename, so this identifies a card across
  /// the two languages even where nothing else does.
  final String? image;

  /// The payload key this card came from, kept verbatim.
  ///
  /// Deck Log serves every game it hosts through the same endpoint, so its
  /// sections are named `list`, `sub_list` and `p_list` rather than after what
  /// they hold. Which one is a Vanguard ride deck is not stated anywhere, so
  /// the key is carried through as an opaque label and the meaning is worked
  /// out later, from the cards themselves.
  final String section;
}

/// The sections Deck Log is known to use. Any other key holding cards is read
/// too, so a section we have not seen before is not silently dropped.
const decklogKnownSections = <String>['list', 'sub_list', 'p_list'];

class DecklogDeck {
  const DecklogDeck({
    required this.code,
    required this.gameTitleId,
    required this.cards,
    this.name,
  });

  final String code;
  final String gameTitleId;
  final String? name;
  final List<DecklogCard> cards;

  bool get isVanguard => gameTitleId == decklogVanguardTitleId;

  int get totalCards => cards.fold(0, (sum, card) => sum + card.quantity);
}

class DecklogException implements Exception {
  const DecklogException(this.message);

  final String message;

  @override
  String toString() => message;
}

final _decklogUrl = RegExp(
  r'(decklog(?:-en)?\.bushiroad\.com)/(?:[a-z-]+/)*view/([A-Za-z0-9]+)',
  caseSensitive: false,
);

/// Deck Log codes are short and alphanumeric.
final _decklogBareCode = RegExp(r'^[A-Za-z0-9]{3,16}$');

/// Pulls every deck code out of whatever the user pasted, in the order they
/// appear: a share link, several links, a link with text around it, or bare
/// codes one per line.
///
/// Duplicates are dropped, so pasting the same deck twice imports it once.
List<DecklogCode> decklogCodesFrom(String input) {
  final codes = <DecklogCode>[];
  final seen = <String>{};
  final seenCodes = <String>{};
  void add(String code, String? host) {
    final upper = code.toUpperCase();
    // A bare code adds nothing when the same code already arrived as a link:
    // the link says which site, and the bare one does not.
    if (host == null && seenCodes.contains(upper)) return;
    if (!seen.add('${host ?? '*'}|$upper')) return;
    seenCodes.add(upper);
    codes.add(DecklogCode(code, host: host));
  }

  // Links first. What they matched is then blanked out, so a link's own path
  // can never be read a second time as a bare code.
  final remainder = input.replaceAllMapped(_decklogUrl, (match) {
    add(match.group(2)!, match.group(1)!.toLowerCase());
    return ' ';
  });

  // A bare code has to stand alone on its line, or in a comma separated list
  // of them. Splitting on spaces as well would read "hello there" as two deck
  // codes -- ordinary words match the shape of a code, so only the lack of a
  // space around them tells the two apart.
  for (final line in remainder.split('\n')) {
    final parts = [
      for (final part in line.split(RegExp(r'[,;]')))
        if (part.trim().isNotEmpty) part.trim(),
    ];
    if (parts.isEmpty) continue;
    if (parts.every(_decklogBareCode.hasMatch)) {
      for (final part in parts) {
        add(part, null);
      }
    }
  }
  return codes;
}

/// The first deck code in what the user pasted, or null if there is none.
DecklogCode? decklogCodeFrom(String input) {
  final codes = decklogCodesFrom(input);
  return codes.isEmpty ? null : codes.first;
}

/// Reads a Deck Log API payload.
///
/// Throws [DecklogException] with a message worth showing when the body is not
/// a deck.
DecklogDeck parseDecklogPayload(String body, {required String code}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    throw const DecklogException(
      'Deck Log did not return a deck. The code may be wrong, or the deck may '
      'not be shared publicly.',
    );
  }
  if (decoded is! Map<String, dynamic>) {
    throw const DecklogException('Deck Log returned something unexpected.');
  }

  final cards = _readSections(decoded);

  if (cards.isEmpty) {
    throw const DecklogException('That Deck Log entry has no cards in it.');
  }

  final name = decoded['deck_name'] ?? decoded['title'] ?? decoded['name'];

  return DecklogDeck(
    code: code,
    gameTitleId: '${decoded['game_title_id'] ?? ''}',
    name: (name is String && name.trim().isNotEmpty) ? name.trim() : null,
    cards: cards,
  );
}

/// Reads every section of the payload that holds cards.
///
/// The known keys are read first so their order is stable; anything else that
/// turns out to be a list of cards is read after, because a deck arriving one
/// section short is worse than reading a key we did not expect.
List<DecklogCard> _readSections(Map<String, dynamic> decoded) {
  final keys = <String>{...decklogKnownSections, ...decoded.keys};
  return [for (final key in keys) ..._readList(decoded[key], key)];
}

List<DecklogCard> _readList(Object? raw, String section) {
  if (raw is! List) return const [];
  final cards = <DecklogCard>[];
  for (final entry in raw.whereType<Map<String, dynamic>>()) {
    final name = '${entry['name'] ?? ''}'.trim();
    final quantity = int.tryParse('${entry['num'] ?? ''}') ?? 0;
    if (name.isEmpty || quantity <= 0) continue;

    final number = '${entry['card_number'] ?? entry['cardno'] ?? ''}'.trim();
    final image =
        '${entry['img'] ?? entry['image'] ?? entry['image_url'] ?? ''}'.trim();
    cards.add(
      DecklogCard(
        name: name,
        quantity: quantity,
        cardNumber: number.isEmpty ? null : number,
        trigger: _triggerIn(entry),
        image: image.isEmpty ? null : image,
        section: section,
      ),
    );
  }
  return cards;
}

/// A value that names a trigger on its own, or as one part of a filename or
/// code, such as `heal` or `trigger_heal.png`.
final _triggerValue = RegExp(
  r'^(?:.*[_/-])?(critical|draw|front|heal|stand|over)(?:[._/-].*)?$',
  caseSensitive: false,
);

/// Looks for the card's trigger icon anywhere in its payload entry.
///
/// The card data the app ships records that a card is a trigger unit but not
/// which trigger, so the user is asked. Deck Log knows -- it draws the icons --
/// but which key carries it is not documented and the endpoint cannot be
/// reached from where this was written, so no key name is assumed.
///
/// Instead any short value that spells one of the six triggers is taken, and
/// everything else ignored. Guessing a key wrongly therefore costs nothing: an
/// unrecognised value yields no trigger at all, which is exactly where the app
/// stands without it. Only a value that can only be a trigger is believed.
String? _triggerIn(Map<String, dynamic> entry, {bool nested = false}) {
  for (final field in entry.entries) {
    // The name and the rules text are prose: "Draw" and "Critical" turn up in
    // both, meaning something else.
    if (const {'name', 'effect', 'ability', 'text'}.contains(field.key)) {
      continue;
    }
    final value = field.value;
    if (value is Map<String, dynamic> && !nested) {
      final found = _triggerIn(value, nested: true);
      if (found != null) return found;
      continue;
    }
    if (value is! String || value.isEmpty || value.length > 32) continue;
    final match = _triggerValue.firstMatch(value.trim());
    if (match != null) return match.group(1)!.toLowerCase();
  }
  return null;
}

/// Fetches the raw payload for a deck code.
typedef DecklogFetcher = Future<String> Function(DecklogCode code);

/// The real network call.
///
/// Deck Log's own page reaches this endpoint with same-origin headers, so they
/// are sent here too. It is tried as a POST first, which is what the site does,
/// and retried as a GET because some deployments answer that instead.
///
/// Each of the code's sites is tried in turn. A link says which one it came
/// from and only that one is asked; a bare code could belong to either, so the
/// English site is tried first and the Japanese one after.
Future<String> fetchDecklogPayload(DecklogCode code) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    ..userAgent = 'Mozilla/5.0 (Android) TCGDecks';

  try {
    for (final host in code.hosts) {
      for (final method in ['POST', 'GET']) {
        try {
          final request = await client.openUrl(
            method,
            Uri.parse(decklogApiUrlOn(host, code.code)),
          );
          request.headers
            ..set(HttpHeaders.acceptHeader, 'application/json, text/plain, */*')
            ..set(HttpHeaders.refererHeader, decklogViewUrlOn(host, code.code))
            ..set('Origin', 'https://$host')
            ..set('X-Requested-With', 'XMLHttpRequest');
          if (method == 'POST') {
            request.headers.contentType = ContentType(
              'application',
              'x-www-form-urlencoded',
            );
            request.write('');
          }

          final response = await request.close();
          final body = await response.transform(utf8.decoder).join();
          if (response.statusCode == 200 && body.trim().isNotEmpty) return body;
        } on HttpException {
          // Fall through and try the other method, then the other site.
        } on SocketException {
          // Same: one site being unreachable should not end the attempt.
        }
      }
    }
    throw const DecklogException(
      'Could not reach Deck Log. Check your connection, or paste the deck '
      'text instead.',
    );
  } finally {
    client.close();
  }
}

const _notADeckLogInput = DecklogException(
  'That is not a Deck Log link or code. Paste a link from either '
  'decklog-en.bushiroad.com or decklog.bushiroad.com, or just the code. '
  'Several links, one per line, import several decks.',
);

/// One deck's outcome in a batch: the deck, or why it could not be loaded.
///
/// A batch reports per deck rather than failing whole, so one dead code out of
/// six does not cost the other five.
class DecklogLoad {
  const DecklogLoad.loaded(this.deck) : code = null, error = null;
  const DecklogLoad.failed(this.code, this.error) : deck = null;

  final DecklogDeck? deck;
  final String? code;
  final String? error;
}

/// Loads a deck by code, URL, or a payload the user pasted themselves.
///
/// Pasting the payload is the escape hatch for when the request is refused:
/// the endpoint can be opened in a browser and its contents pasted in.
Future<DecklogDeck> loadDecklog(
  String input, {
  DecklogFetcher fetch = fetchDecklogPayload,
}) async {
  final text = input.trim();
  if (text.startsWith('{')) {
    return parseDecklogPayload(text, code: 'pasted');
  }

  final code = decklogCodeFrom(text);
  if (code == null) throw _notADeckLogInput;
  return parseDecklogPayload(await fetch(code), code: code.code);
}

/// Loads every deck named in what the user pasted, in order.
///
/// Decks are fetched one at a time rather than at once: Deck Log is somebody
/// else's server, and a paste of twenty links should not arrive as twenty
/// simultaneous requests.
Future<List<DecklogLoad>> loadDecklogBatch(
  String input, {
  DecklogFetcher fetch = fetchDecklogPayload,
}) async {
  final text = input.trim();
  if (text.startsWith('{')) {
    // A pasted payload is one deck by definition.
    return [DecklogLoad.loaded(parseDecklogPayload(text, code: 'pasted'))];
  }

  final codes = decklogCodesFrom(text);
  if (codes.isEmpty) throw _notADeckLogInput;

  final loads = <DecklogLoad>[];
  for (final code in codes) {
    try {
      loads.add(
        DecklogLoad.loaded(
          parseDecklogPayload(await fetch(code), code: code.code),
        ),
      );
    } on DecklogException catch (error) {
      loads.add(DecklogLoad.failed(code.code, error.message));
    }
  }
  return loads;
}
