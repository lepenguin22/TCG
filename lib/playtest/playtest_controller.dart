import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/card_definition.dart';
import '../models/deck.dart';
import '../store/deck_store.dart';
import 'playtest_ai.dart';
import 'playtest_engine.dart';
import 'playtest_state.dart';

/// What the board is waiting for.
enum PlaytestStage {
  /// You are still choosing which opening cards to put back.
  mulligan,

  /// Your turn, and yours to drive.
  yours,

  /// You have declared an attack and the CPU has guarded it: the drive check
  /// and the damage are yours to confirm, so you can read what came off the
  /// top before it resolves.
  yourAttack,

  /// The CPU is playing its main phase, one action per tap, so what it did
  /// can be read as it happens rather than found finished.
  cpuTurn,

  /// The CPU is attacking and is waiting for you to guard.
  guarding,

  /// The CPU's attack has been guarded and is ready to resolve.
  cpuAttack,

  over,
}

/// Drives a game and tells the screen what to show.
///
/// The engine knows the rules and the AI knows what the CPU wants; this is the
/// piece that decides when each of them gets to move, and holds the little
/// bits of presentation state -- what the last drive check turned up -- that
/// the board needs in order to show a player what just happened to them.
class PlaytestController extends ChangeNotifier {
  PlaytestController({
    required DeckStore store,
    required Deck yourDeck,
    required Deck opponentDeck,
    TurnOrder turnOrder = TurnOrder.youFirst,
    this.mode = PlaytestMode.vsCpu,
    Random? random,
  }) {
    engine = PlaytestEngine.start(
      store: store,
      yourDeck: yourDeck,
      opponentDeck: opponentDeck,
      turnOrder: turnOrder,
      mode: mode,
      random: random,
    );
    ai = PlaytestAi(engine);
    gameId = yourDeck.gameId;
    mulliganSide = state.you;
  }

  /// Who plays the other side: the CPU, or you.
  final PlaytestMode mode;

  /// Whether both hands are yours.
  bool get bothSides => mode == PlaytestMode.bothSides;

  /// The game being played, for the screens that need to ask its rules or its
  /// card database something -- choosing a crest to play, among them.
  late final String gameId;

  late final PlaytestEngine engine;
  late final PlaytestAi ai;

  PlaytestState get state => engine.state;

  /// The near side of the board: the deck you set up as yours. It stays at
  /// the bottom of the screen whoever is playing it.
  PlaytestSide get you => state.you;

  /// The far side.
  PlaytestSide get cpu => state.opponent;

  /// The side you are acting as right now.
  ///
  /// Against the CPU that is always your own. With both hands yours it is
  /// whoever's turn it is, which is the whole of what the mode changes: every
  /// control on the board goes on working, and it works for the player whose
  /// turn it is.
  PlaytestSide get me => bothSides ? state.active : state.you;

  /// Whether you are the one playing [side].
  bool controls(PlaytestSide side) => bothSides || side == state.you;

  /// Whether it is [side]'s turn.
  bool isTurnOf(PlaytestSide side) => side == state.active;

  /// The hand the strip along the bottom shows: the defender's while a guard
  /// is being made, and otherwise the hand of whoever is playing.
  PlaytestSide get handSide =>
      stage == PlaytestStage.guarding ? state.inactive : me;

  PlaytestStage stage = PlaytestStage.mulligan;

  /// Cards you have picked out of the opening hand to put back.
  final Set<GameCard> mulliganPicks = {};

  /// Whose opening hand is being decided. With both hands yours, the second
  /// player's follows the first's.
  late PlaytestSide mulliganSide;

  /// The cards this battle has turned face up, drive and damage together.
  /// The engine keeps them; the board shows them as the trigger zone.
  List<CheckedCard> get triggerZone => state.triggerZone;

  /// A unit you have picked up and are about to place.
  GameCard? holding;

  /// The circle you have chosen to attack with, waiting on a target.
  Circle? selectedAttacker;

