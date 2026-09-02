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
        expect(entry.attributes['grade'], isNotNull, reason: entry.name);
        expect(entry.attributes['cardType'], isNotNull, reason: entry.name);
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
