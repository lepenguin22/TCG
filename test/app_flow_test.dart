import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tcg_decks/main.dart';
import 'package:tcg_decks/store/deck_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Scrolls the target into view before tapping, so tests do not depend on
  /// where a control happens to land in the test viewport. A lazy list may not
  /// have built the target yet, hence the scroll before the finder resolves.
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      // Scroll the page's own list, not the scrollable inside a text field.
      await tester.dragUntilVisible(
        finder,
        find.byType(ListView).first,
        const Offset(0, -220),
      );
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<DeckStore> pumpApp(WidgetTester tester) async {
    final store = DeckStore();
    await store.load();
    await tester.pumpWidget(TcgDecksApp(store: store));
    await tester.pumpAndSettle();
    return store;
  }

  testWidgets('an empty install explains what to do', (tester) async {
    await pumpApp(tester);

    expect(find.text('My Decks'), findsOneWidget);
    expect(find.text('No decks yet'), findsOneWidget);
    expect(find.text('Create a deck'), findsOneWidget);
  });

  testWidgets('building a deck from scratch shows it on the deck screen', (
    tester,
  ) async {
    final store = await pumpApp(tester);

    // Create the deck.
    await tester.tap(find.widgetWithText(FloatingActionButton, 'New deck'));
    await tester.pumpAndSettle();
    expect(find.text('New Deck'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Dragon Empire');
    await tester.pumpAndSettle();
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Create deck'));

    // We land on the deck, which starts illegal and says so.
    expect(find.text('Dragon Empire'), findsWidgets);
    expect(find.text('Ride Deck'), findsWidgets);
    expect(find.text('Main Deck'), findsWidgets);
    expect(
      find.textContaining('empty', findRichText: true),
      findsWidgets,
      reason: 'an empty deck should be flagged by the rules panel',
    );

    // Add a card to the main deck.
    await tapVisible(
      tester,
      find.widgetWithText(OutlinedButton, 'Add to Main'),
    );
    expect(find.text('Add to Main Deck'), findsOneWidget);
    expect(find.text('Your card library is empty'), findsOneWidget);

    await tapVisible(
      tester,
      find.widgetWithText(FilledButton, 'Create a card'),
    );
    expect(find.text('New Card'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField).first,
      'Dragontree Maiden, Sharlka',
    );
    await tester.pumpAndSettle();
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Save card'));

    // The card is in the library and one copy went into the deck.
    expect(store.cards, hasLength(1));
    expect(store.decks.single.entries.single.quantity, 1);

    // Back on the deck screen the card is listed.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Dragontree Maiden, Sharlka'), findsOneWidget);
    expect(find.text('GRADE 0'), findsOneWidget);
  });

  testWidgets('the quantity stepper edits the deck', (tester) async {
    final store = await pumpApp(tester);
    final deck = store.createDeck(name: 'Stepper deck');
    final card = store.saveCard(
      gameId: 'vanguard',
      name: 'Test Body',
      attributes: {'grade': '2', 'cardType': 'normal'},
    );
    store.addToDeck(deck.id, card.id, 'main', quantity: 2);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Stepper deck'));
    await tester.pumpAndSettle();

    await tapVisible(tester, find.byTooltip('Add one Test Body'));
    expect(store.decks.single.entries.single.quantity, 3);

    await tapVisible(tester, find.byTooltip('Remove one Test Body'));
    await tapVisible(tester, find.byTooltip('Remove one Test Body'));
    expect(store.decks.single.entries.single.quantity, 1);
  });

  testWidgets('a deck that breaks the rules says exactly why', (tester) async {
    final store = await pumpApp(tester);
    final deck = store.createDeck(name: 'Illegal deck');
    final card = store.saveCard(
      gameId: 'vanguard',
      name: 'Too Many',
      attributes: {'grade': '2', 'cardType': 'normal'},
    );
    store.addToDeck(deck.id, card.id, 'main', quantity: 5);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Illegal deck'));
    await tester.pumpAndSettle();

    // Only the first three issues show until the list is expanded.
    expect(find.textContaining('must hold exactly 50'), findsOneWidget);
    await tapVisible(tester, find.textContaining('Show all'));
    expect(find.textContaining('appears 5 times'), findsOneWidget);
  });

  testWidgets('the deck menu opens and can pin a deck', (tester) async {
    final store = await pumpApp(tester);
    store.createDeck(name: 'Menu deck');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Menu deck'));
    await tester.pumpAndSettle();

    await tapVisible(tester, find.byTooltip('Deck actions'));
    expect(find.text('Copy as text'), findsOneWidget);
    expect(find.text('Duplicate deck'), findsOneWidget);
    expect(find.text('Delete deck'), findsOneWidget);

    await tapVisible(tester, find.text('Pin to top'));
    expect(store.decks.single.favorite, isTrue);
  });
}
