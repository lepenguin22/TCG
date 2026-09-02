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

Future<DeckStore> loadedStore() async {
  final store = DeckStore();
  await store.load();
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('reading a deck code out of what was pasted', () {
    test('a full share link', () {
      expect(
        decklogCodeFrom('https://decklog-en.bushiroad.com/view/7K3X'),
        '7K3X',
      );
    });

    test('the Japanese host', () {
      expect(
        decklogCodeFrom('https://decklog.bushiroad.com/view/1TXGS'),
        '1TXGS',
      );
    });

    test('a link with a locale segment and a query string', () {
      expect(
        decklogCodeFrom('https://decklog-en.bushiroad.com/en/view/ABC123?x=1'),
        'ABC123',
      );
    });

    test('a link with surrounding text, as a share sheet gives it', () {
      expect(
        decklogCodeFrom(
          'Check my deck! https://decklog-en.bushiroad.com/view/7RD6E',
        ),
        '7RD6E',
      );
    });

    test('a bare deck code', () {
      expect(decklogCodeFrom('  CQMN '), 'CQMN');
    });

    test('nonsense is rejected rather than guessed at', () {
      expect(decklogCodeFrom('https://example.com/view/ABC'), isNull);
      expect(decklogCodeFrom('not a code at all'), isNull);
      expect(decklogCodeFrom(''), isNull);
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
        fetch: (code) async {
          requested = code;
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

      expect(result.unmatched, ['Card From Next Week']);
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
