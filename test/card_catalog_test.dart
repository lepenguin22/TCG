import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tcg_decks/games/card_catalog.dart';
import 'package:tcg_decks/store/decklog_import.dart';
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
        'crest',
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

    test('a G unit with "15000+" power is its own card', () {
      // The plus is the card saying its power grows. Read as no power at all,
      // the printing looked misread, and a misread printing is folded into
      // another of the same name -- which put a G-era card's rules text on
      // the D-format stride unit that replaced it.
      final dragut = cards.firstWhere(
        (c) => (c.attributes['cardNo'] ?? '').startsWith('DZ-BT15/016'),
      );
      expect(dragut.name, 'Pirate King of Redemption, Dragut');
      expect(dragut.attributes['power'], '15000');
      expect(
        dragut.attributes['effect'],
        contains('turn a card with the same card name as this unit'),
        reason: 'its own text, not the G-CHB03 printing\'s',
      );
      expect(
        dragut.attributes['effect'],
        isNot(contains('Generation Break 2')),
        reason: 'that clause belongs to the older card of the same name',
      );
      expect(
        dragut.allNumbers.any((n) => n.startsWith('G-CHB03')),
        isFalse,
        reason: 'the G-era card is a different card, not another printing',
      );

      // And the older one is still there, with its own text.
      final older = cards.firstWhere(
        (c) =>
            c.name == 'Pirate King of Redemption, Dragut' &&
            (c.attributes['cardNo'] ?? '').startsWith('G-CHB03'),
      );
      expect(older.attributes['effect'], contains('Generation Break 2'));
    });

    test('no G-era card claims a D-format reprint as its own printing', () {
      // The same fold, measured across the catalogue rather than on one card.
      // A D-format reprint of a G unit is a rewritten card, so a G-series
      // entry listing a DZ number among its printings is one of these folds:
      // there were four before the builder learned to read "15000+".
      final folded = cards.where(
        (c) =>
            c.attributes['cardType'] == 'g-unit' &&
            (c.attributes['cardNo'] ?? '').startsWith('G-') &&
            c.allNumbers.any((n) => n.startsWith('DZ-')),
      );
      expect(folded, isEmpty, reason: folded.map((c) => c.name).join(', '));
    });

    test('the stats the card list prints wrongly are corrected', () {
      // Bushiroad's own pages give a power the card has not got on a run of
      // DZ-BT15 printings -- 5000 on a 8000 power booster, a power at all on
      // an order. Re-reading the site cannot fix that, so the corrections are
      // kept in a file and applied when the catalogue is built; this is the
      // check that they survived the build.
      final errata = jsonDecode(
        File('data/cardlist/errata.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final fixes = errata['cards'] as Map<String, dynamic>;
      expect(fixes, isNotEmpty);
      for (final fix in fixes.entries) {
        final number = fix.key.toUpperCase();
        final card = cards.firstWhere(
          (c) => c.allNumbers.any((n) => n.toUpperCase() == number),
          orElse: () => throw StateError('$number is in no card'),
        );
        final want = (fix.value as Map<String, dynamic>)['power'] as String;
        expect(card.attributes['power'] ?? '', want, reason: number);
      }
    });

    test('the powers a player read off their own cards are what the app '
        'shows', () {
      // Reported from the cards themselves, and the ones with no other
      // printing in the set to check against.
      const printed = {
        'DZ-BT15/029EN': '8000',
        'DZ-BT15/052EN': '8000',
        'DZ-BT15/080EN': '10000',
        'DZ-BT15/081EN': '10000',
        'DZ-BT15/084EN': '8000',
      };
      for (final entry in printed.entries) {
        final card = cards.firstWhere(
          (c) => c.allNumbers.contains(entry.key),
          orElse: () => throw StateError('${entry.key} is in no card'),
        );
        expect(card.attributes['power'], entry.value, reason: entry.key);
      }
    });

    test('two printings of one DZ-BT15 card agree on its power', () {
      // The alternate-art printing of a card in the same set is the same
      // card, so a disagreement is one of the two pages being wrong. This is
      // how the wrong ones were found in the first place.
      final inSet = cards.where(
        (c) => c.allNumbers.any((n) => n.startsWith('DZ-BT15/')),
      );
      final byName = <String, List<CatalogCard>>{};
      for (final card in inSet) {
        byName.putIfAbsent(card.name, () => []).add(card);
      }
      for (final entry in byName.entries) {
        final powers = entry.value
            .map((c) => c.attributes['power'] ?? '')
            .toSet();
        expect(
          powers,
          hasLength(1),
          reason:
              '${entry.key}: '
              '${entry.value.map((c) => '${c.cardNo} ${c.attributes['power']}')}',
        );
      }
    });

    test('a trigger icon is only ever on a trigger unit', () {
      final marked = cards.where((c) => c.attributes['trigger'] != null);
      expect(marked, isNotEmpty);
      for (final entry in marked) {
        expect(entry.attributes['cardType'], 'trigger', reason: entry.name);
      }
    });

    test('the trigger icons come from the card list, not from guessing', () {
      // For a long time only over triggers could be marked, because the only
      // source available did not record which trigger a trigger unit is. The
      // official card list prints it, and the sets read from there carry all
      // six kinds.
      final kinds = cards
          .map((c) => c.attributes['trigger'])
          .whereType<String>()
          .toSet();
      expect(kinds, containsAll(['critical', 'draw', 'front', 'heal', 'over']));
      expect(
        kinds.difference({
          'critical',
          'draw',
          'front',
          'heal',
          'stand',
          'over',
        }),
        isEmpty,
      );

      final marked = cards
          .where((c) => (c.attributes['trigger'] ?? '').isNotEmpty)
          .length;
      expect(marked, greaterThan(200));
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
      // A vanilla trigger's only printed text is its trigger, and that is now
      // read into the trigger field rather than left in the rules text -- so
      // "has something to say about itself" is either of the two.
      final described = cards
          .where(
            (c) =>
                (c.attributes['effect'] ?? '').isNotEmpty ||
                (c.attributes['trigger'] ?? '').isNotEmpty,
          )
          .length;
      expect(described / cards.length, greaterThan(0.99));
    });

    test('a known card has the abilities from its printing', () {
      // By number, not by name: three different cards are called Dragonic
      // Overlord -- the D-series one and two older Kagero ones -- and taking
      // whichever happened to hold the name was reading a different card.
      final overlord = cards.firstWhere(
        (c) => c.allNumbers.contains('D-BT02/001EN'),
      );
      expect(overlord.attributes['effect'], contains('[CONT](VC/RC)'));
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
      //
      // A handful are left over: a promo whose number says nothing, whose
      // nation the V- and D-series both used, and whose wording differs from
      // every other printing -- so it is its own card and has no sibling to
      // borrow a date from. Dating it off a differently worded card would be
      // guessing, and guessing "D-series" is what makes an illegal deck look
      // legal, so these stay undated and the app says it cannot check them.
      final unplaced = cards
          .where(
            (c) =>
                (c.attributes['series'] ?? '').isEmpty &&
                (c.attributes['possibleSeries'] ?? '').isEmpty,
          )
          .toList();
      expect(
        unplaced.length,
        lessThan(10),
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

    test('image filenames identify cards almost uniquely', () {
      // The image is what an imported Japanese card is matched on when its
      // number cannot be read, so a key that pointed at two cards would be a
      // silent mismatch. The few that do are dropped rather than guessed at,
      // but there must not be many.
      final counts = <String, int>{};
      for (final entry in cards) {
        final image = entry.attributes['imageUrl'];
        if (image == null || image.isEmpty) continue;
        final key = decklogImageKey(image);
        counts[key] = (counts[key] ?? 0) + 1;
      }
      final shared = counts.values.where((count) => count > 1).length;
      expect(shared, lessThan(10), reason: 'shared image keys: $shared');
      expect(counts.length, greaterThan(cards.length * 0.99));
    });

    test('card numbers survive the trip to a Japanese number', () {
      // Stripping the EN is what lets a Japanese deck find English cards, so
      // it must not make two cards look like one.
      final keys = <String, String>{};
      final clashes = <String>[];
      for (final entry in cards) {
        final number = entry.cardNo;
        if (number == null || number.isEmpty) continue;
        final key = decklogNumberKey(number);
        final seen = keys[key];
        if (seen != null && seen != entry.name) clashes.add(key);
        keys[key] = entry.name;
      }
      expect(clashes, isEmpty);
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

      // An original-series card with no reprint since.
      final frank = cards.firstWhere((c) => c.name == 'Monster Frank');
      expect(frank.attributes['series'], isNot(contains('d')));
    });

    test('a card reprinted forward into Standard becomes legal there', () {
      // The Blaster Blade Start Deck brought this printing of Flash Shield,
      // Iseult into Standard, and a card is legal wherever any of its
      // printings is -- so the database has to follow the reprint. Looked up
      // by number, because the name belongs to two different cards.
      final iseult = cards.firstWhere(
        (c) => c.allNumbers.contains('DZ-SS13/012EN'),
      );
      expect(iseult.attributes['series'], contains('d'));
    });

    test('D-series cards are Standard legal', () {
      // By name, because a name can belong to more than one card: the game
      // remakes a card under its old name with new stats, and those are
      // separate entries. At least one of them has to be Standard legal.
      for (final name in [
        'Dragonic Overlord',
        'Blaster Blade',
        'Light Dragon Deity of Honors, Amartinoa',
      ]) {
        final entries = cards.where((c) => c.name == name);
        expect(entries, isNotEmpty, reason: name);
        expect(
          entries.any((c) => (c.attributes['series'] ?? '').contains('d')),
          isTrue,
          reason: name,
        );
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

    test('a stride deck\'s crest is in the catalog, typed as a crest', () {
      // The crest a Stride Deckset brings is filed by the card list under no
      // card type at all -- "Others", beside a Plant token -- so it used to
      // be dropped with the tokens. A deck built around it does nothing
      // without it, and a playtest cannot put it into play if the app has
      // never heard of it.
      final crests = cards
          .where((c) => c.attributes['cardType'] == 'crest')
          .toList();
      expect(crests, hasLength(greaterThanOrEqualTo(6)));
      for (final crest in crests) {
        expect(
          crest.attributes['effect'],
          contains('You can perform [Stride]'),
          reason: 'that permission is what makes it one',
        );
      }

      final nightrose = crests.firstWhere(
        (c) => c.allNumbers.contains('DZ-SS03/T01EN'),
      );
      expect(nightrose.name, contains('Nightrose'));
      expect(nightrose.attributes['imageUrl'], contains('dzss03_t01'));
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

    test('a card is unique by its name, its stats and what it does', () {
      // The game remakes cards under their old names: an 8000 power original
      // and its 10000 power reissue are two cards, and "Flash Shield, Iseult"
      // is a grade 0 trigger in one era and a grade 1 normal unit in another.
      // Keyed by name alone, one silently stood in for the other. What must
      // be unique is the whole identity -- and stats are not the whole of it,
      // because a remake can match the original's numbers exactly and still
      // do something entirely different.
      final identities = cards
          .map(
            (c) => [
              c.lowerName,
              c.attributes['grade'] ?? '',
              c.attributes['power'] ?? '',
              c.attributes['shield'] ?? '',
              c.attributes['cardType'] ?? '',
              (c.attributes['effect'] ?? '').replaceAll(RegExp(r'\s+'), ''),
            ].join('|'),
          )
          .toSet();
      expect(identities.length, cards.length);

      // And the duplication by name is the exception, not the rule.
      final names = cards.map((c) => c.lowerName).toSet();
      expect(names.length, greaterThan(cards.length * 0.7));
    });

    test('same stats but different abilities are different cards', () {
      // DZ-SS13/002 and D-BT05/005 Blaster Blade are both grade 2, 10000
      // power, 5000 shield Keter Sanctuary units -- and do entirely different
      // things. Held as one card, a deck naming either was shown the other's
      // abilities and artwork.
      CatalogCard of(String number) => cards.firstWhere(
        (c) => c.allNumbers.contains(number),
        orElse: () => fail('no card printed as $number'),
      );

      final start = of('DZ-SS13/002EN');
      final booster = of('D-BT05/005EN');

      expect(start.name, 'Blaster Blade');
      expect(booster.name, 'Blaster Blade');
      expect(start.attributes['grade'], booster.attributes['grade']);
      expect(start.attributes['power'], booster.attributes['power']);

      expect(
        start.attributes['effect'],
        contains('Aichi icon'),
        reason: 'the start deck card searches the ride deck',
      );
      expect(
        booster.attributes['effect'],
        isNot(contains('Aichi icon')),
        reason: 'the booster card does not',
      );
      expect(start.imageFor('DZ-SS13/002EN'), isNot(booster.imageFor(null)));
    });

    test('one number never names two cards', () {
      // A number is looked up to decide which card a deck means, so two cards
      // claiming one printing would resolve arbitrarily -- exactly the bug
      // that showed the wrong Blaster Blade.
      final owners = <String, int>{};
      for (final card in cards) {
        for (final number in card.allNumbers) {
          owners[number] = (owners[number] ?? 0) + 1;
        }
      }
      final shared = owners.entries.where((e) => e.value > 1).toList();
      expect(shared, isEmpty, reason: 'numbers claimed twice: $shared');
    });

    test('every printing of a card can be looked up by its number', () {
      // Only one printing's number is shown, but a deck can name any of them.
      // Matching only the shown one sent the rest to be matched by name,
      // where a card sharing a name with a different one took its place.
      final iseult = cards.where((c) => c.name == 'Flash Shield, Iseult');
      expect(iseult.length, greaterThan(1), reason: 'a remade card');
      for (final entry in iseult) {
        expect(entry.allNumbers, contains(entry.cardNo));
      }
      final withAlternates = cards.where((c) => c.otherNumbers.isNotEmpty);
      expect(withAlternates.length, greaterThan(1000));
    });

    test('known cards resolve with the right attributes', () {
      final overlord = cards.firstWhere(
        (c) => c.allNumbers.contains('D-BT02/001EN'),
      );
      expect(overlord.name, 'Dragonic Overlord');
      expect(overlord.attributes['grade'], '3');
      expect(overlord.attributes['power'], '13000');
      expect(overlord.attributes['nation'], 'dragon-empire');
      expect(overlord.attributes['cardType'], 'normal');

      // The older Kagero cards of the same name are their own entries, and
      // keep their own stats rather than being overwritten by this one. Every
      // era it was remade in has its own numbers: 11000 in the original
      // series, 13000 in the V-series, and neither carries a nation.
      final original = cards.firstWhere(
        (c) => c.allNumbers.contains('BT01/S04EN'),
      );
      expect(original.attributes['power'], '11000');
      expect(original.attributes['clan'], 'Kagero');
      expect(original.attributes['nation'], isNull);

      final vSeries = cards.firstWhere(
        (c) => c.allNumbers.contains('V-CS01/004EN'),
      );
      expect(vSeries.attributes['power'], '13000');
      expect(vSeries.attributes['clan'], 'Kagero');
      expect(vSeries.attributes['nation'], isNull);
    });

    test('the promos asked for by hand are in the database', () {
      // Cards reported missing by someone playing with them. The database is
      // rebuilt from the official list, so a card can only be here because
      // the list carries it -- but a rebuild that dropped one of these would
      // otherwise be noticed the same way it was the first time.
      final surf = cards.firstWhere(
        (c) => c.allNumbers.contains('D-PR/1112EN'),
      );
      expect(surf.name, 'Onslaught Surf Dragon');
      expect(surf.attributes['grade'], '2');
      expect(surf.attributes['power'], '10000');
      expect(surf.attributes['shield'], '5000');
      expect(surf.attributes['nation'], 'stoicheia');
      expect(CardCatalog.search(cards, 'onslaught surf dragon').first, surf);
      expect(CardCatalog.search(cards, 'D-PR/1112EN').first, surf);
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
