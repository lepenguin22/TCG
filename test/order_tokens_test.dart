import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tcg_decks/games/card_catalog.dart';
import 'package:tcg_decks/playtest/net/playtest_intent.dart';
import 'package:tcg_decks/playtest/order_tokens.dart';
import 'package:tcg_decks/playtest/playtest_state.dart';

import 'playtest_engine_test.dart' show buildDeck, engineFor;
import 'playtest_net_test.dart' show seatedGame;

const _xceedText =
    '[AUTO]:When this unit is placed by riding from a grade 0 card, '
    '[COST][reveal a grade 3 card with "Impauldio" in its card name from the '
    'ride deck], and put a SYSTEM CODE: X-ceed token into your order zone.';

void main() {
  late final List<CatalogCard> catalog;
  setUpAll(() {
    catalog = parseCatalog(
      File('assets/cards/vanguard.json').readAsStringSync(),
    );
  });

  group('which tokens a deck makes', () {
    test('a card names its token', () {
      expect(orderTokenNamesIn([_xceedText]), ['SYSTEM CODE: X-ceed']);
      expect(
        orderTokenNamesIn([
          'and put a Forge token in your order zone.',
          'put an "Idealize Queen\'s Fort" token in your order zone.',
        ]),
        ['Forge', 'Idealize Queen\'s Fort'],
      );
    });

    test('a sentence with another card named in it still finds the token', () {
      expect(
        orderTokenNamesIn([
          '[COST][put an "Organic Lifeform, Lulu" from (RC) or hand into '
              'soul], search your deck, and if you revealed a card, put a '
              'Soul-Stirring Clash token into your order zone.',
        ]),
        ['Soul-Stirring Clash'],
      );
    });

    test('the database has SYSTEM CODE: X-ceed, first for the deck', () {
      final choices = orderTokenChoices(catalog, [_xceedText]);
      expect(choices.first.name, 'SYSTEM CODE: X-ceed');
      expect(choices.first.attributes['cardNo'], 'DZ-BT04/T02EN');
      expect(choices.every(isOrderZoneToken), isTrue);
    });
  });

  group('on the board', () {
    test('a token goes into the order zone, and out of the game', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.active;
      final xceed = catalog.firstWhere((c) => c.name == 'SYSTEM CODE: X-ceed');

      final token = engine.placeOrderToken(
        you,
        tokenFromCatalog(xceed, 'vanguard'),
      );
      expect(you.orderZone, [token]);
      expect(token.isSetOrder, isTrue);
      expect(token.card.attributes['effect'], contains('AutoMOD'));

      // Whichever way it is sent, a token stops existing.
      engine.removeOrder(you, token, to: OrderExit.hand);
      expect(you.orderZone, isEmpty);
      expect(you.hand, isNot(contains(token)));
      expect(you.drop, isNot(contains(token)));
    });

    test('a token the database lacks is made by name', () async {
      final (store, deck) = await buildDeck();
      final engine = engineFor(store, deck);
      engine.beginPlay();
      final you = engine.state.active;
      final forge = engine.placeOrderToken(
        you,
        namedToken('Forge', 'vanguard'),
      );
      expect(forge.name, 'Forge');
      expect(forge.isSetOrder, isTrue);
    });

    test(
      'across two devices the host makes the token from its own card',
      () async {
        final game = await seatedGame();
        final active = game.host.state.active;
        final mine = active == game.sideOne ? game.one : game.two;
        final theirs = active == game.sideOne ? game.two : game.one;
        final xceed = catalog.firstWhere(
          (c) => c.name == 'SYSTEM CODE: X-ceed',
        );
        game.host.orderTokens = {
          'DZ-BT04/T02EN': tokenFromCatalog(xceed, 'vanguard'),
        };

        mine.ask(
          const PlaytestIntent(
            IntentKind.placeOrderToken,
            name: 'whatever the device says',
            cardNo: 'DZ-BT04/T02EN',
          ),
        );
        await pumpEventQueue();

        expect(active.orderZone.single.name, 'SYSTEM CODE: X-ceed');
        final id = active.orderZone.single.instanceId;
        expect(theirs.snapshot!.them.orderZoneIds, [id]);
        expect(theirs.snapshot!.knows(id), isTrue);

        // By name, for a token the database has no card for.
        mine.ask(
          const PlaytestIntent(IntentKind.placeOrderToken, name: 'Forge'),
        );
        await pumpEventQueue();
        expect(active.orderZone.last.name, 'Forge');

        // And nothing for no name at all.
        mine.ask(const PlaytestIntent(IntentKind.placeOrderToken));
        await pumpEventQueue();
        expect(active.orderZone, hasLength(2));
        expect(game.host.refusals.last, contains('token'));

        // Leaving the order zone, it is gone.
        mine.ask(
          PlaytestIntent(
            IntentKind.removeOrder,
            card: id,
            exit: OrderExit.drop,
          ),
        );
        await pumpEventQueue();
        expect(active.orderZone, hasLength(1));
        expect(active.drop.map((c) => c.instanceId), isNot(contains(id)));
      },
    );
  });
}
