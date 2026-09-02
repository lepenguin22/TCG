import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tcg_decks/games/card_catalog.dart';
import 'package:tcg_decks/games/vanguard/vanguard_game.dart';
import 'package:tcg_decks/main.dart';
import 'package:tcg_decks/store/deck_store.dart';

const _asset = 'assets/cards/vanguard.json';

const _imageBase =
    'https://en.cf-vanguard.com/wordpress/wp-content/images/cardlist/';

CatalogCard _card(String name, Map<String, Object> extra) =>
    CatalogCard.fromJson({'n': name, ...extra}, imageBase: _imageBase);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Boots the app with a small stand-in catalog, so the tests stay fast and
  /// do not depend on the contents of the real asset.
  Future<(DeckStore, CardCatalog)> pumpApp(WidgetTester tester) async {
    final store = DeckStore();
    await store.load();
    final catalog = CardCatalog()
      ..seed(_asset, [
        _card('Dragonic Overlord', {
          'g': 3,
          't': 'normal',
          'na': 'dragon-empire',
          'p': 13000,
          'no': 'D-BT02/SP01EN',
          'e':
              '[CONT](VC/RC):During the battle this unit attacked a '
              'rear-guard, your opponent cannot call cards from their hand '
              'to (GC).',
          'i': 'dbt02/dbt02_sp01.png',
        }),
        _card('Dragonic Overlord the End', {
          'g': 3,
          't': 'normal',
          'na': 'dragon-empire',
          'p': 13000,
        }),
        _card('Embodiment of Armor, Bahr', {
          'g': 1,
          't': 'normal',
          'na': 'dragon-empire',
          'p': 8000,
        }),
        _card('Blitz Assault Dragon', {
          'g': 0,
          't': 'trigger',
          'na': 'dragon-empire',
          'p': 5000,
          's': 15000,
        }),
        _card('Light Dragon Deity of Honors, Amartinoa', {
          'g': 0,
          't': 'trigger',
          'tr': 'over',
          'na': 'keter-sanctuary',
          's': 50000,
        }),
      ]);

    await tester.pumpWidget(TcgDecksApp(store: store, catalog: catalog));
    await tester.pumpAndSettle();
    return (store, catalog);
  }

  Future<void> openAddCards(WidgetTester tester, DeckStore store) async {
    store.createDeck(name: 'Test deck');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test deck'));
    await tester.pumpAndSettle();

    final addButton = find.widgetWithText(OutlinedButton, 'Add to Main');
    await tester.ensureVisible(addButton);
    await tester.pumpAndSettle();
    await tester.tap(addButton);
    await tester.pumpAndSettle();
  }

  testWidgets('the card database is the default source', (tester) async {
    final (store, _) = await pumpApp(tester);
    await openAddCards(tester, store);

    expect(find.text('Add to Main Deck'), findsOneWidget);
    expect(find.text('Card database'), findsOneWidget);
    expect(find.text('My library'), findsOneWidget);
    // Nothing is listed until you search, but the count invites you to.
    expect(find.textContaining('5 cards ready'), findsOneWidget);
  });

  testWidgets('searching finds real cards and ranks them', (tester) async {
    final (store, _) = await pumpApp(tester);
    await openAddCards(tester, store);

    await tester.enterText(find.byType(TextField).first, 'dragonic overlord');
    await tester.pumpAndSettle();

    expect(find.text('Dragonic Overlord'), findsOneWidget);
    expect(find.text('Dragonic Overlord the End'), findsOneWidget);
    expect(find.text('Embodiment of Armor, Bahr'), findsNothing);
  });

  testWidgets('adding a card fills in its details with no typing', (
    tester,
  ) async {
    final (store, _) = await pumpApp(tester);
    await openAddCards(tester, store);

    await tester.enterText(find.byType(TextField).first, 'bahr');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Embodiment of Armor, Bahr'));
    await tester.pumpAndSettle();

    // One library card, created from the catalogue, already filled in.
    expect(store.cards, hasLength(1));
    final card = store.cards.single;
    expect(card.name, 'Embodiment of Armor, Bahr');
    expect(card.attributes['grade'], '1');
    expect(card.attributes['cardType'], 'normal');
    expect(card.attributes['nation'], 'dragon-empire');
    expect(card.attributes['power'], '8000');

    // And it is in the deck.
    expect(store.decks.single.entries.single.cardId, card.id);
    expect(store.decks.single.entries.single.quantity, 1);
  });

  testWidgets('a trigger unit asks which trigger, once', (tester) async {
    final (store, _) = await pumpApp(tester);
    await openAddCards(tester, store);

    await tester.enterText(find.byType(TextField).first, 'blitz assault');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blitz Assault Dragon'));
    await tester.pumpAndSettle();

    // The catalogue cannot supply the trigger icon, so the app asks.
    expect(find.textContaining('Which trigger?'), findsOneWidget);
    expect(store.cards, isEmpty, reason: 'nothing saved until answered');

    await tester.tap(find.text('Critical'));
    await tester.pumpAndSettle();

    expect(store.cards.single.attributes['trigger'], 'critical');
    expect(store.decks.single.entries.single.quantity, 1);

    // Adding it again reuses the library card and does not ask twice.
    await tester.tap(find.text('Blitz Assault Dragon'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Which trigger?'), findsNothing);
    expect(store.cards, hasLength(1));
    expect(store.decks.single.entries.single.quantity, 2);
  });

  testWidgets('dismissing the trigger prompt adds nothing', (tester) async {
    final (store, _) = await pumpApp(tester);
    await openAddCards(tester, store);

    await tester.enterText(find.byType(TextField).first, 'blitz assault');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blitz Assault Dragon'));
    await tester.pumpAndSettle();

    // Tap the barrier to dismiss the sheet.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(store.cards, isEmpty);
    expect(store.decks.single.entries, isEmpty);
  });

  testWidgets('an over trigger is known already and is not asked about', (
    tester,
  ) async {
    final (store, _) = await pumpApp(tester);
    await openAddCards(tester, store);

    await tester.enterText(find.byType(TextField).first, 'amartinoa');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Amartinoa'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Which trigger?'), findsNothing);
    expect(store.cards.single.attributes['trigger'], 'over');
  });

  testWidgets('cards added from the database show up in My library', (
    tester,
  ) async {
    final (store, _) = await pumpApp(tester);
    await openAddCards(tester, store);

    await tester.enterText(find.byType(TextField).first, 'bahr');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Embodiment of Armor, Bahr'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('My library'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pumpAndSettle();

    expect(find.text('Embodiment of Armor, Bahr'), findsOneWidget);
  });

  testWidgets('the card sheet shows the image and the abilities', (
    tester,
  ) async {
    final (store, _) = await pumpApp(tester);
    await openAddCards(tester, store);

    await tester.enterText(find.byType(TextField).first, 'dragonic overlord');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('View card').first);
    await tester.pumpAndSettle();

    // The sheet leads with the image and the card's identity.
    expect(find.text('Dragonic Overlord'), findsWidgets);
    expect(find.text('D-BT02/SP01EN'), findsWidgets);

    // The image is requested from the official card list.
    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage).last,
    );
    expect(image.imageUrl, '${_imageBase}dbt02/dbt02_sp01.png');

    // The abilities sit below the image, so scroll the sheet to them.
    await tester.dragUntilVisible(
      find.text('ABILITIES'),
      find.byType(ListView).last,
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('cannot call cards from their hand'),
      findsOneWidget,
    );
  });

  testWidgets('the card sheet can add the card to the deck', (tester) async {
    final (store, _) = await pumpApp(tester);
    await openAddCards(tester, store);

    await tester.enterText(find.byType(TextField).first, 'dragonic overlord');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('View card').first);
    await tester.pumpAndSettle();

    final addButton = find.widgetWithText(FilledButton, 'Add to deck');
    await tester.dragUntilVisible(
      addButton,
      find.byType(ListView).last,
      const Offset(0, -150),
    );
    await tester.pumpAndSettle();
    await tester.tap(addButton);
    await tester.pumpAndSettle();

    expect(store.decks.single.entries.single.quantity, 1);
    expect(store.cards.single.name, 'Dragonic Overlord');
  });

  testWidgets('abilities and image are kept on the library card', (
    tester,
  ) async {
    final (store, _) = await pumpApp(tester);
    await openAddCards(tester, store);

    await tester.enterText(find.byType(TextField).first, 'dragonic overlord');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dragonic Overlord'));
    await tester.pumpAndSettle();

    final card = store.cards.single;
    expect(card.attributes['effect'], contains('[CONT](VC/RC)'));
    expect(card.attributes['imageUrl'], '${_imageBase}dbt02/dbt02_sp01.png');
  });

  testWidgets('a card with no image still renders', (tester) async {
    // Hand-entered cards have no image; the row must fall back quietly.
    final (store, _) = await pumpApp(tester);
    await openAddCards(tester, store);

    await tester.enterText(find.byType(TextField).first, 'bahr');
    await tester.pumpAndSettle();

    expect(find.text('Embodiment of Armor, Bahr'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a deck built from the database validates correctly', (
    tester,
  ) async {
    // The rules engine must read catalogue-sourced cards the same way it reads
    // hand-entered ones.
    final (store, _) = await pumpApp(tester);
    await openAddCards(tester, store);

    await tester.enterText(find.byType(TextField).first, 'bahr');
    await tester.pumpAndSettle();
    for (var i = 0; i < 5; i += 1) {
      await tester.tap(find.text('Embodiment of Armor, Bahr'));
      await tester.pumpAndSettle();
    }

    await tester.pageBack();
    await tester.pumpAndSettle();

    const game = VanguardGame();
    final issues = game.validate(store.viewOf(store.decks.single));
    expect(issues.map((i) => i.message), contains(contains('appears 5 times')));
  });
}
