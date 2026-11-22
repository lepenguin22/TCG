import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tcg_decks/playtest/net/playtest_intent.dart';
import 'package:tcg_decks/playtest/order_tokens.dart';
import 'package:tcg_decks/playtest/playtest_controller.dart';
import 'package:tcg_decks/playtest/playtest_state.dart';

import 'playtest_engine_test.dart' show buildDeck;
import 'playtest_net_test.dart' show seatedGame;

Future<PlaytestController> started() async {
  final (store, deck) = await buildDeck();
  final game = PlaytestController(
    store: store,
    yourDeck: deck,
    opponentDeck: deck,
    random: Random(3),
  );
  game.confirmMulligan();
  game.confirmMulligan();
  return game;
}

void main() {
  test('nothing to undo before the first move', () async {
    final game = await started();
    expect(game.canUndo, isFalse);
    game.undo();
    expect(game.canUndo, isFalse);
  });

  test('a ride is taken back whole', () async {
    final game = await started();
    final you = game.you;
    final before = fingerprintOf(game.state);
    final vanguard = you.vanguard!.card;
    final card = game.engine.rideDeckOption(you)!;

    game.ride(card, fromRideDeck: true);
    expect(you.vanguard!.card, card);
    expect(game.canUndo, isTrue);

    game.undo();
    expect(you.vanguard!.card, vanguard);
    expect(you.rideDeck, contains(card));
    expect(you.soul, isNot(contains(vanguard)));
    expect(game.state.ridden, isFalse);
    expect(fingerprintOf(game.state), before);
    expect(game.canUndo, isFalse);
  });

  test('steps come back one at a time, power and tokens and all', () async {
    final game = await started();
    final you = game.you;
    game.ride(game.engine.rideDeckOption(you)!, fromRideDeck: true);
    final afterRide = fingerprintOf(game.state);

    game.addPower(you, Circle.vanguard, 5000);
    final afterPower = fingerprintOf(game.state);
    expect(you.vanguard!.powerBonus, 5000);

    you.field.remove(Circle.backLeft);
    game.callToken(
      you,
      Circle.backLeft,
      namedUnitToken('Plant', 'vanguard', const []),
    );
    expect(you.field[Circle.backLeft]?.card.name, 'Plant');

    game.undo();
    expect(you.field[Circle.backLeft], isNull);
    expect(fingerprintOf(game.state), afterPower);
    game.undo();
    expect(you.vanguard!.powerBonus, 0);
    expect(fingerprintOf(game.state), afterRide);
  });

  test('a shuffle is taken back to the order it was in', () async {
    final game = await started();
    final you = game.you;
    game.drawCard(you);
    final order = [for (final c in you.deck) c.instanceId];
    game.shuffleDeck(you);
    game.undo();
    expect([for (final c in you.deck) c.instanceId], order);
  });

  test('undoing an attack puts the units back and the attack away', () async {
    final game = await started();
    // Turn one cannot attack, so to turn two's battle phase.
    final first = game.state.active;
    while (game.state.active == first) {
      game.nextPhase();
    }
    while (game.state.phase != PlaytestPhase.battle) {
      game.nextPhase();
    }
    final you = game.state.active;
    game.selectAttacker(Circle.vanguard);
    game.attackWithSelected(Circle.vanguard);
    expect(game.state.attack, isNotNull);
    expect(you.vanguard!.rested, isTrue);

    game.undo();
    expect(game.state.attack, isNull);
    expect(you.vanguard!.rested, isFalse);
    expect(game.selectedAttacker, isNull);
  });

  test('across two devices you undo your own move, and only yours', () async {
    final game = await seatedGame();
    final active = game.host.state.active;
    final mine = active == game.sideOne ? game.one : game.two;
    final theirs = active == game.sideOne ? game.two : game.one;
    expect(mine.snapshot!.canUndo, isFalse);

    final before = fingerprintOf(game.host.state);
    mine.ask(const PlaytestIntent(IntentKind.setEnergy, amount: 3));
    await pumpEventQueue();
    expect(active.energy, 3);
    expect(mine.snapshot!.canUndo, isTrue);
    expect(theirs.snapshot!.canUndo, isFalse);

    // Not the other player's to take back.
    theirs.ask(const PlaytestIntent(IntentKind.undo));
    await pumpEventQueue();
    expect(active.energy, 3);
    expect(game.host.refusals.last, contains('last move'));

    mine.ask(const PlaytestIntent(IntentKind.undo));
    await pumpEventQueue();
    expect(active.energy, 0);
    expect(fingerprintOf(game.host.state), before);
    expect(mine.snapshot!.me.energy, 0);
    expect(mine.snapshot!.canUndo, isFalse);
  });
}