  /// Whether the booster behind the chosen attacker is coming along.
  ///
  /// Off until you say otherwise. Boosting is not always wanted: a unit that
  /// restands wants its booster kept back for the second swing, and a booster
  /// spent on the first one is not there for it.
  bool boostSelected = false;

  void _sync() {
    if (state.isOver) stage = PlaytestStage.over;
    notifyListeners();
  }

  // ------------------------------------------------------------------ mulligan

  void togglePick(GameCard card) {
    if (!mulliganPicks.remove(card)) mulliganPicks.add(card);
    notifyListeners();
  }

  void confirmMulligan() {
    engine.mulligan(mulliganSide, mulliganPicks.toList());
    mulliganPicks.clear();
    // With both hands yours, the other player decides their own opening
    // before the game starts rather than having one decided for them.
    if (bothSides && mulliganSide == state.you) {
      mulliganSide = state.opponent;
      notifyListeners();
      return;
    }
    engine.beginPlay();
    stage = PlaytestStage.yours;
    // The CPU may have won the roll, in which case turn one is its own and it
    // plays straight through to its first attack before you get the board.
    // With both hands yours there is nobody to hand over to.
    if (!bothSides && !state.yourTurn && !state.isOver) {
      _runCpuTurn();
    }
    _sync();
  }

  // ---------------------------------------------------------------- your turn

  void ride(GameCard card, {required bool fromRideDeck, GameCard? discard}) {
    engine.ride(me, card, fromRideDeck: fromRideDeck, discard: discard);
    _sync();
  }

  void hold(GameCard? card) {
    holding = card;
    notifyListeners();
  }

  void placeHeld(Circle circle) {
    final card = holding;
    if (card == null) return;
    if (!engine.canCall(me, card, circle)) return;
    engine.call(me, card, circle);
    holding = null;
    _sync();
  }

  void playOrder(GameCard card) {
    engine.playOrder(me, card);
    holding = null;
    _sync();
  }

  void playOrderFromDrop(PlaytestSide side, GameCard card) {
    engine.playOrderFromDrop(side, card);
    _sync();
  }

  void discard(GameCard card) {
    engine.discard(handSide, card);
    holding = null;
    _sync();
  }

  void nextPhase() {
    selectedAttacker = null;
    boostSelected = false;
    holding = null;
    engine.advancePhase();
    // Ending your turn hands over to the CPU, which plays up to its first
    // attack and then waits for you. With both hands yours the turn simply
    // passes to the other player, who is also you.
    if (!bothSides && !state.yourTurn && !state.isOver) {
      _runCpuTurn();
    }
    _sync();
  }

  void selectAttacker(Circle? circle) {
    selectedAttacker = circle;
    boostSelected = false;
    notifyListeners();
  }

  /// The unit that could boost the attacker you have chosen, if there is one
  /// standing behind it that is allowed to.
  ///
  /// A grade 2 or greater in the back row is not a booster: it can only boost
  /// if an ability has given it [Boost], which is a button on its own sheet.
  FieldUnit? get availableBooster {
    final from = selectedAttacker;
    final circle = from?.boostedBy;
    if (circle == null) return null;
    final booster = me.field[circle];
    if (booster == null || booster.rested || !booster.canBoost) return null;
    return booster;
  }

  /// The unit behind the attacker that would boost if it could, so the board
  /// can say why it is not being offered.
  FieldUnit? get boosterThatCannot {
    final circle = selectedAttacker?.boostedBy;
    if (circle == null) return null;
    final behind = me.field[circle];
    if (behind == null || behind.rested || behind.canBoost) return null;
    return behind;
  }

  void toggleBoost() {
    if (availableBooster == null) return;
    boostSelected = !boostSelected;
    notifyListeners();
  }

  /// Attacks [target] with the unit you picked, boosting only if you asked
  /// for it.
  void attackWithSelected(Circle target) {
    final from = selectedAttacker;
    if (from == null) return;
    final boost = boostSelected && availableBooster != null;
    selectedAttacker = null;
    boostSelected = false;
    attack(from: from, to: target, boost: boost);
  }

