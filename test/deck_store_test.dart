import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tcg_decks/games/vanguard/vanguard_data.dart';
import 'package:tcg_decks/store/deck_store.dart';

Future<DeckStore> loadedStore() async {
  final store = DeckStore();
  await store.load();
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a new deck starts empty and on the game default format', () async {
    final store = await loadedStore();
    final deck = store.createDeck(name: '  Dragon Empire  ');

    expect(store.decks, hasLength(1));
    expect(deck.name, 'Dragon Empire');
    expect(deck.formatId, formatStandard);
    expect(deck.entries, isEmpty);
  });

  test('adding the same card twice stacks the quantity', () async {
    final store = await loadedStore();
    final deck = store.createDeck(name: 'Deck');
    final card = store.saveCard(
      gameId: 'vanguard',
      name: 'Crit',
      attributes: {'grade': '0', 'cardType': 'trigger', 'trigger': 'critical'},
    );

    store.addToDeck(deck.id, card.id, zoneMain);
    store.addToDeck(deck.id, card.id, zoneMain, quantity: 3);

    expect(store.deckById(deck.id)!.entries.single.quantity, 4);
  });

  test('the same card in two zones is two entries', () async {
    final store = await loadedStore();
    final deck = store.createDeck(name: 'Deck');
    final card = store.saveCard(
      gameId: 'vanguard',
      name: 'Grade 1',
      attributes: {'grade': '1', 'cardType': 'normal'},
    );

    store.addToDeck(deck.id, card.id, zoneMain, quantity: 4);
    store.addToDeck(deck.id, card.id, zoneRide);

    final view = store.viewOf(store.deckById(deck.id)!);
    expect(view.zoneCount(zoneMain), 4);
    expect(view.zoneCount(zoneRide), 1);
    expect(view.totalCount, 5);
  });

  test('setting a quantity to zero removes the card from the deck', () async {
    final store = await loadedStore();
    final deck = store.createDeck(name: 'Deck');
    final card = store.saveCard(
      gameId: 'vanguard',
      name: 'Body',
      attributes: {'grade': '2', 'cardType': 'normal'},
    );

    store.addToDeck(deck.id, card.id, zoneMain, quantity: 2);
    store.setQuantity(deck.id, card.id, zoneMain, 0);

    expect(store.deckById(deck.id)!.entries, isEmpty);
    // The card itself stays in the library for reuse.
    expect(store.cards, hasLength(1));
  });

  test(
    'moving a card merges into an existing stack in the target zone',
    () async {
      final store = await loadedStore();
      final deck = store.createDeck(name: 'Deck');
      final card = store.saveCard(
        gameId: 'vanguard',
        name: 'Body',
        attributes: {'grade': '2', 'cardType': 'normal'},
      );

      store.addToDeck(deck.id, card.id, zoneMain, quantity: 2);
      store.addToDeck(deck.id, card.id, zoneRide, quantity: 1);
      store.moveEntry(deck.id, card.id, zoneRide, zoneMain);

      final entries = store.deckById(deck.id)!.entries;
      expect(entries, hasLength(1));
      expect(entries.single.zoneId, zoneMain);
      expect(entries.single.quantity, 3);
    },
  );

  test('deleting a card pulls it out of every deck', () async {
    final store = await loadedStore();
    final first = store.createDeck(name: 'First');
    final second = store.createDeck(name: 'Second');
    final card = store.saveCard(
      gameId: 'vanguard',
      name: 'Shared',
      attributes: {'grade': '3', 'cardType': 'normal'},
    );

    store.addToDeck(first.id, card.id, zoneMain, quantity: 4);
    store.addToDeck(second.id, card.id, zoneMain, quantity: 2);
    store.deleteCard(card.id);

    expect(store.cards, isEmpty);
    expect(store.deckById(first.id)!.entries, isEmpty);
    expect(store.deckById(second.id)!.entries, isEmpty);
  });

  test('a duplicated deck copies the cards but not the pin', () async {
    final store = await loadedStore();
    final deck = store.createDeck(name: 'Original');
    final card = store.saveCard(
      gameId: 'vanguard',
      name: 'Body',
      attributes: {'grade': '2', 'cardType': 'normal'},
    );
    store.addToDeck(deck.id, card.id, zoneMain, quantity: 4);
    store.toggleFavorite(deck.id);

    final copy = store.duplicateDeck(deck.id)!;

    expect(copy.name, 'Original (copy)');
    expect(copy.favorite, isFalse);
    expect(copy.entries.single.quantity, 4);
    // Editing the copy must not touch the original.
    store.setQuantity(copy.id, card.id, zoneMain, 1);
    expect(store.deckById(deck.id)!.entries.single.quantity, 4);
  });

  test('decks and cards survive a reload', () async {
    final store = await loadedStore();
    final deck = store.createDeck(name: 'Persisted', description: 'notes');
    final card = store.saveCard(
      gameId: 'vanguard',
      name: 'Dragontree Maiden',
      attributes: {'grade': '3', 'cardType': 'normal', 'nation': 'stoicheia'},
    );
    store.addToDeck(deck.id, card.id, zoneMain, quantity: 4);

    final reloaded = await loadedStore();

    expect(reloaded.decks, hasLength(1));
    expect(reloaded.decks.single.name, 'Persisted');
    expect(reloaded.decks.single.description, 'notes');
    expect(reloaded.cards.single.name, 'Dragontree Maiden');
    expect(reloaded.cards.single.attributes['nation'], 'stoicheia');
    expect(reloaded.viewOf(reloaded.decks.single).zoneCount(zoneMain), 4);
  });

  test('a backup round trips into an empty install', () async {
    final source = await loadedStore();
    final deck = source.createDeck(name: 'Exported');
    final card = source.saveCard(
      gameId: 'vanguard',
      name: 'Body',
      attributes: {'grade': '2', 'cardType': 'normal'},
    );
    source.addToDeck(deck.id, card.id, zoneMain, quantity: 3);
    final payload = source.exportBackup();

    SharedPreferences.setMockInitialValues({});
    final target = await loadedStore();
    final result = target.importBackup(payload);

    expect(result.decks, 1);
    expect(result.cards, 1);
    expect(target.viewOf(target.decks.single).zoneCount(zoneMain), 3);
  });

  test('importing the same backup twice does not duplicate anything', () async {
    final store = await loadedStore();
    store.createDeck(name: 'Deck');
    final payload = store.exportBackup();

    final result = store.importBackup(payload);

    expect(result.decks, 0);
    expect(store.decks, hasLength(1));
  });

  test('editing a card in the library updates it everywhere', () async {
    final store = await loadedStore();
    final deck = store.createDeck(name: 'Deck');
    final card = store.saveCard(
      gameId: 'vanguard',
      name: 'Typo Name',
      attributes: {'grade': '2', 'cardType': 'normal'},
    );
    store.addToDeck(deck.id, card.id, zoneMain);

    store.saveCard(
      id: card.id,
      gameId: 'vanguard',
      name: 'Fixed Name',
      attributes: {'grade': '3', 'cardType': 'normal'},
    );

    expect(store.cards, hasLength(1));
    final view = store.viewOf(store.deckById(deck.id)!);
    expect(view.items.single.card.name, 'Fixed Name');
    expect(view.items.single.card.attributes['grade'], '3');
  });
}
