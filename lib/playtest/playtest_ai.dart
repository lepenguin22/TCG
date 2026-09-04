import 'playtest_engine.dart';
import 'playtest_state.dart';

/// The CPU opponent.
///
/// It plays the game the engine can adjudicate: climb the ride deck, build a
/// board, stride where the deck can, attack where attacking achieves
/// something, and guard by what the damage race is actually worth. It does not
/// read card abilities, because nothing here can -- so it is a sparring
/// partner that applies real pressure and makes real decisions about your
/// attacks, not an opponent that will combo you out.
///
/// Everything below is decided from what the engine can see: power, shield,
/// critical, grade, how much damage each side is on and how many cards are in
/// hand. Where a judgement is a guess it is a stated one, so it can be argued
/// with rather than being buried in a magic number.
class PlaytestAi {
  /// [controlled] names the side this instance plays, defaulting to the
  /// opponent -- the CPU seat in a real game. Naming it is what lets the same
  /// policy be pointed at both sides and made to play itself, which is how the
  /// decisions below are measured rather than merely asserted.
  PlaytestAi(this.engine, [PlaytestSide? controlled])
    : _controlled = controlled;

  final PlaytestEngine engine;
  final PlaytestSide? _controlled;

  PlaytestState get state => engine.state;

  /// The side this instance plays.
  PlaytestSide get me => _controlled ?? state.opponent;

  PlaytestSide get foe => me == state.you ? state.opponent : state.you;

  /// Plays this side's turn up to the point where it starts attacking.
  void takeTurn() {
    if (state.isOver) return;

    _ride();
    _stride();
    _callUnits();
    _reposition();
    state.phase = PlaytestPhase.battle;
  }

  // ----------------------------------------------------------------- the board

  void _ride() {
    if (!engine.canRide(me)) {
      state.phase = PlaytestPhase.main;
      return;
    }

    // The ride deck is the reliable climb, so take it whenever it is there.
    final fromDeck = engine.rideDeckOption(me);
    if (fromDeck != null) {
      engine.ride(me, fromDeck, fromRideDeck: true);
      state.phase = PlaytestPhase.main;
      return;
    }

    // Otherwise ride out of hand, going up a grade before going sideways, and
    // taking the biggest of the options at that grade.
    final options = engine.handRideOptions(me);
    if (options.isNotEmpty) {
      final current = me.vanguard?.card.grade ?? 0;
      options.sort((a, b) {
        final up = (b.grade > current ? 1 : 0) - (a.grade > current ? 1 : 0);
        return up != 0 ? up : b.power.compareTo(a.power);
      });
      engine.ride(me, options.first, fromRideDeck: false);
    }
    state.phase = PlaytestPhase.main;
  }

  /// Strides when the deck can, which is most of what a G zone is worth.
  void _stride() {
    if (!engine.canStride(me)) return;

    // The biggest G unit: with no ability text to weigh, power is what is
    // left to choose on.
    final gUnits = [...me.gZone]..sort((a, b) => b.power.compareTo(a.power));

    // Pay with the fewest cards, and among equal grades give up the ones that
    // guard worst -- a 15000 shield trigger in hand is worth more than the
    // grade 3 it could be discarded instead of.
    final payable = [...me.hand]
      ..sort((a, b) {
        final byGrade = b.grade.compareTo(a.grade);
        return byGrade != 0 ? byGrade : a.shield.compareTo(b.shield);
      });

    final cost = <GameCard>[];
    var total = 0;
    for (final card in payable) {
      if (total >= 3) break;
      // Never pay with the perfect guard: it is the card that saves the game.
      if (card.isSentinel) continue;
      cost.add(card);
      total += card.grade;
    }
    if (total < 3) return;
    engine.stride(me, gUnits.first, cost);
  }

