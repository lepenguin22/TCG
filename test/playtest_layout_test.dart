import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:tcg_decks/screens/playtest_screen.dart';
import 'package:tcg_decks/store/deck_store.dart';
import 'package:tcg_decks/theme.dart';

import 'package:tcg_decks/playtest/playtest_controller.dart';
import 'package:tcg_decks/playtest/playtest_state.dart';

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

  group('the board in a desktop window', () {
    // The sizes a Windows window actually has: the one it opens at, the same
    // window made shorter, and a maximised one on an ordinary monitor. The
    // app holds itself to 1100 wide, so that is as wide as this gets.
    const opening = Size(884, 921);

    Future<PlaytestController> pump(WidgetTester tester, Size size) async {
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
      return Provider.of<PlaytestController>(
        tester.element(find.byType(Scaffold)),
        listen: false,
      );
    }

    double circleWidth(WidgetTester tester, String key) =>
        tester.getSize(find.byKey(ValueKey(key))).width;

    testWidgets('both players are on the screen at once, unscrolled', (
      tester,
    ) async {
      await pump(tester, opening);

      // Every circle of both boards, without moving anything.
      for (final side in ['You', 'CPU']) {
        for (final circle in Circle.values) {
          expect(
            find.byKey(ValueKey('circle-$side-${circle.name}')),
            findsOneWidget,
            reason: '$side $circle',
          );
        }
      }
      // The outermost scrollable under that key: the piles have one of
      // their own inside it.
      final board = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const ValueKey('board-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        board.position.maxScrollExtent,
        0,
        reason: 'there is nothing below the fold to scroll to',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the cards are drawn to fit the height there is', (
      tester,
    ) async {
      await pump(tester, opening);
      final roomy = circleWidth(tester, 'circle-You-vanguard');
      expect(roomy, lessThanOrEqualTo(132));

      // The same game, in a window dragged shorter.
      tester.view.physicalSize = const Size(884, 700);
      await tester.pump();
      final cramped = circleWidth(tester, 'circle-You-vanguard');
      expect(
        cramped,
        lessThan(roomy),
        reason: 'a shorter window draws smaller cards rather than scrolling',
      );

      // The outermost scrollable under that key: the piles have one of
      // their own inside it.
      final board = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const ValueKey('board-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(board.position.maxScrollExtent, 0);
    });

    testWidgets('the piles sit beside the field, and the fields line up', (
      tester,
    ) async {
      await pump(tester, opening);

      final theirField = tester.getRect(
        find.byKey(const ValueKey('circle-CPU-vanguard')),
      );
      final yourField = tester.getRect(
        find.byKey(const ValueKey('circle-You-vanguard')),
      );
      for (final damage in ['damage-CPU', 'damage-You']) {
        final rect = tester.getRect(find.byKey(ValueKey(damage)));
        expect(
          rect.left,
          greaterThanOrEqualTo(yourField.right),
          reason: '$damage is beside the field, not above it',
        );
      }

      // And the two fields are in the same columns, so an attacker is
      // directly above what it attacks.
      expect(theirField.left, yourField.left);
      expect(theirField.right, yourField.right);
    });

    testWidgets('the log is on the board rather than behind a button', (
      tester,
    ) async {
      await pump(tester, opening);

      expect(find.text('LOG'), findsOneWidget);
      expect(find.byKey(const ValueKey('board-log')), findsOneWidget);
      // And it is saying something: the openings have been settled by now,
      // which is the line the log opens on.
      expect(find.textContaining('kept the opening hand'), findsWidgets);
    });

    testWidgets('a phone keeps the board it was built for', (tester) async {
      await pump(tester, const Size(390, 844));

      expect(find.text('LOG'), findsNothing);
      expect(find.byKey(const ValueKey('board-scroll')), findsNothing);
    });

    testWidgets('a turn plays through at a desktop size', (tester) async {
      await pump(tester, opening);

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
