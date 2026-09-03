import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tcg_decks/games/card_catalog.dart';
import 'package:tcg_decks/games/vanguard/vanguard_game.dart';

CatalogCard card(String name, Map<String, Object> extra) =>
    CatalogCard.fromJson({'n': name, ...extra});

void main() {
  group('parsing', () {
    test('short keys expand to the attribute names the game uses', () {
      final parsed = CatalogCard.fromJson({
        'n': 'Dragonic Overlord',
        'g': 3,
        't': 'normal',
        'na': 'dragon-empire',
        'p': 13000,
        'no': 'D-BT02/SP01EN',
      });

      expect(parsed.name, 'Dragonic Overlord');
      expect(parsed.attributes, {
        'grade': '3',
        'cardType': 'normal',
        'nation': 'dragon-empire',
        'power': '13000',
        'cardNo': 'D-BT02/SP01EN',
      });
      expect(parsed.cardNo, 'D-BT02/SP01EN');
    });

    test('unknown keys pass through, so another game can add attributes', () {
      final parsed = CatalogCard.fromJson({'n': 'Some Card', 'hp': 120});
      expect(parsed.attributes['hp'], '120');
    });

    test('the image prefix is put back on', () {
      final parsed = CatalogCard.fromJson({
        'n': 'Dragonic Overlord',
        'i': 'dbt02/dbt02_sp01.png',
      }, imageBase: 'https://example.test/cards/');
      expect(
        parsed.attributes['imageUrl'],
        'https://example.test/cards/dbt02/dbt02_sp01.png',
      );
    });

    test('card text comes through as the effect attribute', () {
      final parsed = CatalogCard.fromJson({
        'n': 'Some Card',
        'e': '[AUTO](VC):When this unit attacks, draw a card.',
      });
      expect(
        parsed.attributes['effect'],
        '[AUTO](VC):When this unit attacks, draw a card.',
      );
    });

    test('the image prefix is only applied to the image', () {
      final parsed = CatalogCard.fromJson({
        'n': 'Some Card',
        'no': 'D-BT01/001EN',
      }, imageBase: 'https://example.test/');
      expect(parsed.attributes['cardNo'], 'D-BT01/001EN');
    });

    test('a card with no number still searches by name', () {
      final parsed = CatalogCard.fromJson({'n': 'Nameless'});
      expect(parsed.searchText, 'nameless');
    });
  });

  group('search', () {
    final cards = [
      card('Blaster Blade', {'g': 2, 't': 'normal', 'no': 'DZ-SS08/Re45EN'}),
      card('Blaster Blade Seeker', {'g': 2, 't': 'normal'}),
      card('Sword Blaster Blade', {'g': 1, 't': 'normal'}),
      card('Dragonic Overlord', {'g': 3, 't': 'normal'}),
      card('Amulet Pure Eagle', {'g': 0, 't': 'trigger'}),
    ];

    test('an empty query with no filters returns nothing', () {
      expect(CardCatalog.search(cards, '   '), isEmpty);
    });

    test('multi-word names match, and exact beats prefix beats contains', () {
      final results = CardCatalog.search(cards, 'blaster blade');
      expect(results.map((c) => c.name), [
        'Blaster Blade', // exact
        'Blaster Blade Seeker', // prefix
        'Sword Blaster Blade', // word inside the name
      ]);
    });

    test('search is case insensitive', () {
      expect(
        CardCatalog.search(cards, 'DRAGONIC').single.name,
        'Dragonic Overlord',
      );
    });

    test('a card number finds its card', () {
      expect(
        CardCatalog.search(cards, 'DZ-SS08/Re45EN').single.name,
        'Blaster Blade',
      );
    });

    test('filters narrow the results', () {
      final results = CardCatalog.search(
        cards,
        'blaster',
        filters: {'grade': '1'},
      );
      expect(results.map((c) => c.name), ['Sword Blaster Blade']);
    });

    test('an empty filter value is ignored', () {
      final results = CardCatalog.search(
        cards,
        'dragonic',
        filters: {'grade': ''},
      );
      expect(results, hasLength(1));
    });

    test('a filter alone browses without a query', () {
      final results = CardCatalog.search(
        cards,
        '',
        filters: {'cardType': 'trigger'},
      );
      expect(results.map((c) => c.name), ['Amulet Pure Eagle']);
    });

    test('the result count is capped', () {
      final many = [
        for (var i = 0; i < 200; i += 1) card('Card $i', {'t': 'normal'}),
      ];
      expect(CardCatalog.search(many, 'card', limit: 25), hasLength(25));
    });
  });

  group('the bundled Vanguard catalog', () {
    // Reads the real generated asset off disk. Guards against shipping a
    // catalog that is missing, truncated, or has drifted from the schema the
    // app and the rules engine expect.
    late final List<CatalogCard> cards;

    setUpAll(() {
      const game = VanguardGame();
      final path = game.catalogAsset!;
      cards = parseCatalog(File(path).readAsStringSync());
    });

    test('is present and substantial', () {
      expect(cards.length, greaterThan(9000));
    });

    test('every entry has a name, grade and card type', () {
      for (final entry in cards) {
        expect(entry.name, isNotEmpty);
        expect(entry.attributes['cardType'], isNotNull, reason: entry.name);
        // Ride deck crests are the one card type with no grade.
        if (entry.attributes['cardType'] == 'ride-deck-crest') {
          expect(entry.attributes['grade'], isNull, reason: entry.name);
        } else {
          expect(entry.attributes['grade'], isNotNull, reason: entry.name);
        }
      }
    });

    test('card types are ones the rules engine understands', () {
      const known = {
        'normal',
        'trigger',
        'sentinel',
        'order',
        'order-blitz',
        'order-set',
        'g-unit',
        'ride-deck-crest',
        'token',
      };
      final seen = cards.map((c) => c.attributes['cardType']).toSet();
      expect(seen.difference(known), isEmpty);
    });

    test('nations are ones the rules engine understands', () {
      const known = {
        'dragon-empire',
        'dark-states',
        'brandt-gate',
        'keter-sanctuary',
        'stoicheia',
        'lyrical-monasterio',
      };
      final seen = cards
          .map((c) => c.attributes['nation'])
          .whereType<String>()
          .toSet();
      expect(seen.difference(known), isEmpty);
    });

    test('covers the modern D-series nations', () {
      for (final nation in [
        'dragon-empire',
        'dark-states',
        'brandt-gate',
        'keter-sanctuary',
        'stoicheia',
      ]) {
        final count = cards
            .where((c) => c.attributes['nation'] == nation)
            .length;
        expect(count, greaterThan(100), reason: nation);
      }
    });

    test('sentinels are typed as sentinels, not as triggers', () {
      // The source data files sentinels under "Trigger Unit"; miscounting them
      // would break the exactly-16-triggers rule.
      final iseult = cards.firstWhere((c) => c.name == 'Flash Shield, Iseult');
      expect(iseult.attributes['cardType'], 'sentinel');
      expect(iseult.attributes['trigger'], isNull);
      expect(
        cards.where((c) => c.attributes['cardType'] == 'sentinel').length,
        greaterThan(100),
      );
    });

    test('over triggers are marked, and only over triggers are', () {
      final over = cards.where((c) => c.attributes['trigger'] == 'over');
      expect(over, isNotEmpty);
      for (final entry in over) {
        expect(entry.attributes['cardType'], 'trigger', reason: entry.name);
      }
      // No other trigger icon is claimed, because the source cannot supply it.
      final triggers = cards
          .map((c) => c.attributes['trigger'])
          .whereType<String>()
          .toSet();
      expect(triggers, {'over'});
    });

    test('every card carries an image URL on the official host', () {
      for (final entry in cards) {
        final url = entry.attributes['imageUrl'];
        expect(url, isNotNull, reason: entry.name);
        expect(
          url,
          startsWith('https://en.cf-vanguard.com/'),
          reason: entry.name,
        );
        expect(
          url!.endsWith('.png') || url.endsWith('.jpg'),
          isTrue,
          reason: '$entry.name -> $url',
        );
      }
    });

    test('nearly every card carries its abilities', () {
      final withText = cards
          .where((c) => (c.attributes['effect'] ?? '').isNotEmpty)
          .length;
      // A handful of vanilla cards genuinely print no text.
      expect(withText / cards.length, greaterThan(0.99));
    });

    test('a known card has the abilities from its printing', () {
      final overlord = cards.firstWhere((c) => c.name == 'Dragonic Overlord');
      expect(overlord.attributes['effect'], contains('[AUTO](VC)'));
    });

    test('series letters are ones the rules engine understands', () {
      const known = {'d', 'v', 'g', 'o', 'p'};
      for (final entry in cards) {
        final series = entry.attributes['series'];
        if (series == null) continue;
        expect(series, isNotEmpty, reason: entry.name);
        expect(
          series.split('').toSet().difference(known),
          isEmpty,
          reason: '${entry.name} -> $series',
        );
      }
    });

    test('almost every card is dated to an era', () {
      final dated = cards
          .where((c) => (c.attributes['series'] ?? '').isNotEmpty)
          .length;
      expect(dated / cards.length, greaterThan(0.97));
    });

    test('every card is either dated or at least placed before the D-series', () {
      // Old PR promos carry no era in their number. Their clan still rules the
      // D-series out, which is enough to check them against Standard.
      final unplaced = cards
          .where(
            (c) =>
                (c.attributes['series'] ?? '').isEmpty &&
                (c.attributes['possibleSeries'] ?? '').isEmpty,
          )
          .toList();
      expect(
        unplaced.length,
        lessThan(5),
        reason: 'unplaced: ${unplaced.map((c) => c.name).take(10).toList()}',
      );
    });

    test('a narrowed era never claims the D-series', () {
      // The whole point of 'possibleSeries' is that the card predates it.
      for (final entry in cards) {
        final possible = entry.attributes['possibleSeries'];
        if (possible == null) continue;
        expect(possible, isNot(contains('d')), reason: entry.name);
        expect(entry.attributes['series'], isNull, reason: entry.name);
      }
    });

    test('a "Standard" promo carrying a clan is dated to the V-series', () {
      // The D-series replaced clans with nations, so a clan on a VGS promo is
      // a V-series card however recent the event was. A year cutoff got this
      // wrong for the 2021 handover.
      final gengan = cards.firstWhere(
        (c) => c.name == 'Stealth Dragon, Gengan',
      );
      expect(gengan.attributes['series'], isNot(contains('d')));
      expect(gengan.attributes['clan'], 'Nubatama');
    });

    test('the Standard pool is a real subset, not everything', () {
      final standard = cards
          .where((c) => (c.attributes['series'] ?? '').contains('d'))
          .length;
      // D-series is a few thousand cards out of a decade of printings. If this
      // ever swings to nearly all or nearly none, the era rules have broken.
      expect(standard, greaterThan(2000));
      expect(standard, lessThan(cards.length * 0.7));
    });

    test('cards printed only before the D-series are not Standard legal', () {
      // Blaster Blade Seeker was reprinted in the V Clan Collection, which is
      // a D-branded product for V Premium, not a Standard set.
      final seeker = cards.firstWhere((c) => c.name == 'Blaster Blade Seeker');
      expect(seeker.attributes['series'], isNot(contains('d')));

      // Flash Shield, Iseult's newest printing is a Premium Deckset.
      final iseult = cards.firstWhere((c) => c.name == 'Flash Shield, Iseult');
      expect(iseult.attributes['series'], isNot(contains('d')));
    });

    test('D-series cards are Standard legal', () {
      for (final name in [
        'Dragonic Overlord',
        'Blaster Blade',
        'Light Dragon Deity of Honors, Amartinoa',
      ]) {
        final entry = cards.firstWhere((c) => c.name == name);
        expect(entry.attributes['series'], contains('d'), reason: name);
      }
    });

    test('every card in a D-series-only nation is Standard legal', () {
      // These four nations exist only in the D-series, so a card in one must
      // be in the Standard pool. Dragon Empire and Brandt Gate are left out:
      // the V-series used those names too, so they prove nothing.
      //
      // This is the check that caught the Stride Decksets being mistaken for
      // Premium products.
      const nations = {
        'dark-states',
        'keter-sanctuary',
        'stoicheia',
        'lyrical-monasterio',
      };
      final wrong = cards
          .where((c) => nations.contains(c.attributes['nation']))
          .where((c) => !(c.attributes['series'] ?? '').contains('d'))
          .map((c) => '${c.name} (${c.attributes['cardNo']})')
          .toList();
      expect(wrong, isEmpty);
    });

    test('ride deck crests are in the catalog and are Divinez cards', () {
      final crests = cards
          .where((c) => c.attributes['cardType'] == 'ride-deck-crest')
          .toList();
      expect(crests, isNotEmpty);
      for (final crest in crests) {
        // The crest arrived with Divinez, so it is a D-series card, and it has
        // no grade to fill a ride deck slot with.
        expect(crest.attributes['series'], contains('d'), reason: crest.name);
        expect(crest.attributes['grade'], isNull, reason: crest.name);
      }
      expect(crests.map((c) => c.name), contains('Energy Generator'));
    });

    test('names are unique, so the four-copy rule counts correctly', () {
      final names = cards.map((c) => c.lowerName).toSet();
      expect(names.length, cards.length);
    });

    test('known cards resolve with the right attributes', () {
      final overlord = cards.firstWhere((c) => c.name == 'Dragonic Overlord');
      expect(overlord.attributes['grade'], '3');
      expect(overlord.attributes['nation'], 'dragon-empire');
      expect(overlord.attributes['cardType'], 'normal');
    });

    test('searching the real catalog finds a card by name', () {
      final results = CardCatalog.search(cards, 'dragonic overlord');
      expect(results.first.name, 'Dragonic Overlord');
    });

    test('the asset is valid JSON with the expected envelope', () {
      const game = VanguardGame();
      final json = jsonDecode(
        File(game.catalogAsset!).readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(json['game'], 'vanguard');
      expect(json['version'], 1);
      expect(json['source'], contains('cf-vanguard.com'));
    });
  });
}
