import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tcg_decks/games/card_catalog.dart';
import 'package:tcg_decks/main.dart';
import 'package:tcg_decks/store/deck_store.dart';

/// What a desktop window does to a layout built for a phone.
///
/// The app is the same app on Windows as on Android -- one codebase, one set
/// of screens -- so the only thing a desktop needs is somewhere for the extra
/// width to go. These pin that down from both ends: the width is capped where
/// there is too much of it, and nothing changes where there is not.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final store = DeckStore();
    await store.load();
    final catalog = CardCatalog()..seed('assets/cards/vanguard.json', const []);
    await tester.pumpWidget(TcgDecksApp(store: store, catalog: catalog));
    await tester.pumpAndSettle();
  }

  double contentWidth(WidgetTester tester) =>
      tester.getSize(find.byType(Scaffold).first).width;

  testWidgets('a desktop window holds the app to a readable column', (
    tester,
  ) async {
    // A maximised window on an ordinary monitor.
    await pumpAt(tester, const Size(1920, 1080));

    expect(contentWidth(tester), 1100);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a window narrower than the cap is filled', (tester) async {
    await pumpAt(tester, const Size(900, 960));

    expect(
      contentWidth(tester),
      900,
      reason: 'the window the app opens at is inside the cap',
    );
  });

  testWidgets('a phone is untouched by any of it', (tester) async {
    await pumpAt(tester, const Size(430, 932));

    expect(contentWidth(tester), 430);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the app still works at a desktop size', (tester) async {
    await pumpAt(tester, const Size(1920, 1080));

    // The deck list is the first thing on screen, and a new deck can be
    // started from it, which is as far as this needs to go: the rest of the
    // screens are covered at four sizes by the other layout tests.
    expect(find.text('My Decks'), findsOneWidget);
    await tester.tap(find.widgetWithText(FloatingActionButton, 'New deck'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