  /// Fills the board, without emptying the hand of everything that guards.
  void _callUnits() {
    // Front row first -- those are the circles that attack -- but the boost
    // behind the vanguard comes before a second attacker, because the
    // vanguard attacks every single turn and wants the help every time.
    const order = [
      Circle.frontLeft,
      Circle.backCenter,
      Circle.frontRight,
      Circle.backLeft,
      Circle.backRight,
    ];

    for (final circle in order) {
      // How much hand to keep back for guarding. Deeper in damage means more
      // attacks that have to be answered, so more is held.
      final reserve = me.damageCount >= 4 ? 4 : 3;
      if (me.hand.length <= reserve) return;

      final callable = me.hand
          .where((c) => engine.canCall(me, c, circle))
          .toList();
      if (callable.isEmpty) continue;

      // Call the units that guard worst and hit hardest, keeping the big
      // shields in hand where they are worth more.
      callable.sort((a, b) {
        final byPower = b.power.compareTo(a.power);
        return byPower != 0 ? byPower : a.shield.compareTo(b.shield);
      });

      // Never call away the perfect guard.
      final best = callable.firstWhere(
        (c) => !c.isSentinel,
        orElse: () => callable.first,
      );
      if (best.isSentinel) continue;

      // Replacing a unit already there costs a card for the difference alone,
      // so it has to be a real upgrade rather than a rounding error.
      final occupant = me.field[circle];
      if (occupant != null && best.power < occupant.card.power + 3000) {
        continue;
      }
      engine.call(me, best, circle);
    }
  }

  /// Moves a rear-guard up out of the back row when there is nothing in front
  /// of it to boost.
  ///
  /// A unit stood behind an empty circle is doing nothing at all: it cannot
  /// attack from there and it has nobody to push. Moving it forward turns it
  /// into another attack for free, and costs the boost it was not giving.
  ///
  /// Deliberately after calling rather than before. Given a card for that
  /// empty front circle, the better board is the bigger unit in front with
  /// this one boosting it -- so this only picks up what calling could not
  /// fill, which is the board left over after an attacker was retired.
  void _reposition() {
    for (final back in [Circle.backLeft, Circle.backRight]) {
      final unit = me.field[back];
      if (unit == null) continue;
      final front = engine.moveTargetOf(back);
      if (front == null || me.field[front] != null) continue;
      engine.moveUnit(me, back);
    }
  }

  // ------------------------------------------------------------------ attacking

  /// The next attack worth making, or null when there is none left.
  ///
  /// "Worth making" is the change from swinging with everything every turn: an
  /// attack that cannot reach its target's power even unguarded achieves
  /// nothing at all -- the defender simply declines to guard it -- so it is
  /// not made.
  ({Circle from, Circle to, bool boost})? nextAttack() {
    if (state.isOver || foe.vanguard == null) return null;

    final available = engine.attackers(me);
    if (available.isEmpty) return null;

    // The vanguard swings last: a trigger off its drive check lands on the
    // unit that drew it, so the attacks that want softening up go first.
    available.sort((a, b) {
      if (a == Circle.vanguard) return 1;
      if (b == Circle.vanguard) return -1;
      return 0;
    });

    for (final from in available) {
      final plan = _planAttack(from);
      if (plan != null) return plan;
    }
    return null;
  }

  /// Works out what, if anything, the unit on [from] should attack.
  ({Circle from, Circle to, bool boost})? _planAttack(Circle from) {
    final attacker = me.field[from];
    if (attacker == null) return null;

    // Boosting costs nothing: a unit in the back row cannot attack and cannot
    // be attacked, so leaving it standing buys nothing. It comes along
    // whenever it is there.
    final boosterCircle = from.boostedBy;
    final booster = boosterCircle == null ? null : me.field[boosterCircle];
    final boost = booster != null && !booster.rested;
    final power = attacker.power + (boost ? booster.card.power : 0);

    final enemyVanguard = foe.vanguard;
    if (enemyVanguard == null) return null;

    // A rear-guard that can be killed outright is worth killing when it is
    // pulling real weight -- a big attacker, or the boost under one -- and
    // when this unit is not the vanguard, whose attack is always better spent
    // on the vanguard.
    if (from != Circle.vanguard) {
      Circle? bestTarget;
      var bestValue = 0;
      for (final circle in engine.targets(foe)) {
        if (circle == Circle.vanguard) continue;
        final unit = foe.field[circle];
        if (unit == null || power < unit.power) continue;
        // What killing it is worth: its own power, plus the boost it would
        // have given the unit in front of it.
        final boostBehind = circle.boosts;
        final boosted = boostBehind == null ? null : foe.field[boostBehind];
        final value = unit.card.power + (boosted == null ? 0 : 3000);
        if (value > bestValue) {
          bestValue = value;
          bestTarget = circle;
        }
      }
      // Only worth diverting for a rear-guard that is actually a threat. A
      // 5000 power body is not worth an attack that could pressure instead.
      if (bestTarget != null && bestValue >= 9000) {
        return (from: from, to: bestTarget, boost: boost);
      }
    }

    // Otherwise the vanguard, but only if the attack can get there. An attack
    // short of the defender's power is simply waved through, so making it
    // achieves nothing and tells the opponent what is in the CPU's hand.
    if (power < enemyVanguard.power) return null;
    return (from: from, to: Circle.vanguard, boost: boost);
  }

