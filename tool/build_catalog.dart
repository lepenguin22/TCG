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

/// Source card type -> the app's `cardType` attribute.
const _cardTypes = <String, String>{
  'Normal Unit': 'normal',
  'Trigger Unit': 'trigger',
  'Trigger Order': 'trigger',
  'G Unit': 'g-unit',
  'Normal Order': 'order',
  'Blitz Order': 'order-blitz',
  'Set Order': 'order-set',
};

Future<dynamic> _getJson(HttpClient client, String url) async {
  final request = await client.getUrl(Uri.parse(url));
  final response = await request.close();
  if (response.statusCode != 200) {
    throw HttpException('HTTP ${response.statusCode} for $url');
  }
  return jsonDecode(await response.transform(utf8.decoder).join());
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

  // Keep one entry per card name. Later sets win, so a card carries its most
  // recent printing's number.
  final byName = <String, Map<String, Object?>>{};
  var printings = 0;
  var skipped = 0;

  for (var i = 0; i < sets.length; i += 1) {
    final set = sets[i];
    final cardsUrl = set['cardsUrl'] as String?;
    if (cardsUrl == null) continue;

    final List<dynamic> cards;
    try {
      cards = await _getJson(client, cardsUrl) as List;
    } on Exception catch (error) {
      stderr.writeln('  ! ${set['name']}: $error');
      continue;
    }

    for (final raw in cards.whereType<Map<String, dynamic>>()) {
      printings += 1;
      final name = (raw['name'] as String? ?? '').trim();
      final cardType = _cardTypes[raw['type']];
      // Tokens, markers, crests and untyped rows are not deck cards.
      if (name.isEmpty || cardType == null) {
        skipped += 1;
        continue;
      }

      final shield = _asInt(raw['shield']);
      final effect = (raw['effect'] as String? ?? '').trim();
      final image = raw['image_url'] as String? ?? '';

      // The source files sentinels under "Trigger Unit" alongside real
      // triggers. Counting one as a trigger would throw off the 16 trigger
      // rule, so the rules text decides instead of the source's card type.
      final isSentinel = effect.contains('[CONT]:Sentinel');
      final isOver = effect.contains('[Over] trigger') || shield == 50000;

      final source = (raw['clan'] as String? ?? '').trim();
      final nation = _nations[source];

      final entry = <String, Object?>{
        'n': name,
        'g': _asInt(raw['grade']) ?? 0,
        't': isSentinel ? 'sentinel' : cardType,
        if (cardType == 'trigger' && isOver) 'tr': 'over',
        'na': ?nation,
        if (nation == null && source.isNotEmpty && source != '-') 'c': source,
        'p': ?_asInt(raw['power']),
        's': ?shield,
        if ((raw['number'] as String? ?? '').isNotEmpty) 'no': raw['number'],
        if (effect.isNotEmpty) 'e': effect,
        if (image.startsWith(_imageBase))
          'i': image.substring(_imageBase.length),
      };

      byName[name.toLowerCase()] = entry;
    }

    if ((i + 1) % 40 == 0) {
      stdout.writeln('  ${i + 1}/${sets.length} sets, ${byName.length} cards');
    }
  }

  client.close();

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
        's=shield no=cardNo e=effect i=image (relative to imageBase)',
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
    ..writeln('${(await file.length() / 1024 / 1024).toStringAsFixed(2)} MB');
}
