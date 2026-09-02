/// A client for Bushiroad's Deck Log, the official deck sharing site also
/// reached through Fighter Navigator.
///
/// A shared deck lives at `https://decklog-en.bushiroad.com/view/<CODE>`. The
/// page itself is a script driven app, but it is fed by a JSON endpoint that
/// takes the same code, and that is what this reads.
///
/// The network call is deliberately kept behind [DecklogFetcher] so that
/// everything interesting -- pulling a code out of whatever the user pasted,
/// reading the payload, and turning it into cards -- is testable without a
/// socket.
library;

import 'dart:convert';
import 'dart:io';

const decklogViewUrl = 'https://decklog-en.bushiroad.com/view/';
const decklogApiUrl = 'https://decklog-en.bushiroad.com/system/app/api/view/';

/// Deck Log's id for Cardfight!! Vanguard, used to reject a deck from one of
/// the other games it hosts.
const decklogVanguardTitleId = '1';

/// One card as Deck Log reports it.
class DecklogCard {
  const DecklogCard({
    required this.name,
    required this.quantity,
    this.cardNumber,
    required this.section,
  });

  final String name;
  final int quantity;

  /// The printed card number, when the payload carries one. It identifies a
  /// card far more reliably than its name.
  final String? cardNumber;

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

/// Pulls a deck code out of whatever the user pasted: a full URL, a URL with
/// tracking junk on the end, or the bare code from the share dialog.
String? decklogCodeFrom(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;

  final url = RegExp(
    r'decklog(?:-en)?\.bushiroad\.com/(?:[a-z-]+/)*view/([A-Za-z0-9]+)',
    caseSensitive: false,
  ).firstMatch(text);
  if (url != null) return url.group(1);

  // A bare code. Deck Log codes are short and alphanumeric; anything with a
  // slash or a space is something else the user pasted by mistake.
  if (RegExp(r'^[A-Za-z0-9]{3,16}$').hasMatch(text)) return text;

  return null;
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
    cards.add(
      DecklogCard(
        name: name,
        quantity: quantity,
        cardNumber: number.isEmpty ? null : number,
        section: section,
      ),
    );
  }
  return cards;
}

/// Fetches the raw payload for a deck code.
typedef DecklogFetcher = Future<String> Function(String code);

/// The real network call.
///
/// Deck Log's own page reaches this endpoint with same-origin headers, so they
/// are sent here too. It is tried as a POST first, which is what the site does,
/// and retried as a GET because some deployments answer that instead.
Future<String> fetchDecklogPayload(String code) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    ..userAgent = 'Mozilla/5.0 (Android) TCGDecks';

  try {
    for (final method in ['POST', 'GET']) {
      try {
        final request = await client.openUrl(
          method,
          Uri.parse('$decklogApiUrl$code'),
        );
        request.headers
          ..set(HttpHeaders.acceptHeader, 'application/json, text/plain, */*')
          ..set(HttpHeaders.refererHeader, '$decklogViewUrl$code')
          ..set('Origin', 'https://decklog-en.bushiroad.com')
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
        // Fall through and try the other method.
      }
    }
    throw const DecklogException(
      'Could not reach Deck Log. Check your connection, or paste the deck '
      'text instead.',
    );
  } on SocketException {
    throw const DecklogException(
      'Could not reach Deck Log. Check your connection, or paste the deck '
      'text instead.',
    );
  } finally {
    client.close();
  }
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
  if (code == null) {
    throw const DecklogException(
      'That is not a Deck Log link or code. Paste a link like '
      'decklog-en.bushiroad.com/view/ABC123, or just the code.',
    );
  }
  return parseDecklogPayload(await fetch(code), code: code);
}