  /// Declares an attack. Against the CPU it guards straight away, so what you
  /// see next is the real fight and not a guess at it; with both hands yours
  /// the guard is yours to make too, so the board asks for it first.
  void attack({required Circle from, required Circle to, bool boost = false}) {
    // The turn one rule, kept here as well as in what the board offers: a
    // caller that has not asked cannot make an attack that is not allowed.
    if (!engine.canAttack(me)) return;
    final pending = engine.declareAttack(from: from, to: to, boost: boost);
    if (bothSides) {
      stage = PlaytestStage.guarding;
      _sync();
      return;
    }
    ai.guard(pending);
    stage = PlaytestStage.yourAttack;
    _sync();
  }

  /// Runs the drive check for the attack you have declared.
  void driveCheck() {
    engine.driveCheck();
    notifyListeners();
  }

  /// Settles your attack and returns the board to you.
  void resolveYourAttack() {
    engine.resolveAttack();
    // The trigger zone is deliberately left standing: the damage this attack
    // just dealt was checked during the resolve, and clearing it here would
    // hide the card before it had been read.
    stage = state.isOver ? PlaytestStage.over : PlaytestStage.yours;
    _sync();
  }

  // ----------------------------------------------------------------- cpu turn

  /// Hands the turn to the CPU. Nothing is played yet: its main phase is
  /// stepped through from the board, one action at a time.
  void _runCpuTurn() {
    lastCpuAction = null;
    stage = PlaytestStage.cpuTurn;
  }

  /// What the CPU last did, for the line above the Continue button.
  String? lastCpuAction;

  /// Plays the CPU's next single action, or moves it on to attacking when its
  /// main phase is done.
  void cpuStep() {
    final before = state.log.length;
    if (ai.takeStep()) {
      // Everything the engine noted for that one action: a call and the
      // ability it set off are one step and read as one line.
      final done = state.log
          .skip(before)
          .map((entry) => entry.text)
          .where((text) => !text.startsWith('---'))
          .join(' ');
      lastCpuAction = done.isEmpty ? null : done;
      _sync();
      return;
    }
    lastCpuAction = null;
    _nextCpuAttack();
    _sync();
  }

  void _nextCpuAttack() {
    if (state.isOver) {
      stage = PlaytestStage.over;
      return;
    }
    final next = ai.nextAttack();
    if (next == null) {
      // Nothing left to swing with, so the CPU's turn is done -- but the
      // abilities that pay out at the end of it come first.
      ai.playEndOfTurnAbilities();
      engine.endTurn();
      stage = PlaytestStage.yours;
      return;
    }
    final pending = engine.declareAttack(
      from: next.from,
      to: next.to,
      boost: next.boost,
    );
    // Whatever the attack itself sets off, before you are asked to guard it:
    // the power it adds is power your guard has to answer.
    ai.playAttackAbilities(pending);
    stage = PlaytestStage.guarding;
  }

  /// Adds a card from your hand to the guardian circle against the CPU's
  /// attack.
  void guardWith(GameCard card) {
    engine.addGuardian(card);
    _sync();
  }

  /// Takes the attack as it stands: drive check first, so you see what the
  /// CPU turned up before the damage lands.
  ///
  /// With both hands yours the guard is finished rather than the attack: the
  /// board goes back to the attacking player, who drives and resolves it the
  /// way they would any attack of their own.
  void confirmGuard() {
    if (bothSides) {
      stage = PlaytestStage.yourAttack;
      _sync();
      return;
    }
    engine.driveCheck();
    stage = PlaytestStage.cpuAttack;
    _sync();
  }

  /// Resolves the CPU's attack and moves on to its next one.
  void resolveCpuAttack() {
    // The attack is gone by the time it has resolved, so which circle swung
    // is remembered here for the abilities that pay out on a hit.
    final attacker = state.attack?.attackerCircle;
    final booster = state.attack?.booster == null ? null : attacker?.boostedBy;
    final hit = engine.resolveAttack();
    if (attacker != null) {
      if (hit) ai.playHitAbilities(attacker);
      ai.playEndOfBattleAbilities(attacker, booster);
    }
    _nextCpuAttack();
    _sync();
  }

