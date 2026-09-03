import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tcg_decks/games/card_catalog.dart';
import 'package:tcg_decks/store/catalog_backfill.dart';
import 'package:tcg_decks/store/deck_store.dart';

const _asset = 'assets/cards/vanguard.json';

CatalogCard _card(String name, Map<String, Object> extra) =>
    CatalogCard.fromJson({'n': name, ...extra});

final _catalog = [
  _card('Dragonic Overlord', {
    'g': 3,
    't': 'normal',
    'na': 'dragon-empire',
    'p': 13000,
    'no': 'D-BT02/001EN',
    'e': '[CONT](VC/RC):Something.',
    'i': 'dbt02/dbt02_001.png',
    'sr': 'dov',
  }),
  _card('Blitz Assault Dragon', {
    'g': 0,
    't': 'trigger',
    'na': 'dragon-empire',
    'no': 'DZ-BT01/030EN',
    'sr': 'd',
  }),
];

Future<DeckStore> loadedStore() async {
  final store = DeckStore();
  await store.load();
  return store;
}

CardCatalog seededCatalog([List<CatalogCard>? cards]) =>
    CardCatalog()..seed(_asset, cards ?? _catalog);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a card saved before the catalog gets its details filled in', () async {
    final store = await loadedStore();
    // What an older build would have saved: a name and nothing else.
    final card = store.saveCard(
      gameId: 'vanguard',
      name: 'Dragonic Overlord',
      attributes: {'grade': '3', 'cardType': 'normal'},
    );

    final filled = await backfillLibraryFromCatalog(store, seededCatalog());

    expect(filled, 1);
    final updated = store.cardById(card.id)!;
    expect(updated.attributes['series'], 'dov');
    expect(updated.attributes['cardNo'], 'D-BT02/001EN');
    expect(updated.attributes['nation'], 'dragon-empire');
    expect(updated.attributes['effect'], contains('[CONT]'));
    expect(updated.attributes['imageUrl'], contains('dbt02_001.png'));
    // The card keeps its identity, so decks referencing it are untouched.
    expect(updated.id, card.id);
    expect(updated.name, 'Dragonic Overlord');
  });

  test('the deck that used the card now validates against the pool', () async {
    final store = await loadedStore();
    final deck = store.createDeck(name: 'Old deck');
    final card = store.saveCard(
      gameId: 'vanguard',
      name: 'Dragonic Overlord',
      attributes: {'grade': '3', 'cardType': 'normal'},
    );
    store.addToDeck(deck.id, card.id, 'main', quantity: 4);

    await backfillLibraryFromCatalog(store, seededCatalog());

    final view = store.viewOf(store.deckById(deck.id)!);
    expect(view.items.single.card.attributes['series'], 'dov');
    expect(view.zoneCount('main'), 4, reason: 'the deck entry is unchanged');
  });

  test('an edit you made is never overwritten', () async {
    final store = await loadedStore();
    final card = store.saveCard(
      gameId: 'vanguard',
      name: 'Dragonic Overlord',
      attributes: {
        'grade': '2', // deliberately different from the catalog
        'cardType': 'normal',
        'notes': 'my combo note',
      },
    );

    await backfillLibraryFromCatalog(store, seededCatalog());

    final updated = store.cardById(card.id)!;
    expect(updated.attributes['grade'], '2', reason: 'your value wins');
    expect(updated.attributes['notes'], 'my combo note');
    // The blanks are still filled.
    expect(updated.attributes['series'], 'dov');
  });

  test('a trigger you answered for is kept', () async {
    final store = await loadedStore();
    final card = store.saveCard(
      gameId: 'vanguard',
      name: 'Blitz Assault Dragon',
      attributes: {'grade': '0', 'cardType': 'trigger', 'trigger': 'critical'},
    );

    await backfillLibraryFromCatalog(store, seededCatalog());

    final updated = store.cardById(card.id)!;
    expect(updated.attributes['trigger'], 'critical');
    expect(updated.attributes['series'], 'd');
  });

  test('a card matched by number is not confused with another name', () async {
    final store = await loadedStore();
    // The user renamed the card but kept the number.
    final card = store.saveCard(
      gameId: 'vanguard',
      name: 'My Nickname For It',
      attributes: {'cardNo': 'D-BT02/001EN'},
    );

    await backfillLibraryFromCatalog(store, seededCatalog());

    final updated = store.cardById(card.id)!;
    expect(updated.name, 'My Nickname For It', reason: 'names are never taken');
    expect(updated.attributes['series'], 'dov');
  });

  test('a card the catalog does not know is left alone', () async {
    final store = await loadedStore();
    final card = store.saveCard(
      gameId: 'vanguard',
      name: 'Something I Made Up',
      attributes: {'grade': '1', 'cardType': 'normal'},
    );

    final filled = await backfillLibraryFromCatalog(store, seededCatalog());

    expect(filled, 0);
    expect(store.cardById(card.id)!.attributes, {
      'grade': '1',
      'cardType': 'normal',
    });
  });

  test('cards of another game are never touched', () async {
    final store = await loadedStore();
    final card = store.saveCard(
      gameId: 'some-other-game',
      name: 'Dragonic Overlord',
      attributes: {'grade': '3'},
    );

    final filled = await backfillLibraryFromCatalog(store, seededCatalog());

    expect(filled, 0);
    expect(store.cardById(card.id)!.attributes['series'], isNull);
  });

  test('it runs once, then never reads the catalog again', () async {
    final store = await loadedStore();
    store.saveCard(
      gameId: 'vanguard',
      name: 'Dragonic Overlord',
      attributes: {'grade': '3'},
    );

    expect(store.needsCardBackfill, isTrue);
    expect(await backfillLibraryFromCatalog(store, seededCatalog()), 1);
    expect(store.needsCardBackfill, isFalse);
    // A second run does nothing, even though a card still lacks a series
    // because the catalog has never heard of it.
    expect(await backfillLibraryFromCatalog(store, seededCatalog()), 0);
  });

  test('the repair survives a restart', () async {
    final store = await loadedStore();
    store.saveCard(
      gameId: 'vanguard',
      name: 'Dragonic Overlord',
      attributes: {'grade': '3'},
    );
    await backfillLibraryFromCatalog(store, seededCatalog());

    final reloaded = await loadedStore();
    expect(reloaded.cards.single.attributes['series'], 'dov');
    expect(reloaded.needsCardBackfill, isFalse);
  });

  test('an empty library costs nothing and still marks itself done', () async {
    final store = await loadedStore();
    final catalog = seededCatalog();

    expect(await backfillLibraryFromCatalog(store, catalog), 0);
    expect(store.needsCardBackfill, isFalse);
  });

  test('an unreadable catalog is retried next launch', () async {
    final store = await loadedStore();
    store.saveCard(
      gameId: 'vanguard',
      name: 'Dragonic Overlord',
      attributes: {'grade': '3'},
    );

    // An empty catalog is what a missing or malformed asset looks like.
    expect(await backfillLibraryFromCatalog(store, seededCatalog([])), 0);
    expect(
      store.needsCardBackfill,
      isTrue,
      reason: 'do not mark a repair done that never happened',
    );

    // With a working catalog it repairs as normal.
    expect(await backfillLibraryFromCatalog(store, seededCatalog()), 1);
    expect(store.needsCardBackfill, isFalse);
  });

  test('a corrected era replaces what an older build wrote', () async {
    // The era is worked out by the app, not entered by hand, so unlike every
    // other attribute the catalogue's answer wins -- otherwise a card dated
    // wrongly by an older build would stay wrong forever.
    final store = DeckStore();
    await store.load();
    store.saveCard(
      gameId: 'vanguard',
      name: 'Stealth Dragon, Gengan',
      attributes: {'cardNo': 'BSF2021/VGS01EN', 'series': 'd', 'grade': '2'},
    );

    final catalog = CardCatalog()
      ..seed(_asset, [
        CatalogCard.fromJson({
          'n': 'Stealth Dragon, Gengan',
          'no': 'BSF2021/VGS01EN',
          'g': 2,
          'sr': 'v',
        }),
      ]);
    await backfillLibraryFromCatalog(store, catalog);

    expect(store.cards.single.attributes['series'], 'v');
  });

  test('an era that can no longer be established is dropped', () async {
    final store = DeckStore();
    await store.load();
    store.saveCard(
      gameId: 'vanguard',
      name: 'Old Promo',
      attributes: {'cardNo': 'PR/0001EN', 'series': 'd', 'grade': '2'},
    );

    final catalog = CardCatalog()
      ..seed(_asset, [
        CatalogCard.fromJson({
          'n': 'Old Promo',
          'no': 'PR/0001EN',
          'g': 2,
          'sp': 'gopv',
        }),
      ]);
    await backfillLibraryFromCatalog(store, catalog);

    final card = store.cards.single;
    expect(card.attributes['series'], isNull);
    expect(card.attributes['possibleSeries'], 'gopv');
  });

  test('a card saved under another printing is still repaired', () async {
    // The catalogue shows one of a card's printings. A card saved under any
    // other one matched nothing here and was never filled in.
    final store = DeckStore();
    await store.load();
    store.saveCard(
      gameId: 'vanguard',
      name: 'Blaster Blade',
      attributes: {'cardNo': 'DZ-SS13/002EN'},
    );

    final catalog = CardCatalog()
      ..seed(_asset, [
        CatalogCard.fromJson({
          'n': 'Blaster Blade',
          'no': 'D-BT05/005EN',
          'no2': ['DZ-SS13/002EN'],
          'i': 'blaster-blade-d-bt05.jpg',
          'i2': {'DZ-SS13/002EN': 'blaster-blade-dz-ss13.jpg'},
          'g': 2,
          'p': 10000,
          'sr': 'dv',
        }),
      ]);
    await backfillLibraryFromCatalog(store, catalog);

    final card = store.cards.single;
    expect(card.attributes['grade'], '2');
    expect(card.attributes['power'], '10000');
    expect(
      card.attributes['cardNo'],
      'DZ-SS13/002EN',
      reason: 'the printing the user has is not overwritten',
    );
    // Not D-BT05's art, which the catalogue shows for this card by default --
    // the user's own printing's art.
    expect(card.attributes['imageUrl'], 'blaster-blade-dz-ss13.jpg');
  });
}
