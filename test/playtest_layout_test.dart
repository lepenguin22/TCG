import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tcg_decks/screens/playtest_screen.dart';
import 'package:tcg_decks/store/deck_store.dart';
import 'package:tcg_decks/theme.dart';

import 'package:tcg_decks/playtest/playtest_controller.dart';

import 'playtest_engine_test.dart' show buildStrideDeck;

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

      // A deck with a G zone, which is the widest the zone rail ever gets.
      final (store, deck) = await buildStrideDeck();
      await tester.pumpWidget(
        ChangeNotifierProvider<DeckStore>.value(
          value: store,
          child: MaterialApp(
            theme: buildTheme(),
            home: PlaytestScreen(
              yourDeck: deck,
              opponentDeck: deck,
              // A fixed shuffle: these tests reach for particular
              // cards, and a board that is a different board every
              // run fails one time in a hundred for no reason.
              random: Random(7),
            ),
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
        r'^(Next|End turn|Take it|Continue|Resolve|Drive check ×\d+)$',
      );
      for (var i = 0; i < 8; i += 1) {
        final button = find.textContaining(step);
        if (button.evaluate().isEmpty) break;
        await tester.tap(button.first);
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'after step $i');
      }
    });

    testWidgets('the damage zone is whole on $description, removed pile and '
        'all', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final (store, deck) = await buildStrideDeck();
      await tester.pumpWidget(
        ChangeNotifierProvider<DeckStore>.value(
          value: store,
          child: MaterialApp(
            theme: buildTheme(),
            home: PlaytestScreen(
              yourDeck: deck,
              opponentDeck: deck,
              random: Random(7),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Keep this hand'));
      await tester.pump();

      // The board at its widest: a G zone, a removed pile and five damage.
      final game = Provider.of<PlaytestController>(
        tester.element(find.byType(Scaffold)),
        listen: false,
      );
      for (var i = 0; i < 5; i += 1) {
        game.you.damage.add(game.you.deck.removeLast());
      }
      game.you.removed.add(game.you.deck.removeLast());
      game.setEnergy(game.you, game.you.energy);
      await tester.pump();

      expect(find.text('Removed'), findsOneWidget, reason: 'the seventh pile');
      expect(find.textContaining('Damage 5/6'), findsOneWidget);

      // The zone is read, not counted: it is on a line of its own above the
      // piles, and every one of its six places is on the screen.
      final damage = tester.getRect(find.byKey(const ValueKey('damage-You')));
      final piles = tester.getRect(find.byKey(const ValueKey('piles-You')));
      expect(damage.right, lessThanOrEqualTo(size.width));
      expect(
        damage.bottom,
        lessThanOrEqualTo(piles.top),
        reason: 'the piles are below the damage, not beside it',
      );
      expect(tester.takeException(), isNull);
    });
  });
}
