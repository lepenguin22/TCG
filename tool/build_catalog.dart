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

import 'package:tcg_decks/games/vanguard/vanguard_numbers.dart';

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
String? _seriesOf(
  String number, [
  String setName = '',
  String? nation,
  String format = '',
]) {
  // The official card list states the format outright, which beats every
  // inference below: a D-numbered set can be a collection of older cards for
  // Premium, and the card itself says so.
  switch (format) {
    case 'Standard':
      return 'd';
    case 'V Premium':
      return 'v';
    case 'Premium':
      return 'p';
  }

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

  // Everything the number alone can settle, shared with the app so an
  // imported card the database has never seen can be dated the same way.
  final fromNumber = seriesFromCardNumber(no);
  if (fromNumber != null) return fromNumber;

  // A "Standard" promo is the one case the number cannot settle by itself.
  // Which era it belongs to is decided by what the card is grouped under, not
  // by the year it was handed out: the D-series replaced clans with nations,
  // so a clan here is a V-series card. A year cutoff got this wrong for the
  // 2021 handover itself, dating two clan cards as D-series.
  if (RegExp(r'^[A-Z]+\d{4}\D*/VGS').hasMatch(no)) {
    return nation != null ? 'd' : 'v';
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

  // A promo from 2022 or later grouped under any modern nation is D-series:
  // the V-series was over by then, so the two names it shared with the
  // D-series are no longer ambiguous.
  // The year is anchored to the start of an event promo's number, as in
  // BSF2025/01B. A word boundary would not do: there is none between the "F"
  // and the "2".
  final year = RegExp(r'^[A-Z]+(20\d{2})').firstMatch(no);
  if (nation != null &&
      year != null &&
      (int.tryParse(year.group(1)!) ?? 0) >= 2022) {
    return 'd';
  }

  return null;
}

/// Whether a card type is a unit, and so must have a power.
bool _isUnit(String cardType) =>
    cardType == 'normal' || cardType == 'trigger' || cardType == 'g-unit';

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

/// Sets read from the official card list, which the mirror does not have.
Future<List<({String name, List<dynamic> cards})>> _readExtraSets() async {
  final file = File('data/cardlist/extra_sets.json');
  if (!file.existsSync()) return const [];
  final decoded = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  return [
    for (final entry in decoded.values.whereType<Map<String, dynamic>>())
      (
        name: entry['productName'] as String? ?? '',
        cards: entry['cards'] as List? ?? const [],
      ),
  ];
}

const _triggerNames = {'critical', 'draw', 'front', 'heal', 'stand', 'over'};

/// The trigger the card list printed, when the source carries one.
String? _triggerOf(Map<String, dynamic> raw) {
  final value = (raw['trigger'] as String? ?? '').trim().toLowerCase();
  return _triggerNames.contains(value) ? value : null;
}

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

  /// The trigger each card name has, gathered across every printing.
  ///
  /// A trigger belongs to the card, not to the printing, and only the official
  /// card list prints it -- so a card reprinted into a newer set arrives with
  /// its trigger there and without it in the mirror's older entry. Gathering
  /// by name means whichever printing knows it tells the others.
  final triggerByName = <String, String>{};

  /// Which eras each pre-D-series clan has been seen in. Used to work out
  /// which clans belong to the old game rather than to a D-series collab.
  final erasByClan = <String, Set<String>>{};

  /// Every card number a card has been printed under. Only one printing's
  /// number is shown, but a deck can name any of them, so all are kept for
  /// looking a card up.
  final numbersByCard = <String, Set<String>>{};

  /// The era of the printing currently held in [byName], used only to stop an
  /// older printing displacing a Standard legal one.
  final chosenSeries = <String, String?>{};

  var printings = 0;
  var skipped = 0;

  /// Every printing, read before any of them is aggregated: whether a badly
  /// read printing should stand on its own depends on what the rest of that
  /// card's printings look like.
  final records =
      <
        ({
          String name,
          String key,
          bool usable,
          String? series,
          String number,
          String? trigger,
          Map<String, Object?> entry,
        })
      >[];

  // The community mirror stopped scraping at DZ-BT09, so the sets after it are
  // read from the official card list by tool/scrape_cardlist.py and committed
  // here. Both are read; the mirror is a fixed record of everything older.
  final extra = await _readExtraSets();
  final sources = <({String name, List<dynamic> cards})>[
    for (final set in sets)
      if (set['cardsUrl'] != null)
        (
          name: set['name'] as String? ?? '',
          // Any failure here stops the run: a partial catalog that still exits
          // zero would look like a successful rebuild that dropped cards.
          cards: await _getJson(client, set['cardsUrl']! as String) as List,
        ),
    ...extra,
  ];
  stdout.writeln('${sets.length} mirrored sets, ${extra.length} from the site');

  for (var i = 0; i < sources.length; i += 1) {
    final setName = sources[i].name;
    final cards = sources[i].cards;

    for (final raw in cards.whereType<Map<String, dynamic>>()) {
      printings += 1;
      final name = (raw['name'] as String? ?? '').trim();
      final cardType = _cardTypes[raw['type']];
      // Tokens, markers and untyped rows are not deck cards.
      if (name.isEmpty || cardType == null) {
        skipped += 1;
        continue;
      }

      final number = raw['number'] as String? ?? '';
      final source = (raw['clan'] as String? ?? '').trim();
      final nation = _nations[source];
      final series = _seriesOf(
        number,
        setName,
        nation,
        raw['format'] as String? ?? '',
      );
      if (series != null &&
          nation == null &&
          source.isNotEmpty &&
          source != '-') {
        erasByClan.putIfAbsent(source, () => <String>{}).add(series);
      }

      final shield = _asInt(raw['shield']);
      final power = _asInt(raw['power']);
      final grade = _asInt(raw['grade']);
      final effect = (raw['effect'] as String? ?? '').trim();
      final image = raw['image_url'] as String? ?? '';

      // The source files sentinels under "Trigger Unit" alongside real
      // triggers. Counting one as a trigger would throw off the 16 trigger
      // rule, so the rules text decides instead of the source's card type.
      final isSentinel = effect.contains('[CONT]:Sentinel');
      final isOver = effect.contains('[Over] trigger') || shield == 50000;

      final type = isSentinel ? 'sentinel' : cardType;

      // A card is identified by its name AND its stats, not by its name alone.
      // Vanguard remakes a card under the same name with different numbers --
      // an 8000 power original and a 10000 power D-series version are two
      // cards, and "Flash Shield, Iseult" is a grade 0 trigger in one era and
      // a grade 1 normal unit in another. Keyed by name alone, one of them
      // silently stood in for the other everywhere it appeared.
      final key = [
        name.toLowerCase(),
        grade ?? '',
        power ?? '',
        shield ?? '',
        type,
      ].join('|');

      final trigger = cardType == 'trigger'
          ? (_triggerOf(raw) ?? (isOver ? 'over' : null))
          : null;

      final entry = <String, Object?>{
        'n': name,
        // A ride deck crest has no grade at all; everything else defaults to
        // zero when the source leaves it out.
        if (cardType != 'ride-deck-crest') 'g': grade ?? 0,
        't': type,
        // Stamped after every printing has been read, from triggerByName.
        'na': ?nation,
        if (nation == null && source.isNotEmpty && source != '-') 'c': source,
        'p': ?power,
        's': ?shield,
        if (number.isNotEmpty) 'no': number,
        if (effect.isNotEmpty) 'e': effect,
        if (image.startsWith(_imageBase))
          'i': image.substring(_imageBase.length),
      };

      records.add((
        name: name.toLowerCase(),
        key: key,
        // A unit with no power, or a power in single digits, is a row the
        // mirror misread: its status fields are positional, and one missing
        // or extra field shifts every value along. Such a printing must not
        // be allowed to invent a card of its own.
        usable: !_isUnit(cardType) || (power != null && power >= 1000),
        series: series,
        number: number,
        trigger: trigger,
        entry: entry,
      ));
    }

    if ((i + 1) % 40 == 0) {
      stdout.writeln(
        '  ${i + 1}/${sources.length} sets, ${byName.length} cards',
      );
    }
  }

  client.close();

  // A printing the mirror misread must not become a card of its own. Where the
  // same name has printings that were read properly, the bad one is folded
  // into the busiest of them; only where a name has nothing readable at all
  // does it stand alone, because 306 cards exist in no other printing.
  final usableKeys = <String, Map<String, int>>{};
  for (final record in records) {
    if (!record.usable) continue;
    final counts = usableKeys.putIfAbsent(record.name, () => <String, int>{});
    counts[record.key] = (counts[record.key] ?? 0) + 1;
  }
  String keyFor(
    ({
      String name,
      String key,
      bool usable,
      String? series,
      String number,
      String? trigger,
      Map<String, Object?> entry,
    })
    record,
  ) {
    if (record.usable) return record.key;
    final counts = usableKeys[record.name];
    if (counts == null || counts.isEmpty) return record.key;
    return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }

  var folded = 0;
  for (final record in records) {
    final key = keyFor(record);
    if (key != record.key) folded += 1;
    final series = record.series;
    if (series != null) {
      seriesByName.putIfAbsent(key, () => <String>{}).add(series);
    }
    if (record.trigger != null) {
      triggerByName.putIfAbsent(key, () => record.trigger!);
    }
    if (record.number.isNotEmpty) {
      numbersByCard.putIfAbsent(key, () => <String>{}).add(record.number);
    }
    // Later printings win, except that a D-series printing is never replaced
    // by an older one: that is the printing a Standard player owns, so it is
    // the number and the artwork worth showing. A misread printing never
    // displaces one that was read properly.
    if (byName[key] == null || (chosenSeries[key] != 'd' && record.usable)) {
      byName[key] = record.entry;
      chosenSeries[key] = series;
    }
  }
  stdout.writeln('$folded misread printings folded into a readable one');

  // A clan that only ever appears on D-series cards belongs to one of its
  // collaboration sets, not to the old game. Working the list out from the
  // data rather than naming the collabs means a new one needs no code change.
  const preD = {'v', 'g', 'o', 'p'};
  final legacyClans = {
    for (final entry in erasByClan.entries)
      if (entry.value.any(preD.contains) && !entry.value.contains('d'))
        entry.key,
  };

  // Stamp each card with every era it has been printed in.
  var unknownSeries = 0;
  var narrowedSeries = 0;
  for (final entry in byName.entries) {
    final eras = seriesByName[entry.key];
    if (eras == null || eras.isEmpty) {
      // The era is not known, but a clan can still rule the D-series out: the
      // D-series replaced clans with nations, and every clan it does use
      // belongs to a collab. So the card is from one of the older eras --
      // which one is still unknown, and 'sp' says exactly that.
      final clan = entry.value['c'];
      if (clan is String && legacyClans.contains(clan)) {
        entry.value['sp'] = (preD.toList()..sort()).join();
        narrowedSeries += 1;
      } else {
        unknownSeries += 1;
      }
      continue;
    }
    entry.value['sr'] = (eras.toList()..sort()).join();
  }

  // The official card list prints the trigger; the mirror never did, which is
  // why the app has to ask the user for it. Where any printing knows it, it is
  // kept and nobody has to be asked.
  var withTrigger = 0;
  for (final entry in byName.entries) {
    final trigger = triggerByName[entry.key];
    if (trigger == null || entry.value['t'] != 'trigger') continue;
    entry.value['tr'] = trigger;
    withTrigger += 1;
  }

  // The numbers of every other printing, so a deck naming one of them finds
  // the card. Without these a deck built from a reprint matched nothing by
  // number and fell back to matching by name, which is what put the wrong
  // card in front of the user.
  var withAlternates = 0;
  for (final entry in byName.entries) {
    final numbers = numbersByCard[entry.key] ?? const <String>{};
    final others = numbers.where((n) => n != entry.value['no']).toList()
      ..sort();
    if (others.isEmpty) continue;
    entry.value['no2'] = others;
    withAlternates += 1;
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
        'one letter per era the card was printed in, absent when unknown) '
        'sp=possible series (the same letters, but one of them rather than '
        'all: the era is unknown and these are what it could be) '
        'no2=the numbers of this card\'s other printings',
    'cards': catalog,
  };

  final file = File(_outputPath);
  await file.parent.create(recursive: true);
  await file.writeAsString(jsonEncode(payload));

  stdout
    ..writeln('')
    ..writeln(
      '$printings printings read, $skipped skipped (tokens, markers, untyped)',
    )
    ..writeln('${catalog.length} distinct cards written to $_outputPath')
    ..writeln('$unknownSeries of them could not be dated to an era')
    ..writeln('$narrowedSeries are known only to predate the D-series')
    ..writeln('$withTrigger trigger units know which trigger they are')
    ..writeln('$withAlternates carry the numbers of their other printings')
    ..writeln('${(await file.length() / 1024 / 1024).toStringAsFixed(2)} MB');
}
