import 'playtest_engine.dart';
import 'playtest_state.dart';

/// The CPU opponent.
///
/// It plays the game the engine can actually adjudicate: climb the ride deck,
/// fill the board with the biggest units it can, boost, and swing at the
/// vanguard. It does not read card abilities, because nothing here can -- so
/// it is a sparring partner that applies pressure and makes you guard, not an
/// opponent that will combo you out. That is the useful half for a playtest:
/// it answers "does my deck ride, draw and hold up under attacks", which is
/// what a goldfish never asks.
class PlaytestAi {
  PlaytestAi(this.engine);

  final PlaytestEngine engine;

  PlaytestState get state => engine.state;

  /// Plays the CPU's whole turn, stopping when it needs the player to guard.
  ///
  /// Returns when it is the player's turn again, or when an attack is waiting
  /// on a guard decision.
  void takeTurn() {
    if (state.isOver || !state.opponent.isCpu) return;

    _ride();
    _callUnits();
    state.phase = PlaytestPhase.battle;
  }

  void _ride() {
    final side = state.opponent;
    if (!engine.canRide(side)) {
      state.phase = PlaytestPhase.main;
      return;
    }

    // The ride deck is the reliable climb, so take it whenever it is there.
    final fromDeck = engine.rideDeckOption(side);
    if (fromDeck != null) {
      engine.ride(side, fromDeck, fromRideDeck: true);
      state.phase = PlaytestPhase.main;
      return;
    }

    // Otherwise ride the biggest legal unit in hand, preferring to go up a
    // grade over riding sideways into the same one.
    final options = engine.handRideOptions(side);
    if (options.isNotEmpty) {
      final current = side.vanguard?.card.grade ?? 0;
      options.sort((a, b) {
        final up = (b.grade > current ? 1 : 0) - (a.grade > current ? 1 : 0);
        return up != 0 ? up : b.power.compareTo(a.power);
      });
      engine.ride(side, options.first, fromRideDeck: false);
    }
    state.phase = PlaytestPhase.main;
  }

  void _callUnits() {
    final side = state.opponent;

    // Fill the front row first -- those are the circles that attack -- then
    // the back row behind them to boost.
    const order = [
      Circle.frontLeft,
      Circle.frontRight,
      Circle.backCenter,
      Circle.backLeft,
      Circle.backRight,
    ];

    for (final circle in order) {
      final callable =
          side.hand.where((c) => engine.canCall(side, c, circle)).toList()
            ..sort((a, b) => b.power.compareTo(a.power));
      if (callable.isEmpty) continue;

      final occupant = side.field[circle];
      final best = callable.first;
      // Only overwrite a unit already there if the replacement is genuinely
      // bigger, so the CPU does not churn its own board away.
      if (occupant != null && occupant.card.power >= best.power) continue;
      // Keep a couple of cards back to guard with rather than emptying the
      // hand onto the board.
      if (side.hand.length <= 2) return;
      engine.call(side, best, circle);
    }
  }

  /// The next attack the CPU wants to make, or null when it is done attacking.
  ///
  /// Attacks are handed back one at a time so the player can guard each of
  /// them, which is the part of the opponent's turn a playtest is really for.
  ({Circle from, Circle to, bool boost})? nextAttack() {
    final side = state.opponent;
    final foe = state.you;
    if (state.isOver || foe.vanguard == null) return null;

    final available = engine.attackers(side);
    if (available.isEmpty) return null;

    // Vanguard last: its drive checks can find the power that makes the
    // earlier attacks worth guarding, and attacking with it first wastes that.
    available.sort((a, b) {
      if (a == Circle.vanguard) return 1;
      if (b == Circle.vanguard) return -1;
      return 0;
    });

    final from = available.first;
    final booster = from.boostedBy;
    final canBoost =
        booster != null &&
        side.field[booster] != null &&
        !side.field[booster]!.rested;

    // Aim at a rear-guard only when it can be picked off without help;
    // otherwise the vanguard is always the attack worth making.
    final targets = engine.targets(foe);
    var to = Circle.vanguard;
    if (targets.contains(Circle.vanguard)) {
      final attackPower =
          side.field[from]!.power +
          (canBoost ? side.field[booster]!.card.power : 0);
      for (final candidate in targets) {
        if (candidate == Circle.vanguard) continue;
        final unit = foe.field[candidate];
        if (unit != null && attackPower >= unit.power) {
          to = candidate;
          break;
        }
      }
    }

    return (from: from, to: to, boost: canBoost);
  }

  /// How the CPU guards an attack the player has made.
  ///
  /// It spends the least shield that still stops the attack, and only when the
  /// hit actually matters -- there is no sense burning the hand on an early
  /// attack it can afford to take.
  void guard(PendingAttack pending) {
    final side = state.opponent;
    if (!pending.hitsVanguard) return;

    final needed = pending.attackPower - pending.target.power + 1;
    if (needed <= 0) return;

    // Damage five is the one that must not be taken, so anything goes to stop
    // it. Before that, take the hit unless it is cheap to stop.
    final lethal = side.damageCount + pending.attacker.critical >= 6;
    final options = engine.guardOptions(side)
      ..sort((a, b) => a.shield.compareTo(b.shield));
    if (options.isEmpty) return;

    if (lethal) {
      final sentinel = options.where((c) => c.isSentinel).firstOrNull;
      if (sentinel != null) {
        engine.addGuardian(sentinel);
        return;
      }
    } else if (needed > 15000 || side.hand.length <= 3) {
      return;
    }

    var shield = 0;
    for (final card in options) {
      if (shield >= needed) break;
      if (card.isSentinel) continue;
      engine.addGuardian(card);
      shield += card.shield;
    }
  }
}
