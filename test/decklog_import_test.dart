import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tcg_decks/games/card_catalog.dart';
import 'package:tcg_decks/games/vanguard/vanguard_data.dart';
import 'package:tcg_decks/games/vanguard/vanguard_game.dart';
import 'package:tcg_decks/import/decklog.dart';
import 'package:tcg_decks/store/deck_store.dart';
import 'package:tcg_decks/store/decklog_import.dart';

const _asset = 'assets/cards/vanguard.json';

CatalogCard _card(String name, Map<String, Object> extra) =>
    CatalogCard.fromJson({'n': name, ...extra});

final _catalog = [
  _card('Dragonic Overlord', {
    'g': 3,
    't': 'normal',
    'na': 'dragon-empire',
    'no': 'D-BT02/001EN',
    'sr': 'd',
    'i': 'dbt02/dbt02_001.png',
  }),
  _card('Embodiment of Armor, Bahr', {
    'g': 1,
    't': 'normal',
    'na': 'dragon-empire',
    'no': 'D-BT01/030EN',
    'sr': 'd',
  }),
  _card('Lizard Soldier, Conroe', {
    'g': 0,
    't': 'normal',
    'na': 'dragon-empire',
    'no': 'D-BT01/031EN',
    'sr': 'd',
  }),
  _card('Dragonic Deathscythe', {
    'g': 2,
    't': 'normal',
    'na': 'dragon-empire',
    'no': 'D-BT01/032EN',
    'sr': 'd',
  }),
  // The database records that a card is a trigger unit but not which trigger
  // it is, so imported trigger units arrive with no icon. Only 45 of the
  // 1,315 trigger units in the real asset carry one.
  _card('Cosmic Hero, Grandbeat', {
    'g': 0,
    't': 'trigger',
    'na': 'dragon-empire',
    'no': 'D-BT01/040EN',
    'sr': 'd',
  }),
  // A card with twenty printings in the real database. The catalogue shows
  // one of them; a deck can name any.
  _card('Blaster Blade', {
    'g': 2,
    't': 'normal',
    'na': 'keter-sanctuary',
    'no': 'D-BT05/005EN',
    'no2': ['DZ-SS13/002EN', 'V-TD01/004EN'],
    'p': 10000,
    'sr': 'dv',
  }),
  _card('Chronojet Dragon', {
    'g': 4,
    't': 'g-unit',
    'na': 'dark-states',
    'no': 'DZ-BT06/EX03EN',
    'sr': 'd',
  }),
  _card('Energy Generator', {
    't': 'ride-deck-crest',
    'no': 'DZ-TD01/005EN',
    'sr': 'd',
  }),
];

/// A payload shaped like the one Deck Log's view endpoint returns.
String payload({
  List<Map<String, Object>> list = const [],
  List<Map<String, Object>> subList = const [],
  List<Map<String, Object>> pList = const [],
  Map<String, List<Map<String, Object>>> extra = const {},
  String gameTitleId = '1',
  String? deckName,
}) => jsonEncode({
  'game_title_id': gameTitleId,
  'deck_name': ?deckName,
  'list': list,
  'sub_list': subList,
  'p_list': pList,
  ...extra,
});

/// A ride deck: one unit of each grade 0-3, as the rules require.
final rideDeck = [
  entry('Lizard Soldier, Conroe', 1, 'D-BT01/031EN'),
  entry('Embodiment of Armor, Bahr', 1, 'D-BT01/030EN'),
  entry('Dragonic Deathscythe', 1, 'D-BT01/032EN'),
  entry('Dragonic Overlord', 1, 'D-BT02/001EN'),
];

Map<String, Object> entry(String name, int num, [String? number]) => {
  'name': name,
  'num': num,
  'card_number': ?number,
};

/// The deck codes in some text, without their sites, for the cases where only
/// the codes are under test.
List<String> codesIn(String input) => [
  for (final code in decklogCodesFrom(input)) code.code,
];

