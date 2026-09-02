import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tcg_decks/games/card_catalog.dart';
import 'package:tcg_decks/games/vanguard/vanguard_data.dart';
import 'package:tcg_decks/import/decklog.dart';
import 'package:tcg_decks/screens/import_decklog_screen.dart';
import 'package:tcg_decks/store/deck_store.dart';
import 'package:tcg_decks/theme.dart';

const _asset = 'assets/cards/vanguard.json';

CatalogCard _card(String name, Map<String, Object> extra) =>
    CatalogCard.fromJson({'n': name, ...extra});

String _payload({String gameTitleId = '1', String? deckName}) => jsonEncode({
  'game_title_id': gameTitleId,
  'deck_name': ?deckName,
  'list': [
    {'name': 'Dragonic Overlord', 'num': 4, 'card_number': 'D-BT02/001EN'},
    {'name': 'Card From Next Week', 'num': 2},
  ],
  // The ride deck, in the section Deck Log actually files it under.
  'p_list': [
    {'name': 'Lizard Soldier, Conroe', 'num': 1, 'card_number': 'D-BT01/031EN'},
  ],
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<DeckStore> pumpScreen(
    WidgetTester tester, {
    required DecklogFetcher fetch,
  }) async {
    final store = DeckStore();
    await store.load();
    final catalog = CardCatalog()
      ..seed(_asset, [
        _card('Dragonic Overlord', {
          'g': 3,
          't': 'normal',
          'no': 'D-BT02/001EN',
          'sr': 'd',
        }),
        _card('Lizard Soldier, Conroe', {
          'g': 0,
          't': 'normal',
          'no': 'D-BT01/031EN',
          'sr': 'd',
        }),
      ]);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<DeckStore>.value(value: store),
          Provider<CardCatalog>.value(value: catalog),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          home: ImportDecklogScreen(fetch: fetch),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return store;
  }

  testWidgets('pasting a link imports the deck', (tester) async {
    final store = await pumpScreen(
      tester,
      fetch: (code) async {
        expect(code, '7K3X');
        return _payload(deckName: 'Overlord Turbo');
      },
    );

    await tester.enterText(
      find.byType(TextField).first,
      'https://decklog-en.bushiroad.com/view/7K3X',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Import deck'));
    await tester.pumpAndSettle();

    // The deck exists, with its cards in the right zones.
    expect(store.decks, hasLength(1));
    final view = store.viewOf(store.decks.single);
    expect(store.decks.single.name, 'Overlord Turbo');
    expect(view.zoneCount(zoneMain), 6);
    expect(view.zoneCount(zoneRide), 1);

    // And the screen says what happened, including what it could not match.
    expect(find.text('Overlord Turbo'), findsOneWidget);
    expect(find.textContaining('7 cards imported'), findsOneWidget);
    expect(find.textContaining('1 card not in the database'), findsOneWidget);
    expect(find.textContaining('Card From Next Week'), findsOneWidget);
    // The breakdown makes a zone that came out wrong visible straight away.
    expect(find.textContaining('6 in the Main Deck'), findsOneWidget);
    expect(find.textContaining('1 in the Ride Deck'), findsOneWidget);
  });

  testWidgets('a deck for another Bushiroad game is refused', (tester) async {
    final store = await pumpScreen(
      tester,
      fetch: (_) async => _payload(gameTitleId: '2'),
    );

    await tester.enterText(find.byType(TextField).first, '7K3X');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Import deck'));
    await tester.pumpAndSettle();

    expect(find.textContaining('other games'), findsOneWidget);
    expect(store.decks, isEmpty, reason: 'nothing half-imported');
  });

  testWidgets('a failed request explains itself and imports nothing', (
    tester,
  ) async {
    final store = await pumpScreen(
      tester,
      fetch: (_) async =>
          throw const DecklogException('Could not reach Deck Log.'),
    );

    await tester.enterText(find.byType(TextField).first, '7K3X');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Import deck'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not reach Deck Log'), findsOneWidget);
    expect(store.decks, isEmpty);
  });

  testWidgets('nonsense input is rejected without a request', (tester) async {
    final store = await pumpScreen(
      tester,
      fetch: (_) async => fail('should not have been requested'),
    );

    await tester.enterText(find.byType(TextField).first, 'hello there');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Import deck'));
    await tester.pumpAndSettle();

    expect(find.textContaining('not a Deck Log link'), findsOneWidget);
    expect(store.decks, isEmpty);
  });

  testWidgets('a deck with no separable ride deck says so', (tester) async {
    // One flat list: the ride deck cannot be told from the main deck, and the
    // screen has to say that rather than leave the user to notice.
    final flat = jsonEncode({
      'game_title_id': '1',
      'list': [
        {'name': 'Dragonic Overlord', 'num': 4, 'card_number': 'D-BT02/001EN'},
        {
          'name': 'Lizard Soldier, Conroe',
          'num': 1,
          'card_number': 'D-BT01/031EN',
        },
      ],
    });
    final store = await pumpScreen(tester, fetch: (_) async => flat);

    await tester.enterText(find.byType(TextField).first, '7K3X');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Import deck'));
    await tester.pumpAndSettle();

    expect(find.textContaining('single list'), findsOneWidget);
    expect(store.viewOf(store.decks.single).zoneCount(zoneMain), 5);
  });

  testWidgets('a pasted payload works when the request cannot be made', (
    tester,
  ) async {
    // The escape hatch: the endpoint's JSON, opened in a browser and pasted.
    final store = await pumpScreen(
      tester,
      fetch: (_) async => fail('should not have been requested'),
    );

    await tester.enterText(find.byType(TextField).first, _payload());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Import deck'));
    await tester.pumpAndSettle();

    expect(store.decks, hasLength(1));
    expect(store.viewOf(store.decks.single).totalCount, 7);
  });
}