  // --------------------------------------------------- applied by hand

  void addPower(PlaytestSide side, Circle circle, int amount) {
    engine.addPower(side, circle, amount);
    _sync();
  }

  void addCritical(PlaytestSide side, Circle circle, int amount) {
    engine.addCritical(side, circle, amount);
    _sync();
  }

  void grantBoost(PlaytestSide side, Circle circle, {required bool granted}) {
    engine.grantBoost(side, circle, granted: granted);
    _sync();
  }

  void addDrive(PlaytestSide side, Circle circle, int amount) {
    engine.addDrive(side, circle, amount);
    _sync();
  }

  void toggleRest(PlaytestSide side, Circle circle) {
    engine.toggleRest(side, circle);
    _sync();
  }

  void retire(PlaytestSide side, Circle circle) {
    engine.retire(side, circle);
    _sync();
  }

  /// Moves one of your rear-guards between the rows of its column.
  void moveUnit(PlaytestSide side, Circle circle) {
    engine.moveUnit(side, circle);
    _sync();
  }

  void setEnergy(PlaytestSide side, int value) {
    engine.setEnergy(side, value);
    _sync();
  }

  void drawCard(PlaytestSide side) {
    engine.drawCard(side);
    _sync();
  }

  void dealDamage(PlaytestSide side) {
    engine.dealDamage(side);
    _sync();
  }

  /// Strides [side]'s G unit, paid for out of that side's hand.
  ///
  /// The side is passed in rather than assumed: with both hands yours the
  /// player striding is whichever G zone was opened, and a stride run against
  /// the wrong side finds the G unit missing and quietly does nothing.
  void stride(PlaytestSide side, GameCard card, List<GameCard> cost) {
    engine.stride(side, card, cost);
    _sync();
  }

  void counterBlast(PlaytestSide side, int count) {
    engine.counterBlast(side, count);
    _sync();
  }

  void counterCharge(PlaytestSide side, int count) {
    engine.counterCharge(side, count);
    _sync();
  }

  void soulBlast(PlaytestSide side, GameCard card) {
    engine.soulBlast(side, card);
    _sync();
  }

  void soulCharge(PlaytestSide side, int count) {
    engine.soulCharge(side, count);
    _sync();
  }

  void searchDeck(PlaytestSide side, GameCard card, {bool toHand = true}) {
    engine.searchDeck(side, card, toHand: toHand);
    _sync();
  }

  void shuffleDeck(PlaytestSide side) {
    engine.shuffleDeck(side);
    _sync();
  }

  void returnFromDrop(PlaytestSide side, GameCard card) {
    engine.returnFromDrop(side, card);
    _sync();
  }

  void bottomDeck(PlaytestSide side, GameCard card) {
    engine.bottomDeck(side, card);
    _sync();
  }

  void bottomDeckUnit(PlaytestSide side, Circle circle) {
    engine.bottomDeckUnit(side, circle);
    _sync();
  }

  void playCrest(PlaytestSide side, CardDefinition card) {
    engine.playCrest(side, card);
    _sync();
  }

  void removeCrest(PlaytestSide side, GameCard crest) {
    engine.removeCrest(side, crest);
    _sync();
  }

  void flipG(PlaytestSide side, GameCard card, {required bool faceUp}) {
    engine.flipG(side, card, faceUp: faceUp);
    _sync();
  }

  void hollow(PlaytestSide side, Circle circle) {
    engine.hollow(side, circle);
    _sync();
  }

  void toggleLock(PlaytestSide side, Circle circle) {
    if (side.field[circle]?.locked ?? false) {
      engine.unlock(side, circle);
    } else {
      engine.lock(side, circle);
    }
    _sync();
  }
}
