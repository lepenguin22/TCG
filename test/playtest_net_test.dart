import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tcg_decks/models/card_definition.dart';
import 'package:tcg_decks/playtest/net/playtest_host.dart';
import 'package:tcg_decks/playtest/net/playtest_intent.dart';
import 'package:tcg_decks/playtest/net/playtest_transport.dart';
import 'package:tcg_decks/playtest/net/playtest_wire.dart';
import 'package:tcg_decks/playtest/net/remote_board.dart';
import 'package:tcg_decks/playtest/playtest_engine.dart';
import 'package:tcg_decks/playtest/playtest_state.dart';
import 'package:tcg_decks/store/deck_store.dart';

import 'playtest_engine_test.dart' show buildDeck;

/// A game with two people at it rather than a person and a program.
Future<PlaytestEngine> twoPlayerGame(
  DeckStore store,
  deck, {
  int seed = 7,
}) async => PlaytestEngine.start(
  store: store,
  yourDeck: deck,
  opponentDeck: deck,
  mode: PlaytestMode.bothSides,
  random: Random(seed),
);

/// A host with both players seated over loopback pipes, openings settled.
Future<
  ({
    PlaytestHost host,
    RemoteBoard one,
    RemoteBoard two,
    PlaytestSide sideOne,
    PlaytestSide sideTwo,
  })
>
seatedGame({bool keepOpenings = true}) async {
  final (store, deck) = await buildDeck();
  final engine = await twoPlayerGame(store, deck);
  final host = PlaytestHost(engine);

  final (hostEndOne, deviceOne) = LoopbackTransport.pair();
  final (hostEndTwo, deviceTwo) = LoopbackTransport.pair();
  final one = RemoteBoard(transport: deviceOne, gameId: 'vanguard');
  final two = RemoteBoard(transport: deviceTwo, gameId: 'vanguard');
  host.seat(engine.state.you, hostEndOne);
  host.seat(engine.state.opponent, hostEndTwo);
  await pumpEventQueue();

  if (keepOpenings) {
    one.ask(const PlaytestIntent(IntentKind.confirmMulligan));
    two.ask(const PlaytestIntent(IntentKind.confirmMulligan));
    await pumpEventQueue();
  }
  return (
    host: host,
    one: one,
    two: two,
    sideOne: engine.state.you,
    sideTwo: engine.state.opponent,
  );
}

