import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tcg_decks/games/vanguard/vanguard_data.dart';
import 'package:tcg_decks/games/vanguard/vanguard_game.dart';
import 'package:tcg_decks/screens/trigger_icons_screen.dart';
import 'package:tcg_decks/store/deck_store.dart';
import 'package:tcg_decks/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// A deck of trigger units with no icons, as an import leaves it.
  Future<(DeckStore, String)> deckWithTriggers(int distinct) async {
    final store = DeckStore();
    await store.load();
    final deck = store.createDeck(
      name: 'Imported',
      gameId: 'vanguard',
      formatId: formatStandard,
      description: '',
    );
    for (var i = 0; i < distinct; i += 1) {
      final card = store.ensureCard(
        gameId: 'vanguard',
        name: 'Trigger $i',
        attributes: {'grade': '0', 'cardType': 'trigger', 'series': 'd'},
      );
      store.addToDeck(deck.id, card.id, zoneMain, quantity: 4);
    }
    return (store, deck.id);
  }

  Future<void> pump(WidgetTester tester, DeckStore store, String deckId) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<DeckStore>.value(
        value: store,
        child: MaterialApp(
          theme: buildTheme(),
          home: TriggerIconsScreen(deckId: deckId),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('every trigger unit in the deck gets a row', (tester) async {
    final (store, deckId) = await deckWithTriggers(2);
    await pump(tester, store, deckId);

    // One row per distinct card, not per copy: 2 rows, not 8 cards' worth.
    expect(find.text('Trigger 0'), findsOneWidget);
    expect(find.text('Trigger 1'), findsOneWidget);
    expect(find.textContaining('2 still to set'), findsOneWidget);
  });

  testWidgets('answering one sets it on the library card', (tester) async {
    final (store, deckId) = await deckWithTriggers(1);
    await pump(tester, store, deckId);

    await tester.tap(find.text('Heal'));
    await tester.pumpAndSettle();

    expect(store.cards.single.attributes['trigger'], 'heal');
    // And the count of what is left updates as you go.
    expect(find.textContaining('still to set'), findsNothing);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('an answer makes the rules check the heal limit', (tester) async {
    final (store, deckId) = await deckWithTriggers(2);
    await pump(tester, store, deckId);

    // Two cards, four copies each, both heal: over the limit of four.
    await tester.tap(find.text('Heal').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Heal').last);
    await tester.pumpAndSettle();

    const game = VanguardGame();
    final issues = game.validate(store.viewOf(store.decks.single));
    expect(
      issues.map((issue) => issue.message),
      contains(contains('8 heal triggers')),
    );
    expect(
      issues.map((issue) => issue.message),
      isNot(contains(contains('no trigger set'))),
    );
  });

  testWidgets('a deck with no trigger units says so', (tester) async {
    final store = DeckStore();
    await store.load();
    final deck = store.createDeck(
      name: 'Empty',
      gameId: 'vanguard',
      formatId: formatStandard,
      description: '',
    );
    await pump(tester, store, deck.id);
    expect(find.textContaining('no trigger units'), findsOneWidget);
  });
}