Future<DeckStore> loadedStore() async {
  final store = DeckStore();
  await store.load();
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('reading a deck code out of what was pasted', () {
    test('a full share link, remembering which site it names', () {
      expect(
        decklogCodeFrom('https://decklog-en.bushiroad.com/view/7K3X'),
        const DecklogCode('7K3X', host: decklogEnHost),
      );
    });

    test('the Japanese site', () {
      // The two sites share a code space, so which one a code belongs to has
      // to travel with it: asking the wrong site returns nothing.
      final code = decklogCodeFrom('https://decklog.bushiroad.com/view/19RVZ6');
      expect(code, const DecklogCode('19RVZ6', host: decklogJpHost));
      expect(code!.isJapanese, isTrue);
      expect(code.hosts, [decklogJpHost]);
    });

    test('a link with a locale segment and a query string', () {
      expect(
        decklogCodeFrom('https://decklog-en.bushiroad.com/en/view/ABC123?x=1')
            ?.code,
        'ABC123',
      );
    });

    test('a link with surrounding text, as a share sheet gives it', () {
      expect(
        decklogCodeFrom(
          'Check my deck! https://decklog-en.bushiroad.com/view/7RD6E',
        )?.code,
        '7RD6E',
      );
    });

    test('a bare deck code belongs to neither site, so both are tried', () {
      final code = decklogCodeFrom('  CQMN ');
      expect(code?.code, 'CQMN');
      expect(code?.host, isNull);
      expect(code?.hosts, [decklogEnHost, decklogJpHost]);
    });

    test('nonsense is rejected rather than guessed at', () {
      expect(decklogCodeFrom('https://example.com/view/ABC'), isNull);
      expect(decklogCodeFrom('not a code at all'), isNull);
      expect(decklogCodeFrom(''), isNull);
    });
  });

  group('reading several deck codes at once', () {
    test('one link per line', () {
      expect(
        codesIn(
          'https://decklog-en.bushiroad.com/view/AAA1\n'
          'https://decklog-en.bushiroad.com/view/BBB2',
        ),
        ['AAA1', 'BBB2'],
      );
    });

    test('links and bare codes mixed together', () {
      expect(
        codesIn('https://decklog-en.bushiroad.com/view/AAA1\nBBB2\nCCC3'),
        ['AAA1', 'BBB2', 'CCC3'],
      );
    });

    test('several links run together in one message', () {
      expect(
        codesIn(
          'my decks: https://decklog-en.bushiroad.com/view/AAA1 and '
          'https://decklog-en.bushiroad.com/view/BBB2 enjoy',
        ),
        ['AAA1', 'BBB2'],
      );
    });

    test('a comma separated list of codes', () {
      expect(codesIn('AAA1, BBB2, CCC3'), ['AAA1', 'BBB2', 'CCC3']);
    });

    test('duplicates are dropped so a deck imports once', () {
      expect(
        codesIn(
          'https://decklog-en.bushiroad.com/view/AAA1\n'
          'https://decklog-en.bushiroad.com/view/AAA1\n'
          'aaa1',
        ),
        ['AAA1'],
      );
    });

    test('prose is not read as a list of codes', () {
      // Ordinary words have the same shape as a code; only standing alone on
      // a line separates the two.
      expect(decklogCodesFrom('hello there'), isEmpty);
      expect(decklogCodesFrom('check out my new deck'), isEmpty);
      expect(decklogCodesFrom(''), isEmpty);
    });

    test('a link and the text around it yields only the code', () {
      expect(
        codesIn('Check my deck! https://decklog-en.bushiroad.com/view/7RD6E'),
        ['7RD6E'],
      );
    });
  });

  group('importing from the Japanese site', () {
    // The game is Japanese, so decks are often shared from decklog.bushiroad
    // .com. Its cards come back with Japanese names, which the English card
    // database cannot match -- but the card numbers are the same apart from
    // the EN the English printings carry, so the number bridges the two.

    test('a Japanese number finds the English card', () {
      expect(decklogNumberKey('D-BT02/001'), decklogNumberKey('D-BT02/001EN'));
      expect(decklogNumberKey('DZ-BT06/EX03'), 'dz-bt06/ex03');
    });

    test('an English variant marker survives the trip', () {
      expect(decklogNumberKey('EB10/021EN-W'), 'eb10/021-w');
      expect(decklogNumberKey('G-CB04/001EN SGR'), 'g-cb04/001 sgr');
    });

    test('the looser key drops the variant marker and the rarity', () {
      expect(decklogLooseNumberKey('EB10/021EN-W'), 'eb10/021');
      expect(decklogLooseNumberKey('G-CB04/001EN SGR'), 'g-cb04/001');
      // Stripping every letter after the digits does collapse the two halves
      // of a split promo -- BSF2025/01A and /01B are different cards. That is
      // why a key shared by two cards is dropped from the index rather than
      // matched: they stay reachable by their exact number instead.
      expect(
        decklogLooseNumberKey('BSF2025/01A'),
        decklogLooseNumberKey('BSF2025/01B'),
      );
      expect(
        decklogNumberKey('BSF2025/01A'),
        isNot(decklogNumberKey('BSF2025/01B')),
      );
    });

    test('a card whose looser key is shared is not mismatched', () async {
      final store = await loadedStore();
      final catalog = CardCatalog()
        ..seed(_asset, [
          _card('Split Promo A', {'g': 0, 't': 'normal', 'no': 'BSF2025/01A'}),
          _card('Split Promo B', {'g': 0, 't': 'normal', 'no': 'BSF2025/01B'}),
        ]);
      final result = await importDecklogDeck(
        store,
        catalog,
        parseDecklogPayload(
          payload(list: [entry('Split Promo B', 1, 'BSF2025/01B')]),
          code: 'X',
        ),
      );
      expect(
        store.viewOf(result.deck).items.single.card.name,
        'Split Promo B',
        reason: 'the exact number still finds it',
      );
    });

    test('a Japanese deck comes across in English', () async {
      final store = await loadedStore();
      final catalog = CardCatalog()..seed(_asset, _catalog);
      final result = await importDecklogDeck(
        store,
        catalog,
        parseDecklogPayload(
          payload(
            deckName: 'ドラゴニックオーバーロード',
            list: [
              // Japanese names, and numbers without the EN.
              entry('ドラゴニック・オーバーロード', 4, 'D-BT02/001'),
              entry('鎧の化身 バール', 4, 'D-BT01/030'),
            ],
            pList: [entry('リザードソルジャー コンロー', 1, 'D-BT01/031')],
          ),
          code: '19RVZ6',
        ),
      );

      expect(result.matched, 3, reason: 'matched on number, not name');
      expect(result.unmatched, isEmpty);
      final view = store.viewOf(result.deck);
      expect(
        view.items.map((item) => item.card.name),
        containsAll([
          'Dragonic Overlord',
          'Embodiment of Armor, Bahr',
          'Lizard Soldier, Conroe',
        ]),
        reason: 'the English name is what gets stored',
      );
      // And the rest of the import still works: zones, grades, rules.
      expect(view.zoneCount(zoneRide), 1);
      expect(view.zoneCount(zoneMain), 8);
      expect(
        view.items.first.card.attributes['series'],
        isNotNull,
        reason: 'a matched card arrives fully filled in',
      );
    });

    test('the deck keeps the name its owner gave it', () async {
      final store = await loadedStore();
      final catalog = CardCatalog()..seed(_asset, _catalog);
      final result = await importDecklogDeck(
        store,
        catalog,
        parseDecklogPayload(
          payload(
            deckName: 'オーバーロード軸',
            list: [entry('ドラゴニック・オーバーロード', 4, 'D-BT02/001')],
          ),
          code: '19RVZ6',
        ),
      );
      expect(result.deck.name, 'オーバーロード軸');
    });

    test('a card with no English printing keeps its Japanese name', () async {
      // Japanese sets run ahead of English ones, so this is normal rather
      // than exceptional, and the deck must not come out short because of it.
      final store = await loadedStore();
      final catalog = CardCatalog()..seed(_asset, _catalog);
      final result = await importDecklogDeck(
        store,
        catalog,
        parseDecklogPayload(
          payload(list: [entry('未発売のカード', 4, 'DZ-BT99/001')]),
          code: '19RVZ6',
        ),
      );
      expect(result.unmatched, ['未発売のカード (DZ-BT99/001)']);
      expect(result.cardsAdded, 4);
      expect(store.viewOf(result.deck).zoneCount(zoneMain), 4);
    });

    test('the ride deck is found with nothing matched to read', () async {
      // A Japanese deck of cards the English database has never seen has no
      // grades to read, so every candidate section used to tie and the first
      // one encountered won. Size decides instead: a ride deck is four cards.
      final store = await loadedStore();
      final catalog = CardCatalog()..seed(_asset, _catalog);
      final result = await importDecklogDeck(
        store,
        catalog,
        parseDecklogPayload(
          payload(
            list: [entry('未発売のカード', 50, 'DZ-BT99/001')],
            // A stray one-card section that also fits the shape...
            subList: [entry('マーカー', 1, 'DZ-BT99/900')],
            // ...and the real ride deck, four cards, one of each.
            pList: [
              entry('ライド0', 1, 'DZ-BT99/010'),
              entry('ライド1', 1, 'DZ-BT99/011'),
              entry('ライド2', 1, 'DZ-BT99/012'),
              entry('ライド3', 1, 'DZ-BT99/013'),
            ],
          ),
          code: '19RVZ6',
        ),
      );
      expect(store.viewOf(result.deck).zoneCount(zoneRide), 4);
    });

    test('an unmatched card is still dated by its number', () async {
      // Japanese sets run ahead of the English ones, so an imported Japanese
      // deck is full of cards the database has never seen. The number still
      // says which era they are from, and without that every one of them
      // reported that it could not be checked against the format.
      final store = await loadedStore();
      final catalog = CardCatalog()..seed(_asset, _catalog);
      final result = await importDecklogDeck(
        store,
        catalog,
        parseDecklogPayload(
          payload(list: [entry('未発売のカード', 4, 'DZ-BT99/001')]),
          code: '19RVZ6',
        ),
      );

      final card = store.viewOf(result.deck).items.single.card;
      expect(card.attributes['series'], 'd');
      const game = VanguardGame();
      expect(
        game.validate(store.viewOf(result.deck)).map((i) => i.message),
        isNot(contains(contains('could not be checked'))),
      );
    });

    test('an unmatched card is reported with its number', () async {
      // The number is what says why a card was missed: a set the English
      // release has not reached yet reads very differently from a number in a
      // shape the app failed to handle.
      final store = await loadedStore();
      final catalog = CardCatalog()..seed(_asset, _catalog);
      final result = await importDecklogDeck(
        store,
        catalog,
        parseDecklogPayload(
          payload(list: [entry('未発売のカード', 4, 'DZ-BT99/001')]),
          code: '19RVZ6',
        ),
      );
      expect(result.unmatched, ['未発売のカード (DZ-BT99/001)']);
    });

    test('the image filename identifies a card across the two sites', () {
      // Both sites draw a card's artwork from the same filename, and the
      // English one does not always mark it with EN.
      expect(decklogImageKey('dbt02/dbt02_001.png'), 'dbt02_001');
      expect(
        decklogImageKey(
          'https://en.cf-vanguard.com/wordpress/wp-content/images/cardlist/'
          'gbt03/GBT03_070EN.jpg',
        ),
        'gbt03_070',
      );
    });

    test('a card with no usable number is matched on its image', () async {
      // The image is the one field a Deck Log card row is known to always
      // carry, so it is the backstop when the number is absent or written in
      // a shape the app does not recognise.
      final store = await loadedStore();
      final catalog = CardCatalog()..seed(_asset, _catalog);
      final result = await importDecklogDeck(
        store,
        catalog,
        parseDecklogPayload(
          jsonEncode({
            'game_title_id': '1',
            'list': [
              {
                'name': 'ドラゴニック・オーバーロード',
                'num': 4,
                'img': 'dbt02/dbt02_001.png',
              },
            ],
          }),
          code: '19RVZ6',
        ),
      );

      expect(result.matched, 1);
      expect(
        store.viewOf(result.deck).items.single.card.name,
        'Dragonic Overlord',
      );
    });

    test(
      'a number in an unexpected shape falls through to the image',
      () async {
        final store = await loadedStore();
        final catalog = CardCatalog()..seed(_asset, _catalog);
        final result = await importDecklogDeck(
          store,
          catalog,
          parseDecklogPayload(
            jsonEncode({
              'game_title_id': '1',
              'list': [
                {
                  'name': 'ドラゴニック・オーバーロード',
                  'num': 4,
                  'card_number': 'D-BT02/001 RRR 【ドラゴンエンパイア】',
                  'img': 'dbt02/dbt02_001.png',
                },
              ],
            }),
            code: '19RVZ6',
          ),
        );
        expect(result.matched, 1);
        expect(result.unmatched, isEmpty);
      },
    );

    test('a Japanese link is fetched from the Japanese site', () async {
      final asked = <String>[];
      await loadDecklogBatch(
        'https://decklog.bushiroad.com/view/19RVZ6',
        fetch: (ref) async {
          asked.addAll(ref.hosts);
          return payload(list: [entry('Dragonic Overlord', 4)]);
        },
      );
      expect(asked, [decklogJpHost]);
    });

    test('an English and a Japanese deck import side by side', () async {
      final loads = await loadDecklogBatch(
        'https://decklog-en.bushiroad.com/view/7K3X\n'
        'https://decklog.bushiroad.com/view/19RVZ6',
        fetch: (ref) async =>
            payload(list: [entry('Dragonic Overlord', 4, 'D-BT02/001EN')]),
      );
      expect(loads.map((load) => load.deck?.code), ['7K3X', '19RVZ6']);
    });
  });

  group('a real Japanese payload', () {
    // Taken from what decklog.bushiroad.com actually returned for the deck
    // 19RVZ6, rather than from what its fields were assumed to be. Every
    // field named here was observed: `list` is the fifty card main deck,
    // `p_list` the ride deck, each entry carrying its own type, slot and
    // grade, and a Japanese card number ending in its rarity where the
    // English printing would carry EN.
    Map<String, Object?> row(
      String number,
      int num,
      String name,
      String grade,
      String img, {
      int type = 1,
      Object slot = 0,
    }) => {
      'card_number': number,
      'num': num,
      '_num': num,
      'type': type,
      'slot': slot,
      'img': img,
      'card_kind': 1,
      'rare': 'TDR',
      'name': name,
      'grade': grade,
      'is_over': false,
      'add_ride': false,
      'max': 4,
    };

    String realPayload() => jsonEncode({
      'id': 4791048,
      'deck_id': '19RVZ6',
      'title': 'ドロイヤル5',
      'game_title_id': 1,
      'deck_param1': 'D',
      'deck_param2': 'ケテルサンクチュアリ',
      'list': [
        row('D-BT02/001R', 4, 'ドラゴニック・オーバーロード', '3', 'D-BT02/dbt02_001.png'),
        row('DZ-SS14/006R', 4, 'ソウルセイバー・ドラゴン', '3', 'DZ-SS14/dzss14_012.png'),
      ],
      'sub_list': [],
      'p_list': [
        row(
          'D-BT01/031R',
          1,
          'リザードソルジャー コンロー',
          '0',
          'DZ-SS14/dzss14_020.png',
          type: 3,
          slot: 'grade_0',
        ),
        row(
          'DZ-SS14/004R',
          1,
          'ブラスター・ブレード',
          '2',
          'DZ-SS14/dzss14_004.png',
          type: 3,
          slot: 'grade_2',
        ),
        row(
          'DZ-SS14/009R',
          1,
          'クレスト',
          '-',
          'DZ-SS14/dzss14_009.png',
          type: 3,
          slot: 'grade_p2',
        ),
      ],
    });

    test('the deck name and game are read', () {
      final deck = parseDecklogPayload(realPayload(), code: '19RVZ6');
      expect(deck.name, 'ドロイヤル5');
      expect(
        deck.isVanguard,
        isTrue,
        reason: 'game_title_id arrives as an int',
      );
    });

    test('a Japanese number ending in its rarity finds the English card', () {
      // DZ-SS14/001R and DZ-SS14/001EN are the same card.
      expect(
        decklogLooseNumberKey('DZ-SS14/001R'),
        decklogLooseNumberKey('DZ-SS14/001EN'),
      );
      expect(decklogLooseNumberKey('D-BT02/001R'), 'd-bt02/001');
    });

    test('cards land in the zones Deck Log filed them under', () async {
      final store = await loadedStore();
      final catalog = CardCatalog()..seed(_asset, _catalog);
      final result = await importDecklogDeck(
        store,
        catalog,
        parseDecklogPayload(realPayload(), code: '19RVZ6'),
      );

      final view = store.viewOf(result.deck);
      expect(view.zoneCount(zoneMain), 8);
      expect(view.zoneCount(zoneRide), 3, reason: 'p_list is the ride deck');
    });

    test('the rarity suffix no longer costs a match', () async {
      final store = await loadedStore();
      final catalog = CardCatalog()..seed(_asset, _catalog);
      final result = await importDecklogDeck(
        store,
        catalog,
        parseDecklogPayload(realPayload(), code: '19RVZ6'),
      );
      // D-BT02/001R and D-BT01/031R are in the fixture database as EN cards.
      expect(
        store.viewOf(result.deck).items.map((item) => item.card.name),
        containsAll(['Dragonic Overlord', 'Lizard Soldier, Conroe']),
      );
    });

    test('the crest is recognised, so the ride deck is legal', () async {
      // The crest has no grade and a slot of its own. Read as a fifth unit it
      // made every imported ride deck illegal.
      final store = await loadedStore();
      final catalog = CardCatalog()..seed(_asset, _catalog);
      final result = await importDecklogDeck(
        store,
        catalog,
        parseDecklogPayload(realPayload(), code: '19RVZ6'),
      );

      final crest = store
          .viewOf(result.deck)
          .items
          .firstWhere((item) => item.card.name == 'クレスト');
      expect(crest.card.attributes['cardType'], 'ride-deck-crest');
      expect(crest.entry.zoneId, zoneRide);
    });

    test('a card too new for the database keeps its grade', () async {
      // Japanese sets run ahead, so these are the common case, not the edge.
      final store = await loadedStore();
      final catalog = CardCatalog()..seed(_asset, _catalog);
      final result = await importDecklogDeck(
        store,
        catalog,
        parseDecklogPayload(realPayload(), code: '19RVZ6'),
      );

      final unseen = store
          .viewOf(result.deck)
          .items
          .firstWhere((item) => item.card.name == 'ソウルセイバー・ドラゴン');
      expect(unseen.card.attributes['grade'], '3');
      expect(unseen.card.attributes['series'], 'd', reason: 'from its number');
    });
  });

  group('the printing a deck names', () {
    // A card can have twenty printings and the database shows one of them, so
    // a deck naming another came out reading a number its owner had never
    // entered: the right card, under the wrong printing.
    final blaster = _catalog.firstWhere((c) => c.name == 'Blaster Blade');

    test('every printing is reachable', () {
      expect(blaster.allNumbers, contains('D-BT05/005EN'));
      expect(blaster.allNumbers, contains('DZ-SS13/002EN'));
    });

    test('the number given is the number recorded', () {
      expect(printedNumberFor(blaster, 'DZ-SS13/002EN'), 'DZ-SS13/002EN');
      expect(printedNumberFor(blaster, 'V-TD01/004EN'), 'V-TD01/004EN');
    });

    test('a Japanese number records its English printing', () {
      // DZ-SS13/002R is how the Japanese site writes it -- the rarity where
      // the English printing carries EN.
      expect(printedNumberFor(blaster, 'DZ-SS13/002R'), 'DZ-SS13/002EN');
    });

    test('nothing given leaves the database\'s own number', () {
      expect(printedNumberFor(blaster, null), isNull);
      expect(printedNumberFor(blaster, '  '), isNull);
    });

    test('a printing the database has never seen is still recorded', () {
      expect(printedNumberFor(blaster, 'DZ-BT99/001EN'), 'DZ-BT99/001EN');
    });

    test('an imported deck keeps the printing it named', () async {
      final store = await loadedStore();
      final catalog = CardCatalog()..seed(_asset, _catalog);
      final result = await importDecklogDeck(
        store,
        catalog,
        parseDecklogPayload(
          payload(list: [entry('Blaster Blade', 4, 'DZ-SS13/002EN')]),
          code: '6XDWK',
        ),
      );

      final card = store.viewOf(result.deck).items.single.card;
      expect(card.name, 'Blaster Blade');
      expect(card.attributes['cardNo'], 'DZ-SS13/002EN');
      // And it is still the right card, filled in from the database.
      expect(card.attributes['grade'], '2');
      expect(card.attributes['power'], '10000');
      expect(result.matched, 1);
      expect(result.unmatched, isEmpty);
    });
  });

  group('the trigger icon, when Deck Log carries one', () {
    // The card database says a card is a trigger unit but not which trigger,
    // so this is an answer the user would otherwise have to give by hand.
    // Which key Deck Log uses is not documented and could not be checked from
    // where this was written, so no key name is assumed: a value that can only
    // be a trigger is believed, and anything else is ignored.
    DecklogCard first(Map<String, Object?> row) => parseDecklogPayload(
      jsonEncode({
        'game_title_id': '1',
        'list': [
          {'name': 'Some Trigger', 'num': 4, ...row},
        ],
      }),
      code: 'X',
    ).cards.first;

    test('read from a plainly named field', () {
      expect(first({'trigger': 'heal'}).trigger, 'heal');
    });

    test('read whatever the field is called', () {
      expect(first({'trigger_type': 'critical'}).trigger, 'critical');
      expect(first({'icon': 'DRAW'}).trigger, 'draw');
      expect(first({'whatever_they_call_it': 'front'}).trigger, 'front');
    });

    test('read out of an icon filename', () {
      expect(first({'icon': 'trigger_stand.png'}).trigger, 'stand');
    });

    test('read from a nested object', () {
      expect(
        first({
          'custom_param': {'trigger': 'over'},
        }).trigger,
        'over',
      );
    });

    test('absent when nothing in the row spells a trigger', () {
      expect(first({'card_number': 'D-BT01/030EN'}).trigger, isNull);
      expect(first({'rarity': 'RRR', 'num2': '4'}).trigger, isNull);
    });

    test('the name and the rules text are never read as one', () {
      // "Draw" and "Critical" are ordinary words in both.
      expect(
        parseDecklogPayload(
          jsonEncode({
            'game_title_id': '1',
            'list': [
              {'name': 'Draw', 'num': 4, 'effect': 'critical'},
            ],
          }),
          code: 'X',
        ).cards.first.trigger,
        isNull,
      );
    });

    test('a value that merely contains a trigger word is not believed', () {
      expect(first({'note': 'healing potion of drawing'}).trigger, isNull);
    });
  });

  group('loading a batch', () {
    test('every code is fetched, in order', () async {
      final requested = <String>[];
      final loads = await loadDecklogBatch(
        'AAA1\nBBB2',
        fetch: (ref) async {
          requested.add(ref.code);
          return payload(list: [entry('Dragonic Overlord', 4)]);
        },
      );
      expect(requested, ['AAA1', 'BBB2']);
      expect(loads.map((load) => load.deck?.code), ['AAA1', 'BBB2']);
    });

    test('a failure is reported against its code, not thrown', () async {
      final loads = await loadDecklogBatch(
        'AAA1\nBAD2',
        fetch: (ref) async {
          if (ref.code == 'BAD2') throw const DecklogException('Nope.');
          return payload(list: [entry('Dragonic Overlord', 4)]);
        },
      );
      expect(loads.first.deck, isNotNull);
      expect(loads.last.deck, isNull);
      expect(loads.last.code, 'BAD2');
      expect(loads.last.error, 'Nope.');
    });

    test('input with no codes in it is still rejected outright', () async {
      await expectLater(
        loadDecklogBatch('hello there', fetch: (_) async => fail('no request')),
        throwsA(isA<DecklogException>()),
      );
    });

    test('a pasted payload is one deck', () async {
      final loads = await loadDecklogBatch(
        payload(list: [entry('Dragonic Overlord', 4)]),
        fetch: (_) async => fail('should not have been called'),
      );
      expect(loads, hasLength(1));
      expect(loads.single.deck?.code, 'pasted');
    });
  });

  group('reading the payload', () {
    test('cards come back with names, counts and numbers', () {
      final deck = parseDecklogPayload(
        payload(
          deckName: 'Overlord',
          list: [entry('Dragonic Overlord', 4, 'D-BT02/001EN')],
          subList: [entry('Lizard Soldier, Conroe', 1, 'D-BT01/031EN')],
        ),
        code: '7K3X',
      );

      expect(deck.code, '7K3X');
      expect(deck.name, 'Overlord');
      expect(deck.isVanguard, isTrue);
      expect(deck.totalCards, 5);
      expect(deck.cards.first.name, 'Dragonic Overlord');
      expect(deck.cards.first.quantity, 4);
      expect(deck.cards.first.cardNumber, 'D-BT02/001EN');
      expect(deck.cards.first.section, 'list');
      expect(deck.cards.last.section, 'sub_list');
    });

    test('a deck for one of the other games is recognisable as such', () {
      final deck = parseDecklogPayload(
        payload(gameTitleId: '2', list: [entry('Some Weiss Card', 4)]),
        code: 'X',
      );
      expect(deck.isVanguard, isFalse);
    });

    test('rows with no name or no count are skipped', () {
      final deck = parseDecklogPayload(
        jsonEncode({
          'game_title_id': '1',
          'list': [
            {'name': '', 'num': 4},
            {'name': 'Real Card', 'num': 0},
            {'name': 'Kept', 'num': 2},
          ],
        }),
        code: 'X',
      );
      expect(deck.cards.map((c) => c.name), ['Kept']);
    });

    test('a body that is not JSON gives a message worth showing', () {
      expect(
        () => parseDecklogPayload('<html>404</html>', code: 'X'),
        throwsA(
          isA<DecklogException>().having(
            (e) => e.message,
            'message',
            contains('may not be shared publicly'),
          ),
        ),
      );
    });

    test('an empty deck is reported rather than imported', () {
      expect(
        () => parseDecklogPayload(payload(), code: 'X'),
        throwsA(isA<DecklogException>()),
      );
    });
  });

  group('loading', () {
    test('a code is fetched and parsed', () async {
      var requested = '';
      final deck = await loadDecklog(
        'https://decklog-en.bushiroad.com/view/7K3X',
        fetch: (ref) async {
          requested = ref.code;
          return payload(list: [entry('Dragonic Overlord', 4)]);
        },
      );
      expect(requested, '7K3X');
      expect(deck.cards.single.name, 'Dragonic Overlord');
    });

    test('a pasted payload skips the network entirely', () async {
      final deck = await loadDecklog(
        payload(list: [entry('Dragonic Overlord', 4)]),
        fetch: (_) async => fail('should not have been called'),
      );
      expect(deck.cards.single.quantity, 4);
      expect(deck.code, 'pasted');
    });

    test('input that is neither is rejected before any request', () async {
      await expectLater(
        loadDecklog('hello there', fetch: (_) async => fail('no request')),
        throwsA(isA<DecklogException>()),
      );
    });
  });

  group('turning a Deck Log deck into one of ours', () {
    Future<DecklogImportResult> importOf(DecklogDeck source) async {
      final store = await loadedStore();
      final catalog = CardCatalog()..seed(_asset, _catalog);
      return importDecklogDeck(store, catalog, source);
    }

    test('cards are matched by number and arrive filled in', () async {
      final result = await importOf(
        parseDecklogPayload(
          payload(
            list: [entry('Whatever Deck Log Calls It', 4, 'D-BT02/001EN')],
          ),
          code: 'X',
        ),
      );

      expect(result.matched, 1);
      expect(result.cardsAdded, 4);
      expect(result.unmatched, isEmpty);
    });

    test('cards are matched by name when there is no number', () async {
      final result = await importOf(
        parseDecklogPayload(
          payload(list: [entry('Embodiment of Armor, Bahr', 4)]),
          code: 'X',
        ),
      );
      expect(result.matched, 1);
      expect(result.unmatched, isEmpty);
    });

    // Deck Log names its sections `list`, `sub_list` and `p_list` for every
    // game it hosts, and nothing says which holds a Vanguard ride deck.
    // Reading the names the wrong way round put ride decks in the main deck,
    // so the section is now identified by shape and these pin that down.
    group('finding the ride deck', () {
      Future<(DeckStore, DecklogImportResult)> importOf(String body) async {
        final store = await loadedStore();
        final catalog = CardCatalog()..seed(_asset, _catalog);
        final result = await importDecklogDeck(
          store,
          catalog,
          parseDecklogPayload(body, code: 'X'),
        );
        return (store, result);
      }

      final mainDeck = [
        entry('Dragonic Overlord', 4, 'D-BT02/001EN'),
        entry('Embodiment of Armor, Bahr', 4, 'D-BT01/030EN'),
      ];

      test('in p_list', () async {
        final (store, result) = await importOf(
          payload(list: mainDeck, pList: rideDeck),
        );
        expect(store.viewOf(result.deck).zoneCount(zoneRide), 4);
        expect(store.viewOf(result.deck).zoneCount(zoneMain), 8);
        expect(result.rideDeckFound, isTrue);
      });

      test('in sub_list', () async {
        final (store, result) = await importOf(
          payload(list: mainDeck, subList: rideDeck),
        );
        expect(store.viewOf(result.deck).zoneCount(zoneRide), 4);
        expect(store.viewOf(result.deck).zoneCount(zoneMain), 8);
      });

      test('in a section we have never seen before', () async {
        final (store, result) = await importOf(
          payload(list: mainDeck, extra: {'ride_list': rideDeck}),
        );
        expect(store.viewOf(result.deck).zoneCount(zoneRide), 4);
        expect(store.viewOf(result.deck).zoneCount(zoneMain), 8);
      });

      test('a G zone alongside it is not mistaken for one', () async {
        final (store, result) = await importOf(
          payload(
            list: mainDeck,
            pList: rideDeck,
            subList: [entry('Chronojet Dragon', 16, 'DZ-BT06/EX03EN')],
          ),
        );
        final view = store.viewOf(result.deck);
        expect(view.zoneCount(zoneRide), 4);
        expect(view.zoneCount(zoneG), 16);
        expect(view.zoneCount(zoneMain), 8);
      });

      test('the main deck is never taken for the ride deck', () async {
        final (store, result) = await importOf(payload(list: mainDeck));
        expect(store.viewOf(result.deck).zoneCount(zoneRide), 0);
        expect(store.viewOf(result.deck).zoneCount(zoneMain), 8);
      });

      test('a section holding two of a grade is not a ride deck', () async {
        // Four one-ofs, but two grade 3s: that is a trimmed main deck, not a
        // ride deck, and guessing wrong is what this whole path is avoiding.
        final (store, result) = await importOf(
          payload(
            list: mainDeck,
            pList: [
              entry('Lizard Soldier, Conroe', 1, 'D-BT01/031EN'),
              entry('Dragonic Overlord', 1, 'D-BT02/001EN'),
              entry('Dragonic Overlord', 1, 'D-BT02/001EN'),
            ],
          ),
        );
        expect(store.viewOf(result.deck).zoneCount(zoneRide), 0);
        expect(result.rideDeckFound, isFalse);
      });

      test('a single flat list is left alone and reported', () async {
        final (store, result) = await importOf(
          payload(list: [...mainDeck, ...rideDeck]),
        );
        expect(result.rideDeckFound, isFalse);
        expect(store.viewOf(result.deck).zoneCount(zoneRide), 0);
        expect(
          store.viewOf(result.deck).zoneCount(zoneMain),
          12,
          reason: 'nothing is dropped, even when the ride deck cannot be told',
        );
      });

      test('the counts say where every card went', () async {
        final (_, result) = await importOf(
          payload(list: mainDeck, pList: rideDeck),
        );
        expect(result.zoneCounts, {zoneMain: 8, zoneRide: 4});
      });

      test('a ride deck of cards the database does not know', () async {
        // Nothing to read a grade off, so the shape alone has to carry it.
        final (store, result) = await importOf(
          payload(
            list: mainDeck,
            pList: [
              entry('Unknown Zero', 1, 'DZ-BT99/010EN'),
              entry('Unknown One', 1, 'DZ-BT99/011EN'),
              entry('Unknown Two', 1, 'DZ-BT99/012EN'),
              entry('Unknown Three', 1, 'DZ-BT99/013EN'),
            ],
          ),
        );
        expect(store.viewOf(result.deck).zoneCount(zoneRide), 4);
      });
    });

    test('a G unit lands in the G zone whatever list it came from', () async {
      // Deck Log's sections do not line up with ours for stride decks, and a
      // G unit is only ever legal in the G zone.
      final store = await loadedStore();
      final catalog = CardCatalog()..seed(_asset, _catalog);
      final result = await importDecklogDeck(
        store,
        catalog,
        parseDecklogPayload(
          payload(list: [entry('Chronojet Dragon', 4, 'DZ-BT06/EX03EN')]),
          code: 'X',
        ),
      );

      final view = store.viewOf(result.deck);
      expect(view.zoneCount(zoneG), 4);
      expect(view.zoneCount(zoneMain), 0);
    });

    test('a ride deck crest lands in the ride deck', () async {
      final store = await loadedStore();
      final catalog = CardCatalog()..seed(_asset, _catalog);
      final result = await importDecklogDeck(
        store,
        catalog,
        parseDecklogPayload(
          payload(list: [entry('Energy Generator', 1, 'DZ-TD01/005EN')]),
          code: 'X',
        ),
      );

      expect(store.viewOf(result.deck).zoneCount(zoneRide), 1);
    });

    test('an unknown card is still imported, and reported', () async {
      final store = await loadedStore();
      final catalog = CardCatalog()..seed(_asset, _catalog);
      final result = await importDecklogDeck(
        store,
        catalog,
        parseDecklogPayload(
          payload(list: [entry('Card From Next Week', 4, 'DZ-BT99/001EN')]),
          code: 'X',
        ),
      );

      expect(result.unmatched, ['Card From Next Week (DZ-BT99/001EN)']);
      expect(result.cardsAdded, 4, reason: 'the deck is not left short');
      final view = store.viewOf(result.deck);
      expect(view.zoneCount(zoneMain), 4);
      expect(view.items.single.card.name, 'Card From Next Week');
      expect(view.items.single.card.attributes['cardNo'], 'DZ-BT99/001EN');
    });

    test('imported trigger units are counted as trigger units', () async {
      // They arrive with no trigger icon, and a deck of sixteen of them used
      // to be reported as having one.
      final store = await loadedStore();
      final catalog = CardCatalog()..seed(_asset, _catalog);
      final result = await importDecklogDeck(
        store,
        catalog,
        parseDecklogPayload(
          payload(list: [entry('Cosmic Hero, Grandbeat', 16, 'D-BT01/040EN')]),
          code: 'X',
        ),
      );

      const game = VanguardGame();
      final view = store.viewOf(result.deck);
      expect(
        game.validate(view).map((i) => i.message),
        isNot(contains(contains('1 trigger units'))),
      );
      final triggers = game
          .stats(view)
          .firstWhere((group) => group.title == 'Triggers');
      expect(triggers.caption, '16 of 16');
    });

    test('a trigger Deck Log named arrives set on the card', () async {
      final store = await loadedStore();
      final catalog = CardCatalog()..seed(_asset, _catalog);
      final result = await importDecklogDeck(
        store,
        catalog,
        parseDecklogPayload(
          jsonEncode({
            'game_title_id': '1',
            'list': [
              {
                'name': 'Cosmic Hero, Grandbeat',
                'num': 4,
                'card_number': 'D-BT01/040EN',
                'trigger': 'heal',
              },
            ],
          }),
          code: 'X',
        ),
      );
      final card = store.viewOf(result.deck).items.single.card;
      expect(card.attributes['trigger'], 'heal');
    });

    test('an imported deck can be checked against the rules', () async {
      final store = await loadedStore();
      final catalog = CardCatalog()..seed(_asset, _catalog);
      final result = await importDecklogDeck(
        store,
        catalog,
        parseDecklogPayload(
          payload(list: [entry('Dragonic Overlord', 4, 'D-BT02/001EN')]),
          code: 'X',
        ),
      );

      const game = VanguardGame();
      final issues = game.validate(store.viewOf(result.deck));
      // Four cards is not a legal deck, and the rules engine can say so --
      // which is only possible because the import filled the cards in.
      expect(
        issues.map((i) => i.message),
        contains(contains('must hold exactly 50')),
      );
      expect(
        issues.map((i) => i.message),
        isNot(contains(contains('could not be checked'))),
      );
    });

    test(
      'the deck is named after the Deck Log entry and says where it came from',
      () async {
        final result = await importOf(
          parseDecklogPayload(
            payload(
              deckName: 'My Overlord Deck',
              list: [entry('Dragonic Overlord', 4, 'D-BT02/001EN')],
            ),
            code: '7K3X',
          ),
        );
        expect(result.deck.name, 'My Overlord Deck');
        expect(result.deck.description, contains('7K3X'));
      },
    );

    test('an unnamed Deck Log entry falls back to its code', () async {
      final result = await importOf(
        parseDecklogPayload(
          payload(list: [entry('Dragonic Overlord', 4)]),
          code: '7K3X',
        ),
      );
      expect(result.deck.name, 'Deck Log 7K3X');
    });

    test('importing twice reuses the library cards', () async {
      final store = await loadedStore();
      final catalog = CardCatalog()..seed(_asset, _catalog);
      final source = parseDecklogPayload(
        payload(list: [entry('Dragonic Overlord', 4, 'D-BT02/001EN')]),
        code: 'X',
      );

      await importDecklogDeck(store, catalog, source);
      await importDecklogDeck(store, catalog, source);

      expect(store.decks, hasLength(2));
      expect(store.cards, hasLength(1), reason: 'one library entry, two decks');
    });
  });
}
