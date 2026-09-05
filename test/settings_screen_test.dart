import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tcg_decks/screens/settings_screen.dart';
import 'package:tcg_decks/store/deck_store.dart';
import 'package:tcg_decks/theme.dart';

/// The settings screen names the build it is, which is the only place in the
/// app that answers "does the copy on my phone have the fix in it?".
void main() {
  testWidgets('the settings screen names the build', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = DeckStore();
    await store.load();

    await tester.pumpWidget(
      ChangeNotifierProvider<DeckStore>.value(
        value: store,
        child: MaterialApp(theme: buildTheme(), home: const SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Nothing passed APP_VERSION in, so it says so rather than lying about a
    // release number. A release build shows its tag here instead.
    await tester.scrollUntilVisible(find.text('Local build'), 200);
    expect(find.text('Local build'), findsOneWidget);
  });
}
