// Regenerates the bundled Cardfight!! Vanguard card catalog.
//
//   dart run tool/build_catalog.dart
//
// Source data is the community "Card Game Simulator" dataset, which is scraped
// from Bushiroad's official card list. We take only the structured attributes
// the deck builder needs -- name, card number, grade, card type, nation or
// clan, power and shield -- and deliberately leave card effect text and images
// alone.
//
// The one attribute the source does not carry is the trigger icon (critical,
// draw, front, heal, stand). Over triggers and sentinels are recoverable from
// the rules text, and are recovered here; the rest is left blank for the app to
// ask about once, the first time a card is used.
//
// Card text and the official card image are included. Images are referenced by
// URL rather than bundled -- there are over twenty thousand of them -- so the
// app fetches and caches each one the first time it is shown.
import 'dart:convert';
import 'dart:io';

const _indexUrl =
    'https://raw.githubusercontent.com/dragogodev/cgs/master/Cardfight%20Vanguard/AllSets.json';

const _outputPath = 'assets/cards/vanguard.json';

/// Every image in the source sits under this prefix, so entries store only the
/// tail of the URL and the app puts them back together.
const _imageBase =
    'https://en.cf-vanguard.com/wordpress/wp-content/images/cardlist/';

/// Values the source's `clan` field uses for the six modern nations. Anything
/// else is a pre-D-series clan, which the app keeps as free text instead.
const _nations = <String, String>{
  'Dragon Empire': 'dragon-empire',
  'Dark States': 'dark-states',
  'Brandt Gate': 'brandt-gate',
  'Keter Sanctuary': 'keter-sanctuary',
  'Stoicheia': 'stoicheia',
  'Lyrical Monasterio': 'lyrical-monasterio',
};

/// Which era of the game a card was printed in, worked out from its card
/// number. This is what decides format legality: Standard takes D-series cards
/// only, V Premium takes V-series, and Premium takes everything older.
///
///   d  D-series and Divinez  (D-BT01, DZ-BT01)
///   v  V-series              (V-BT01)
///   g  G-series              (G-BT01)
///   o  the original series   (BT01, EB01, TD01)
///   p  a promo that is known to be pre-D-series but not which era
///
/// Returns null when the number says nothing, which is the case for most
/// promos. Those are usually resolved by another printing of the same card.
///
/// [setName] matters because the D- prefix is a printing era, not a format:
/// Bushiroad has published several D-branded collections of older cards for
/// V Premium and Premium. Their product names say so, and the card numbers
/// do not.
String? _seriesOf(String number, [String setName = '', String? nation]) {
  // These D-branded products are collections of older cards, and every card in
  // them carries a clan rather than one of the D-series nations. Note that the
  // Stride Decksets are NOT among them: those are D-series products that bring
  // stride into Standard, and their cards do carry nations.
  final product = setName.toLowerCase();
  if (product.contains('v clan collection')) return 'v';
  if (product.contains('p clan collection') ||
      product.contains('premium deckset') ||
      product.contains('history collection')) {
    return 'p';
  }

  final no = number.toUpperCase();
  if (RegExp(r'^DZ?-').hasMatch(no)) return 'd';
  if (no.startsWith('V-')) return 'v';
  if (no.startsWith('G-')) return 'g';
  if (RegExp(r'^(BT|EB|TD|FC|MT|SP)\d').hasMatch(no)) return 'o';

  // Event promos carry the format they were printed for in their number:
  // VGD is D-series, VGV is V Premium and VGP is Premium. VGS is "Standard",
  // which only came to mean D-series in 2021; before that it meant V-series.
  final promo = RegExp(r'^[A-Z]+(\d{4})\D*/VG([SVPD])').firstMatch(no);
  if (promo != null) {
    final year = int.tryParse(promo.group(1)!) ?? 0;
    switch (promo.group(2)) {
      case 'D':
        return 'd';
      case 'S':
        return year >= 2021 ? 'd' : 'v';
      case 'V':
        return 'v';
      case 'P':
        return 'p';
    }
  }

  // Last resort for a promo whose number says nothing: these four nations were
  // introduced with the D-series and have never appeared anywhere else, so a
  // card in one is a D-series card. Dragon Empire and Brandt Gate are left out
  // on purpose -- the V-series used those names too.
  const dSeriesOnlyNations = {
    'dark-states',
    'keter-sanctuary',
    'stoicheia',
    'lyrical-monasterio',
  };
  if (dSeriesOnlyNations.contains(nation)) return 'd';

  return null;
}

/// Source card type -> the app's `cardType` attribute.
const _cardTypes = <String, String>{
  'Normal Unit': 'normal',
  'Trigger Unit': 'trigger',
  'Trigger Order': 'trigger',
  'G Unit': 'g-unit',
  'Normal Order': 'order',
  'Blitz Order': 'order-blitz',
  'Set Order': 'order-set',
  'Ride Deck Crest': 'ride-deck-crest',
};

/// Fetches one JSON document, retrying a few times.
///
/// A dropped request used to be skipped with a warning, which quietly produced
/// a smaller catalog and still exited zero -- in the refresh workflow that
/// would open a pull request deleting cards. Now a set that cannot be read
/// fails the whole run.
Future<dynamic> _getJson(HttpClient client, String url) async {
  Object? lastError;
  for (var attempt = 1; attempt <= 3; attempt += 1) {
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode} for $url');
      }
      return jsonDecode(await response.transform(utf8.decoder).join());
    } on Exception catch (error) {
      lastError = error;
      if (attempt < 3) {
        stderr.writeln('  retrying ($attempt/3) after $error');
        await Future<void>.delayed(Duration(seconds: attempt * 2));
      }
    }
  }
  throw StateError('Could not read $url after 3 attempts: $lastError');
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value.replaceAll(',', ''));
  return null;
}

