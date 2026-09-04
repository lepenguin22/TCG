import 'dart:math';

import 'package:flutter/foundation.dart';

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
    Random? random,
  }) {
    engine = PlaytestEngine.start(
      store: store,
      yourDeck: yourDeck,
      opponentDeck: opponentDeck,
      random: random,
    );
    ai = PlaytestAi(engine);
  }

  late final PlaytestEngine engine;
  late final PlaytestAi ai;

  PlaytestState get state => engine.state;

  PlaytestSide get you => state.you;

  PlaytestSide get cpu => state.opponent;

  PlaytestStage stage = PlaytestStage.mulligan;

  /// Cards you have picked out of your opening hand to put back.
  final Set<GameCard> mulliganPicks = {};

  /// The most recent drive or damage check, kept so the board can show what
  /// was flipped rather than making you read it out of the log.
  List<GameCard> lastChecks = const [];

  /// A unit you have picked up and are about to place.
  GameCard? holding;

  /// The circle you have chosen to attack with, waiting on a target.
  Circle? selectedAttacker;

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
    engine.mulligan(you, mulliganPicks.toList());
    mulliganPicks.clear();
    engine.beginPlay();
    stage = PlaytestStage.yours;
    _sync();
  }

  // ---------------------------------------------------------------- your turn

  void ride(GameCard card, {required bool fromRideDeck}) {
    engine.ride(you, card, fromRideDeck: fromRideDeck);
    _sync();
  }

  void hold(GameCard? card) {
    holding = card;
    notifyListeners();
  }

  void placeHeld(Circle circle) {
    final card = holding;
    if (card == null) return;
    if (!engine.canCall(you, card, circle)) return;
    engine.call(you, card, circle);
    holding = null;
    _sync();
  }

  void playOrder(GameCard card) {
    engine.playOrder(you, card);
    holding = null;
    _sync();
  }

  void discard(GameCard card) {
    engine.discard(you, card);
    holding = null;
    _sync();
  }

  void nextPhase() {
    selectedAttacker = null;
    holding = null;
    engine.advancePhase();
    // Ending your turn hands over to the CPU, which plays up to its first
    // attack and then waits for you.
    if (!state.yourTurn && !state.isOver) {
      _runCpuTurn();
    }
    _sync();
  }

  void selectAttacker(Circle? circle) {
    selectedAttacker = circle;
    notifyListeners();
  }

  /// Attacks [target] with the unit you picked, bringing the booster behind it
  /// along automatically -- a standing booster is almost always wanted, and
  /// asking every time would make a turn of attacks tedious.
  void attackWithSelected(Circle target) {
    final from = selectedAttacker;
    if (from == null) return;
    final boosterCircle = from.boostedBy;
    final booster = boosterCircle == null ? null : you.field[boosterCircle];
    selectedAttacker = null;
    attack(from: from, to: target, boost: booster != null && !booster.rested);
  }

  /// Declares one of your attacks. The CPU guards it straight away, so what
  /// you see next is the real fight and not a guess at it.
  void attack({required Circle from, required Circle to, bool boost = false}) {
    final pending = engine.declareAttack(from: from, to: to, boost: boost);
    ai.guard(pending);
    lastChecks = const [];
    stage = PlaytestStage.yourAttack;
    _sync();
  }

  /// Runs the drive check for the attack you have declared.
  void driveCheck() {
    lastChecks = engine.driveCheck();
    notifyListeners();
  }

  /// Settles your attack and returns the board to you.
  void resolveYourAttack() {
    engine.resolveAttack();
    lastChecks = const [];
    stage = state.isOver ? PlaytestStage.over : PlaytestStage.yours;
    _sync();
  }

  // ----------------------------------------------------------------- cpu turn

  void _runCpuTurn() {
    ai.takeTurn();
    _nextCpuAttack();
  }

  void _nextCpuAttack() {
    if (state.isOver) {
      stage = PlaytestStage.over;
      return;
    }
    final next = ai.nextAttack();
    if (next == null) {
      // Nothing left to swing with, so the CPU's turn is done.
      engine.endTurn();
      stage = PlaytestStage.yours;
      return;
    }
    engine.declareAttack(from: next.from, to: next.to, boost: next.boost);
    lastChecks = const [];
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
  void confirmGuard() {
    lastChecks = engine.driveCheck();
    stage = PlaytestStage.cpuAttack;
    _sync();
  }

  /// Resolves the CPU's attack and moves on to its next one.
  void resolveCpuAttack() {
    engine.resolveAttack();
    lastChecks = const [];
    _nextCpuAttack();
    _sync();
  }

  // --------------------------------------------------- applied by hand

  void addPower(PlaytestSide side, Circle circle, int amount) {
    engine.addPower(side, circle, amount);
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
}
