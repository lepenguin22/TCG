import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tcg_decks/games/card_catalog.dart';
import 'package:tcg_decks/games/vanguard/start_decks.dart';
import 'package:tcg_decks/games/vanguard/vanguard_data.dart';
import 'package:tcg_decks/games/vanguard/vanguard_game.dart';
import 'package:tcg_decks/main.dart';
import 'package:tcg_decks/store/deck_store.dart';
import 'package:tcg_decks/store/decklog_import.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final start in startDecks) {
    test('${start.name} is a whole, legal deck', () async {
      // The real card database, so every number has to be in it.
      const game = VanguardGame();
      final path = game.catalogAsset!;
      final catalog = CardCatalog()
        ..seed(path, parseCatalog(File(path).readAsStringSync()));
      final store = DeckStore();
      await store.load();

      final result = await importDecklogDeck(
        store,
        catalog,
        start.toDecklog(),
        description: start.description,
      );

      expect(result.unmatched, isEmpty);
      expect(result.zoneCounts[zoneMain], 50);
      expect(result.zoneCounts[zoneRide], 5);
      expect(result.deck.description, start.description);

      final view = store.viewOf(result.deck);
      // Not an error, and not a warning either: the triggers arrive with
      // their icons, so the heal and over limits are checked too.
      expect([for (final issue in game.validate(view)) issue.message], isEmpty);

      // No card past four copies, the ride deck's counted in.
      final copies = <String, int>{};
      for (final card in start.cards) {
        copies[card.number] = (copies[card.number] ?? 0) + card.quantity;
      }
      expect(copies.values.where((n) => n > 4), isEmpty);
    });
  }

  testWidgets('My Decks adds a start deck in one tap', (tester) async {
    final store = DeckStore();
    await store.load();
    // Read on the test's own clock: the real database is large.
    const path = 'assets/cards/vanguard.json';
    final cards = await tester.runAsync(
      () async => parseCatalog(await File(path).readAsString()),
    );
    final catalog = CardCatalog()..seed(path, cards!);
    await tester.pumpWidget(TcgDecksApp(store: store, catalog: catalog));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('start-decks')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('start-deck-dz-ss19')));
    await tester.pumpAndSettle();

    expect(store.decks, hasLength(1));
    final deck = store.decks.single;
    expect(deck.name, 'Ghost Meets Gal! (DZ-SS19)');
    expect(store.viewOf(deck).zoneCount(zoneMain), 50);
    expect(store.viewOf(deck).zoneCount(zoneRide), 5);
  });
}
