import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tcg_decks/playtest/playtest_ai.dart';
import 'package:tcg_decks/playtest/playtest_engine.dart';

import 'playtest_engine_test.dart' show buildDeck;

/// What the CPU does over a lot of games, rather than in one contrived spot.
///
/// A policy can pass every unit test and still play badly, because playing
/// badly is a shape that only shows up over a whole game: swinging into
/// defences it cannot beat, spending four cards where two would do, or never
/// finishing. So the same policy is pointed at both seats and made to play
/// itself, and what comes out is measured.
void main() {
  /// Plays [count] games of the CPU against itself, reporting what happened.
  Future<
    ({
      int games,
      int finished,
      int turns,
      int attacks,
      int hopeless,
      int guards,
      int guardCards,
      int stoppable,
    })
  >
  selfPlay({int count = 40}) async {
    var games = 0,
        finished = 0,
        turns = 0,
        attacks = 0,
        hopeless = 0,
        guards = 0,
        guardCards = 0,
        stoppable = 0;

    for (var seed = 0; seed < count; seed += 1) {
      final (store, deck) = await buildDeck();
      final engine = PlaytestEngine.start(
        store: store,
        yourDeck: deck,
        opponentDeck: deck,
        random: Random(seed),
      );
      final first = PlaytestAi(engine, engine.state.you);
      final second = PlaytestAi(engine, engine.state.opponent);
      engine.beginPlay();

      var loops = 0;
      while (!engine.state.isOver && loops++ < 300) {
        final actor = engine.state.yourTurn ? first : second;
        final defender = engine.state.yourTurn ? second : first;
        actor.takeTurn();

        while (!engine.state.isOver) {
          final next = actor.nextAttack();
          if (next == null) break;
          attacks += 1;
          final pending = engine.declareAttack(
            from: next.from,
            to: next.to,
            boost: next.boost,
          );
          // An attack short of its target's power is waved through, so making
          // one achieves nothing at all.
          if (pending.attackPower < pending.target.power) hopeless += 1;

          if (pending.hitsVanguard &&
              pending.attackPower > pending.target.power) {
            stoppable += 1;
          }
          final handBefore = defender.me.hand.length;
          defender.guard(pending);
          if (pending.guardians.isNotEmpty) {
            guards += 1;
            guardCards += handBefore - defender.me.hand.length;
          }
          engine.driveCheck();
          engine.resolveAttack();
        }
        if (engine.state.isOver) break;
        engine.endTurn();
        turns += 1;
      }
      games += 1;
      if (engine.state.isOver) finished += 1;
    }

    return (
      games: games,
      finished: finished,
      turns: turns,
      attacks: attacks,
      hopeless: hopeless,
      guards: guards,
      guardCards: guardCards,
      stoppable: stoppable,
    );
  }

  group('the CPU played against itself', () {
    test('every game reaches an end', () async {
      final result = await selfPlay();
      expect(result.finished, result.games, reason: 'none stalled out');
      // A game of Vanguard is six damage long, so a run of games that ends in
      // two turns or grinds for fifty means the policy is not playing.
      final perGame = result.turns / result.games;
      expect(perGame, greaterThan(4));
      expect(perGame, lessThan(30));
    });

    test('it never makes an attack that cannot connect', () async {
      final result = await selfPlay();
      expect(result.attacks, greaterThan(200), reason: 'it does attack');
      // This is the change from swinging with everything: an attack under its
      // target's power is simply declined, so it is not made at all.
      expect(result.hopeless, 0);
    });

    test('it guards without emptying its hand to do it', () async {
      final result = await selfPlay();
      expect(result.guards, greaterThan(0));
      // Guarding by taking the biggest shields first means the fewest cards
      // for the job. Filling from the smallest up costs about twice as many.
      final perGuard = result.guardCards / result.guards;
      expect(perGuard, lessThan(1.6), reason: 'cards spent per guard');
    });

    test('it answers most of what it can answer, but not all', () async {
      final result = await selfPlay();
      final rate = result.guards / result.stoppable;
      // Guarding everything is as thoughtless as guarding nothing: early
      // damage is cheap and worth taking, late damage is not.
      expect(rate, greaterThan(0.5));
      expect(rate, lessThan(0.95));
    });
  });
}