void main() async {
  final client = HttpClient()
    // Honour HTTPS_PROXY/NO_PROXY so this runs behind a corporate proxy too.
    ..findProxy = HttpClient.findProxyFromEnvironment
    ..connectionTimeout = const Duration(seconds: 60);

  stdout.writeln('Fetching set index…');
  final sets = (await _getJson(client, _indexUrl) as List)
      .whereType<Map<String, dynamic>>()
      .toList();
  stdout.writeln('${sets.length} sets');

  // Keep one entry per card name, since the four-copy rule counts names.
  final byName = <String, Map<String, Object?>>{};

  // Every era a name has ever been printed in, gathered across all its
  // printings. A card is legal in a format if ANY of its printings is, so a
  // V-series card later reprinted into the D-series is Standard legal, and
  // collecting the eras this way also settles most promos: the promo itself
  // says nothing, but another printing of the same card does.
  final seriesByName = <String, Set<String>>{};

  /// The era of the printing currently held in [byName], used only to stop an
  /// older printing displacing a Standard legal one.
  final chosenSeries = <String, String?>{};

  var printings = 0;
  var skipped = 0;

  for (var i = 0; i < sets.length; i += 1) {
    final set = sets[i];
    final cardsUrl = set['cardsUrl'] as String?;
    if (cardsUrl == null) continue;
    final setName = set['name'] as String? ?? '';

    // Any failure here stops the run: a partial catalog that still exits zero
    // would look like a successful rebuild that dropped cards.
    final cards = await _getJson(client, cardsUrl) as List;

    for (final raw in cards.whereType<Map<String, dynamic>>()) {
      printings += 1;
      final name = (raw['name'] as String? ?? '').trim();
      final cardType = _cardTypes[raw['type']];
      // Tokens, markers and untyped rows are not deck cards.
      if (name.isEmpty || cardType == null) {
        skipped += 1;
        continue;
      }

      final key = name.toLowerCase();
      final number = raw['number'] as String? ?? '';
      final source = (raw['clan'] as String? ?? '').trim();
      final nation = _nations[source];
      final series = _seriesOf(number, setName, nation);
      if (series != null) {
        seriesByName.putIfAbsent(key, () => <String>{}).add(series);
      }

      final shield = _asInt(raw['shield']);
      final effect = (raw['effect'] as String? ?? '').trim();
      final image = raw['image_url'] as String? ?? '';

      // The source files sentinels under "Trigger Unit" alongside real
      // triggers. Counting one as a trigger would throw off the 16 trigger
      // rule, so the rules text decides instead of the source's card type.
      final isSentinel = effect.contains('[CONT]:Sentinel');
      final isOver = effect.contains('[Over] trigger') || shield == 50000;

      final entry = <String, Object?>{
        'n': name,
        // A ride deck crest has no grade at all; everything else defaults to
        // zero when the source leaves it out.
        if (cardType != 'ride-deck-crest') 'g': _asInt(raw['grade']) ?? 0,
        't': isSentinel ? 'sentinel' : cardType,
        if (cardType == 'trigger' && isOver) 'tr': 'over',
        'na': ?nation,
        if (nation == null && source.isNotEmpty && source != '-') 'c': source,
        'p': ?_asInt(raw['power']),
        's': ?shield,
        if (number.isNotEmpty) 'no': number,
        if (effect.isNotEmpty) 'e': effect,
        if (image.startsWith(_imageBase))
          'i': image.substring(_imageBase.length),
      };

      // Later printings win, except that a D-series printing is never replaced
      // by an older one: it is the printing a Standard player owns, so it is
      // the number and artwork worth showing.
      // Later printings win, except that a D-series printing is never replaced
      // by an older one: that is the printing a Standard player owns, so it is
      // the number and the artwork worth showing.
      if (byName[key] == null || chosenSeries[key] != 'd') {
        byName[key] = entry;
        chosenSeries[key] = series;
      }
    }

    if ((i + 1) % 40 == 0) {
      stdout.writeln('  ${i + 1}/${sets.length} sets, ${byName.length} cards');
    }
  }

  client.close();

  // Stamp each card with every era it has been printed in.
  var unknownSeries = 0;
  for (final entry in byName.entries) {
    final eras = seriesByName[entry.key];
    if (eras == null || eras.isEmpty) {
      unknownSeries += 1;
      continue;
    }
    entry.value['sr'] = (eras.toList()..sort()).join();
  }

  final catalog = byName.values.toList()
    ..sort(
      (a, b) => (a['n']! as String).toLowerCase().compareTo(
        (b['n']! as String).toLowerCase(),
      ),
    );

  final payload = {
    'game': 'vanguard',
    'version': 1,
    'generatedAt': DateTime.now().toUtc().toIso8601String().split('T').first,
    'source':
        'https://github.com/dragogodev/cgs (scraped from en.cf-vanguard.com)',
    'imageBase': _imageBase,
    'fields':
        'n=name g=grade t=cardType tr=trigger na=nation c=clan p=power '
        's=shield no=cardNo e=effect i=image (relative to imageBase) '
        'sr=series (d=D-series v=V-series g=G-series o=original p=old promo; '
        'one letter per era the card was printed in, absent when unknown)',
    'cards': catalog,
  };

  final file = File(_outputPath);
  await file.parent.create(recursive: true);
  await file.writeAsString(jsonEncode(payload));

  stdout
    ..writeln('')
    ..writeln(
      '$printings printings read, $skipped skipped (tokens, crests, untyped)',
    )
    ..writeln('${catalog.length} distinct cards written to $_outputPath')
    ..writeln('$unknownSeries of them could not be dated to an era')
    ..writeln('${(await file.length() / 1024 / 1024).toStringAsFixed(2)} MB');
}