void main() {
  group('the pipe between two devices', () {
    test('what one end sends, the other end hears', () async {
      final (first, second) = LoopbackTransport.pair();
      final heard = <Map<String, Object?>>[];
      second.messages.listen(heard.add);

      first.send({'type': 'hello'});
      expect(heard, isEmpty, reason: 'a wire is never instant');
      await pumpEventQueue();
      expect(heard, [
        {'type': 'hello'},
      ]);
    });

    test('a hung-up pipe carries nothing', () async {
      final (first, second) = LoopbackTransport.pair();
      final heard = <Map<String, Object?>>[];
      second.messages.listen(heard.add);

      await second.close();
      first.send({'type': 'hello'});
      await pumpEventQueue();
      expect(heard, isEmpty);
      expect(first.isOpen, isTrue, reason: 'this end did not hang up');
    });
  });

  group('what a player is allowed to see', () {
    test('your own hand comes with its cards', () async {
      final game = await seatedGame();
      final snapshot = game.one.snapshot!;

      expect(snapshot.me.handIds, hasLength(game.sideOne.hand.length));
      for (final id in snapshot.me.handIds) {
        expect(snapshot.knows(id), isTrue, reason: 'it is your own hand');
      }
    });

    test('their hand is a row of cards held up backwards', () async {
      final game = await seatedGame();
      final snapshot = game.one.snapshot!;

      // How many they hold is public -- you can count them across the table.
      expect(snapshot.them.handCount, game.sideTwo.hand.length);
      expect(snapshot.them.handCount, greaterThan(0));
      for (final id in snapshot.them.handIds) {
        expect(
          snapshot.knows(id),
          isFalse,
          reason: 'their hand is theirs to know',
        );
      }
    });

    test('no deck travels, not even your own', () async {
      final game = await seatedGame();
      final snapshot = game.one.snapshot!;

      // The count is public; the order is nobody's, which is the whole
      // reason a deck is shuffled.
      expect(snapshot.me.deckCount, game.sideOne.deck.length);
      expect(snapshot.them.deckCount, game.sideTwo.deck.length);
      final deckIds = {
        for (final card in [...game.sideOne.deck, ...game.sideTwo.deck])
          card.instanceId,
      };
      expect(
        snapshot.faces.keys.where(deckIds.contains),
        isEmpty,
        reason: 'not one card of either deck',
      );
    });

    test('their ride deck is a count, yours is a list', () async {
      final game = await seatedGame();
      final mine = game.one.snapshot!;

      expect(mine.me.rideDeckIds, hasLength(game.sideOne.rideDeck.length));
      expect(mine.me.rideDeckIds.every(mine.knows), isTrue);
      expect(mine.them.rideDeckIds, isEmpty);
      expect(mine.them.rideDeckCount, game.sideTwo.rideDeck.length);
      for (final card in game.sideTwo.rideDeck) {
        expect(mine.knows(card.instanceId), isFalse);
      }
    });

    test('everything on the table is on both tables', () async {
      final game = await seatedGame();
      final mine = game.one.snapshot!;
      final theirs = game.two.snapshot!;

      // The vanguards stood up at the start: public, and the same cards from
      // either seat.
      final myVanguard = game.sideOne.vanguard!.card.instanceId;
      expect(mine.knows(myVanguard), isTrue);
      expect(theirs.knows(myVanguard), isTrue);
      expect(
        mine.faces[myVanguard]!.name,
        theirs.faces[myVanguard]!.name,
        reason: 'one card, two seats',
      );
    });

    test('a card becomes public the moment it is played', () async {
      final game = await seatedGame();
      // A card in the ride deck: its owner may look at it, the other player
      // may not, and riding it puts it on the table for both.
      final card = game.sideOne.rideDeck.firstWhere((c) => c.grade == 1);
      expect(game.one.snapshot!.knows(card.instanceId), isTrue);
      expect(game.two.snapshot!.knows(card.instanceId), isFalse);

      game.one.ask(PlaytestIntent(IntentKind.ride, card: card.instanceId));
      await pumpEventQueue();

      expect(
        game.two.snapshot!.knows(card.instanceId),
        isTrue,
        reason: 'it is standing on the table now',
      );
    });

    test(
      'every id a snapshot mentions has a face, bar the hidden ones',
      () async {
        final game = await seatedGame();
        final snapshot = game.one.snapshot!;
        final hidden = {...snapshot.them.handIds};

        final mentioned = <int>[
          ...snapshot.me.handIds,
          ...snapshot.me.rideDeckIds,
          for (final side in [snapshot.me, snapshot.them]) ...[
            ...side.units.values.map((u) => u.cardId),
            ...side.damageIds,
            ...side.dropIds,
            ...side.soulIds,
            ...side.gZoneIds,
            ...side.removedIds,
            ...side.crestIds,
            ...side.handIds,
          ],
        ];
        expect(mentioned, isNotEmpty);
        for (final id in mentioned) {
          if (hidden.contains(id)) continue;
          expect(snapshot.knows(id), isTrue, reason: 'card $id has no face');
        }
      },
    );

    test('a snapshot survives the trip through JSON', () async {
      final game = await seatedGame();
      final original = game.one.snapshot!;
      final copy = PlaytestSnapshot.fromJson(original.toJson());

      expect(copy.me.name, original.me.name);
      expect(copy.them.handCount, original.them.handCount);
      expect(copy.me.deckCount, original.me.deckCount);
      expect(copy.phase, original.phase);
      expect(copy.turn, original.turn);
      expect(copy.faces.length, original.faces.length);
      expect(copy.me.units.keys, original.me.units.keys);
    });
  });

  group('asking the host for a move', () {
    test('a move one player makes shows up on both boards', () async {
      final game = await seatedGame();
      final card = game.sideOne.rideDeck.firstWhere((c) => c.grade == 1);

      game.one.ask(PlaytestIntent(IntentKind.ride, card: card.instanceId));
      await pumpEventQueue();

      expect(game.sideOne.vanguard!.card.instanceId, card.instanceId);
      expect(
        game.one.snapshot!.me.units[Circle.vanguard]!.cardId,
        card.instanceId,
      );
      expect(
        game.two.snapshot!.them.units[Circle.vanguard]!.cardId,
        card.instanceId,
        reason: 'the far seat sees the same vanguard',
      );
    });

    test('a player cannot move on the other player\'s turn', () async {
      final game = await seatedGame();
      final card = game.sideTwo.rideDeck.firstWhere((c) => c.grade == 1);

      game.two.ask(PlaytestIntent(IntentKind.ride, card: card.instanceId));
      await pumpEventQueue();

      expect(game.sideTwo.vanguard!.card.grade, 0, reason: 'nothing happened');
      expect(game.two.refusal, contains('not Player 2\'s turn'));
    });

    test('naming a card in the other player\'s hand finds nothing', () async {
      final game = await seatedGame();
      // Player 1's turn, asking to ride a card out of Player 2's hand: the
      // id is real, but it is not theirs, so it is not there to be found.
      final theirs = game.sideTwo.rideDeck.first;
      final before = game.sideTwo.hand.length;

      game.one.ask(PlaytestIntent(IntentKind.ride, card: theirs.instanceId));
      await pumpEventQueue();

      expect(game.sideTwo.hand.length, before);
      expect(game.sideOne.vanguard!.card.grade, 0);
      expect(game.one.refusal, contains('no such card'));
    });

    test(
      'the defender may play a blitz order on the attacker\'s turn',
      () async {
        final game = await seatedGame();
        final engine = game.host.engine;

        // Past turn one, into a battle, and Player 1 swings.
        while (engine.state.turn < 2 ||
            engine.state.phase != PlaytestPhase.battle) {
          engine.advancePhase();
        }
        game.host.broadcast();
        await pumpEventQueue();
        final attacker = engine.state.active;
        final defender = engine.state.inactive;
        final defending = defender == game.sideOne ? game.one : game.two;
        final attacking = attacker == game.sideOne ? game.one : game.two;

        attacking.ask(
          const PlaytestIntent(
            IntentKind.attack,
            circle: Circle.vanguard,
            to: Circle.vanguard,
          ),
        );
        await pumpEventQueue();
        final defence = engine.state.attack!.defence;

        // A blitz order in the defender's hand, which they may play although
        // it is not their turn.
        final blitz = GameCard(
          994,
          CardDefinition(
            id: 'blitz',
            gameId: 'vanguard',
            name: 'Persona Shield',
            attributes: const {'grade': '0', 'cardType': 'order-blitz'},
            createdAt: DateTime(2024),
            updatedAt: DateTime(2024),
          ),
        );
        defender.hand.add(blitz);

        defending.ask(
          PlaytestIntent(
            IntentKind.playBlitz,
            card: blitz.instanceId,
            amount: 10000,
          ),
        );
        await pumpEventQueue();

        expect(engine.state.attack!.defence, defence + 10000);
        expect(defender.drop, contains(blitz));
        expect(
          engine.state.attack!.guardians,
          isEmpty,
          reason: 'an order is not a guardian',
        );
      },
    );

    test('a card in the drop answers an attack too', () async {
      final game = await seatedGame();
      final engine = game.host.engine;
      while (engine.state.turn < 2 ||
          engine.state.phase != PlaytestPhase.battle) {
        engine.advancePhase();
      }
      game.host.broadcast();
      await pumpEventQueue();
      final defender = engine.state.inactive;
      final attacker = engine.state.active;
      final defending = defender == game.sideOne ? game.one : game.two;
      final attacking = attacker == game.sideOne ? game.one : game.two;

      attacking.ask(
        const PlaytestIntent(
          IntentKind.attack,
          circle: Circle.vanguard,
          to: Circle.vanguard,
        ),
      );
      await pumpEventQueue();
      final defence = engine.state.attack!.defence;

      // A card in the defender's drop zone with something to say about it.
      final inDrop = defender.hand.first;
      engine.discard(defender, inDrop);
      expect(defender.drop, contains(inDrop));

      defending.ask(
        PlaytestIntent(
          IntentKind.activateFromDrop,
          card: inDrop.instanceId,
          amount: 5000,
        ),
      );
      await pumpEventQueue();

      expect(engine.state.attack!.defence, defence + 5000);
      expect(
        defender.removed,
        contains(inDrop),
        reason: 'used from the drop, it leaves the game',
      );
      expect(defender.drop.contains(inDrop), isFalse);
    });

    test('a card in their drop is not yours to use', () async {
      final game = await seatedGame();
      final engine = game.host.engine;
      final theirs = game.sideTwo.hand.first;
      engine.discard(game.sideTwo, theirs);

      game.one.ask(
        PlaytestIntent(IntentKind.activateFromDrop, card: theirs.instanceId),
      );
      await pumpEventQueue();

      expect(game.sideTwo.drop, contains(theirs));
      expect(game.one.refusal, contains('no such card in the drop zone'));
    });

    test('an ordinary order still waits for its own turn', () async {
      final game = await seatedGame();
      final engine = game.host.engine;
      while (engine.state.turn < 2 ||
          engine.state.phase != PlaytestPhase.battle) {
        engine.advancePhase();
      }
      game.host.broadcast();
      await pumpEventQueue();
      final defender = engine.state.inactive;
      final defending = defender == game.sideOne ? game.one : game.two;

      final order = GameCard(
        993,
        CardDefinition(
          id: 'order',
          gameId: 'vanguard',
          name: 'Slow Order',
          attributes: const {'grade': '0', 'cardType': 'order'},
          createdAt: DateTime(2024),
          updatedAt: DateTime(2024),
        ),
      );
      defender.hand.add(order);

      defending.ask(
        PlaytestIntent(IntentKind.playOrder, card: order.instanceId),
      );
      await pumpEventQueue();

      expect(defender.hand, contains(order), reason: 'it is not their turn');
      expect(defending.refusal, contains('turn'));

      // And a card that is not a blitz order is not one however it is asked
      // for.
      defending.ask(
        PlaytestIntent(IntentKind.playBlitz, card: order.instanceId),
      );
      await pumpEventQueue();
      expect(defender.hand, contains(order));
      expect(defending.refusal, contains('not a blitz order'));
    });

    test('a message this build cannot read is refused, not obeyed', () async {
      final game = await seatedGame();
      game.one.transport.send({
        'type': 'intent',
        'intent': {'kind': 'summonCthulhu', 'card': 1},
      });
      await pumpEventQueue();

      expect(game.host.refusals.last, contains('does not know'));
    });

    test('an opening hand is put back when its player says so', () async {
      final game = await seatedGame(keepOpenings: false);
      expect(game.host.state.phase, PlaytestPhase.mulligan);
      final pitched = game.sideOne.hand.first;

      game.one.ask(
        PlaytestIntent(IntentKind.togglePick, card: pitched.instanceId),
      );
      game.one.ask(const PlaytestIntent(IntentKind.confirmMulligan));
      await pumpEventQueue();

      expect(game.sideOne.hand.contains(pitched), isFalse);
      expect(game.sideOne.hand.length, 5, reason: 'and one drawn back');
      expect(
        game.host.state.phase,
        PlaytestPhase.mulligan,
        reason: 'the game waits for the other player',
      );

      game.two.ask(const PlaytestIntent(IntentKind.confirmMulligan));
      await pumpEventQueue();
      expect(game.host.state.phase, isNot(PlaytestPhase.mulligan));
    });

    test('two devices play a battle out between them', () async {
      final game = await seatedGame();
      final engine = game.host.engine;

      // Player 1 rides and passes; nobody attacks on the first turn.
      game.one.ask(
        PlaytestIntent(
          IntentKind.ride,
          card: game.sideOne.rideDeck
              .firstWhere((c) => c.grade == 1)
              .instanceId,
        ),
      );
      for (var i = 0; i < 8 && engine.state.active == game.sideOne; i += 1) {
        game.one.ask(const PlaytestIntent(IntentKind.nextPhase));
        await pumpEventQueue();
      }
      expect(engine.state.active, game.sideTwo);

      // Player 2 rides and attacks the vanguard with theirs.
      game.two.ask(
        PlaytestIntent(
          IntentKind.ride,
          card: game.sideTwo.rideDeck
              .firstWhere((c) => c.grade == 1)
              .instanceId,
        ),
      );
      await pumpEventQueue();
      while (engine.state.phase != PlaytestPhase.battle) {
        game.two.ask(const PlaytestIntent(IntentKind.nextPhase));
        await pumpEventQueue();
      }
      game.two.ask(
        const PlaytestIntent(
          IntentKind.attack,
          circle: Circle.vanguard,
          to: Circle.vanguard,
        ),
      );
      await pumpEventQueue();

      // Both seats see the attack, from their own side of it.
      expect(game.two.snapshot!.attack, isNotNull);
      expect(game.one.snapshot!.attack!.targetCircle, Circle.vanguard);

      // The defender guards out of their own hand, the attacker drive checks,
      // and the attack is settled.
      final shield = game.sideOne.hand.where((c) => c.canGuard).firstOrNull;
      if (shield != null) {
        game.one.ask(PlaytestIntent(IntentKind.guard, card: shield.instanceId));
        await pumpEventQueue();
        expect(engine.state.attack!.guardians, hasLength(1));
        expect(
          game.two.snapshot!.attack!.guardianIds,
          contains(shield.instanceId),
          reason: 'a guardian is face up on the table',
        );
      }

      final damageBefore = game.sideOne.damageCount;
      game.two.ask(const PlaytestIntent(IntentKind.driveCheck));
      await pumpEventQueue();
      game.two.ask(const PlaytestIntent(IntentKind.resolveAttack));
      await pumpEventQueue();

      expect(engine.state.attack, isNull, reason: 'the battle is over');
      expect(
        game.one.snapshot!.me.damageIds.length,
        anyOf(damageBefore, damageBefore + 1),
      );
      expect(
        game.one.snapshot!.log.last,
        game.two.snapshot!.log.last,
        reason: 'both players are reading the same game',
      );
    });
  });

  group('set orders across two devices', () {
    /// A set order put straight into [side]'s hand, the way a deck full of
    /// them would deal one.
    /// [id] sits far above anything the engine hands out, so a test card
    /// never turns out to be a card already in the game.
    GameCard setOrder(PlaytestHost host, PlaytestSide side, {int id = 900770}) {
      final card = GameCard(
        id,
        CardDefinition(
          id: 'catalog:test-set-order-$id',
          gameId: 'vanguard',
          name: 'Product $id',
          attributes: const {'grade': '1', 'cardType': 'order-set'},
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      side.hand.add(card);
      return card;
    }

    test('a set order played from hand shows on both devices', () async {
      final game = await seatedGame();
      final active = game.host.state.active;
      final mine = active == game.sideOne ? game.one : game.two;
      final theirs = active == game.sideOne ? game.two : game.one;
      final order = setOrder(game.host, active);

      mine.ask(PlaytestIntent(IntentKind.playSetOrder, card: order.instanceId));
      await pumpEventQueue();

      expect(active.orderZone, [order]);
      expect(mine.snapshot!.me.orderZoneIds, [order.instanceId]);
      expect(theirs.snapshot!.them.orderZoneIds, [
        order.instanceId,
      ], reason: 'a set order is on the table for both to see');
      expect(
        theirs.snapshot!.knows(order.instanceId),
        isTrue,
        reason: 'both players are playing under what it says',
      );
    });

    test('only a set order is set', () async {
      final game = await seatedGame();
      final active = game.host.state.active;
      final mine = active == game.sideOne ? game.one : game.two;
      final unit = active.hand.firstWhere((c) => c.isUnit);

      mine.ask(PlaytestIntent(IntentKind.playSetOrder, card: unit.instanceId));
      await pumpEventQueue();

      expect(active.orderZone, isEmpty);
      expect(game.host.refusals.last, contains('not a set order'));
    });

    test('a set order leaves by the way its owner picks', () async {
      final game = await seatedGame();
      final active = game.host.state.active;
      final mine = active == game.sideOne ? game.one : game.two;
      final order = setOrder(game.host, active);
      mine.ask(PlaytestIntent(IntentKind.playSetOrder, card: order.instanceId));
      await pumpEventQueue();

      mine.ask(
        PlaytestIntent(
          IntentKind.removeOrder,
          card: order.instanceId,
          exit: OrderExit.soul,
        ),
      );
      await pumpEventQueue();

      expect(active.orderZone, isEmpty);
      expect(active.soul, contains(order));
      expect(mine.snapshot!.me.soulIds, contains(order.instanceId));
    });

    test('the other player cannot take your set order away', () async {
      final game = await seatedGame();
      final active = game.host.state.active;
      final idle = active == game.sideOne ? game.sideTwo : game.sideOne;
      final mine = active == game.sideOne ? game.one : game.two;
      final theirs = active == game.sideOne ? game.two : game.one;
      final order = setOrder(game.host, active);
      mine.ask(PlaytestIntent(IntentKind.playSetOrder, card: order.instanceId));
      await pumpEventQueue();

      // On their own turn, so what stops them is whose order zone it is
      // rather than whose turn it is.
      game.host.state.yourTurn = !game.host.state.yourTurn;
      theirs.ask(
        PlaytestIntent(IntentKind.removeOrder, card: order.instanceId),
      );
      await pumpEventQueue();

      expect(active.orderZone, [
        order,
      ], reason: 'it is still where its owner set it');
      expect(idle.drop.contains(order), isFalse);
      expect(game.host.refusals.last, contains('order zone'));
    });
  });

  group('moving units and drive across two devices', () {
    /// A unit of [side]'s put straight onto [circle], the way a call would
    /// leave it.
    void place(PlaytestHost host, PlaytestSide side, Circle circle) {
      final card = side.hand.firstWhere((c) => c.isUnit);
      side.hand.remove(card);
      side.field[circle] = FieldUnit(card);
    }

    test('a guest swaps two of its own rear-guards', () async {
      final game = await seatedGame();
      final active = game.host.state.active;
      final mine = active == game.sideOne ? game.one : game.two;
      place(game.host, active, Circle.frontLeft);
      final moving = active.field[Circle.frontLeft]!.card;

      mine.ask(
        const PlaytestIntent(
          IntentKind.swapUnits,
          circle: Circle.frontLeft,
          to: Circle.backRight,
        ),
      );
      await pumpEventQueue();

      expect(active.field[Circle.frontLeft], isNull);
      expect(active.field[Circle.backRight]!.card, moving);
      expect(mine.snapshot!.me.units[Circle.backRight], isNotNull);
      expect(mine.snapshot!.me.units[Circle.frontLeft], isNull);
    });

    test('nothing is swapped onto the vanguard', () async {
      final game = await seatedGame();
      final active = game.host.state.active;
      final mine = active == game.sideOne ? game.one : game.two;
      place(game.host, active, Circle.frontLeft);
      final vanguard = active.vanguard;

      mine.ask(
        const PlaytestIntent(
          IntentKind.swapUnits,
          circle: Circle.frontLeft,
          to: Circle.vanguard,
        ),
      );
      await pumpEventQueue();

      expect(active.vanguard, same(vanguard));
      expect(active.field[Circle.frontLeft], isNotNull);
      expect(game.host.refusals.last, contains('cannot change places'));
    });

    test('a rear-guard given drive owes the attack a check', () async {
      final game = await seatedGame();
      final engine = game.host.engine;
      // Turn one attacks nobody, so hand the turn on and play the second.
      engine.endTurn();
      final active = engine.state.active;
      final mine = active == game.sideOne ? game.one : game.two;
      place(game.host, active, Circle.frontLeft);
      engine.state.phase = PlaytestPhase.battle;

      mine.ask(
        const PlaytestIntent(
          IntentKind.addDrive,
          circle: Circle.frontLeft,
          amount: 1,
        ),
      );
      await pumpEventQueue();
      expect(active.field[Circle.frontLeft]!.driveBonus, 1);

      mine.ask(
        const PlaytestIntent(
          IntentKind.attack,
          circle: Circle.frontLeft,
          to: Circle.vanguard,
        ),
      );
      await pumpEventQueue();
      expect(
        mine.snapshot!.attack!.drivesOwed,
        1,
        reason: 'the far board has to be told, since only the ability knows',
      );

      final hand = active.hand.length;
      mine.ask(const PlaytestIntent(IntentKind.driveCheck));
      await pumpEventQueue();

      expect(active.hand.length, hand + 1);
      expect(mine.snapshot!.attack!.drivesOwed, 0);
      expect(mine.snapshot!.attack!.driveChecked, isTrue);
    });

    test('a rear-guard on no drive owes nothing', () async {
      final game = await seatedGame();
      final engine = game.host.engine;
      engine.endTurn();
      final active = engine.state.active;
      final mine = active == game.sideOne ? game.one : game.two;
      place(game.host, active, Circle.frontLeft);
      engine.state.phase = PlaytestPhase.battle;

      mine.ask(
        const PlaytestIntent(
          IntentKind.attack,
          circle: Circle.frontLeft,
          to: Circle.vanguard,
        ),
      );
      await pumpEventQueue();

      expect(mine.snapshot!.attack!.drivesOwed, 0);
      mine.ask(const PlaytestIntent(IntentKind.driveCheck));
      await pumpEventQueue();
      expect(game.host.refusals.last, contains('no drive owed'));
    });
  });
}