  // ------------------------------------------------------------------- guarding

  /// How the CPU guards an attack you have made.
  ///
  /// The old version took every hit until the one that would kill it, which is
  /// why it played like a punching bag. Guarding is a trade -- cards out of
  /// hand against damage on the board -- and what that trade is worth depends
  /// on how close to six the CPU is, how big the critical is, and how much
  /// hand it has to spend.
  void guard(PendingAttack pending) {
    // A rear-guard being run over costs a body, not the game. Cards spent
    // saving one are cards not there to save the vanguard.
    if (!pending.hitsVanguard) return;

    final needed = pending.attackPower - pending.target.power + 1;
    if (needed <= 0) return;

    final critical = pending.attacker.critical;
    final lethal = me.damageCount + critical >= 6;
    final options = engine.guardOptions(me);
    if (options.isEmpty) return;

    if (lethal) {
      // Nothing is held back from the hit that ends the game. A perfect guard
      // does it for one card; otherwise pile on shield and hope it reaches.
      for (final card in options) {
        if (card.isSentinel) {
          engine.addGuardian(card);
          return;
        }
      }
      _pileOn(needed, options);
      return;
    }

    // Below lethal, the perfect guard stays in hand -- it is the answer to the
    // attack that would otherwise win, and spending it early is how a game is
    // lost two turns later.
    final shields = options.where((c) => !c.isSentinel).toList();
    final plan = _cheapestGuard(needed, shields);
    if (plan == null) return; // Cannot be stopped, so do not pay towards it.

    // What the CPU will spend, in cards.
    //
    // Nothing at all for the first few. Early damage is not a loss in this
    // game -- it is a damage check, which is a free look at a trigger, and it
    // is the counter-blast an ability will want later. Guarding it away costs
    // a card and buys almost nothing, which is how a fifteen thousand shield
    // trigger ended up being spent to stop a nine thousand attack on turn
    // one. Six damage is the game, so what matters is which damage this is.
    final after = me.damageCount + critical;
    var budget = switch (me.damageCount) {
      0 || 1 || 2 => 0,
      3 => 1,
      4 => 2,
      _ => 3,
    };
    // The hit that puts it on five is the one after which everything has to
    // be answered, so it is worth more than the one that puts it on three.
    if (after >= 5) budget += 1;
    // A double critical is two damage at once, and worth more to stop.
    if (critical >= 2) budget += 1;
    // A full hand can afford to spend; a nearly empty one cannot.
    if (me.hand.length >= 7) budget += 1;
    if (me.hand.length <= 3) budget -= 1;

    if (plan.length > budget) return;
    for (final card in plan) {
      engine.addGuardian(card);
    }
  }

  /// The fewest cards whose shield adds up to [needed], or null if the hand
  /// cannot get there at all.
  List<GameCard>? _cheapestGuard(int needed, List<GameCard> shields) {
    final sorted = [...shields]..sort((a, b) => b.shield.compareTo(a.shield));
    final taken = <GameCard>[];
    var total = 0;
    for (final card in sorted) {
      if (total >= needed) break;
      taken.add(card);
      total += card.shield;
    }
    return total >= needed ? taken : null;
  }

  /// Throws everything at an attack that has to be stopped.
  void _pileOn(int needed, List<GameCard> options) {
    final sorted = [...options]..sort((a, b) => b.shield.compareTo(a.shield));
    var total = 0;
    for (final card in sorted) {
      if (total >= needed) return;
      if (card.isSentinel) continue;
      engine.addGuardian(card);
      total += card.shield;
    }
  }
}
