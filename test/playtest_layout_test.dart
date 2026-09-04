import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tcg_decks/screens/playtest_screen.dart';
import 'package:tcg_decks/store/deck_store.dart';
import 'package:tcg_decks/theme.dart';

import 'playtest_engine_test.dart' show buildDeck;

/// The board is the densest screen in the app -- twelve circles, two damage
/// rows, a hand and a control bar, all on a phone. It is also the screen where
/// running off the edge would hide something the player needs to tap, so every
/// size it might be opened at is played through here rather than eyeballed.
void main() {
  const sizes = <String, Size>{
    'a small phone': Size(360, 640),
    'a common phone': Size(390, 844),
    'a large phone': Size(430, 932),
    'a tablet': Size(800, 1280),
  };

  sizes.forEach((description, size) {
    testWidgets('the board fits $description', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final (store, deck) = await buildDeck();
      await tester.pumpWidget(
        ChangeNotifierProvider<DeckStore>.value(
          value: store,
          child: MaterialApp(
            theme: buildTheme(),
            home: PlaytestScreen(yourDeck: deck, opponentDeck: deck),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'the opening hand');

      await tester.tap(find.text('Keep this hand'));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'the board');

      // Play on far enough to lay out the attacking and guarding states too,
      // which put the most into the strip between the two boards.
      final step = RegExp(
        r'^(Next|End turn|Take it|Continue|Resolve|Drive check)$',
      );
      for (var i = 0; i < 8; i += 1) {
        final button = find.textContaining(step);
        if (button.evaluate().isEmpty) break;
        await tester.tap(button.first);
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'after step $i');
      }
    });
  });
}
