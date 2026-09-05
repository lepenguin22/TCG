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
    Random? random,
  }) {
    engine = PlaytestEngine.start(
      store: store,
      yourDeck: yourDeck,
      opponentDeck: opponentDeck,
      turnOrder: turnOrder,
      random: random,
    );
    ai = PlaytestAi(engine);
    gameId = yourDeck.gameId;
  }

  /// The game being played, for the screens that need to ask its rules or its
  /// card database something -- choosing a crest to play, among them.
  late final String gameId;

  late final PlaytestEngine engine;
  late final PlaytestAi ai;

  PlaytestState get state => engine.state;

  PlaytestSide get you => state.you;

  PlaytestSide get cpu => state.opponent;

  PlaytestStage stage = PlaytestStage.mulligan;

  /// Cards you have picked out of your opening hand to put back.
  final Set<GameCard> mulliganPicks = {};

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
    engine.mulligan(you, mulliganPicks.toList());
    mulliganPicks.clear();
    engine.beginPlay();
    stage = PlaytestStage.yours;
    // The CPU may have won the roll, in which case turn one is its own and it
    // plays straight through to its first attack before you get the board.
    if (!state.yourTurn && !state.isOver) {
      _runCpuTurn();
    }
    _sync();
  }

  // ---------------------------------------------------------------- your turn

  void ride(GameCard card, {required bool fromRideDeck, GameCard? discard}) {
    engine.ride(you, card, fromRideDeck: fromRideDeck, discard: discard);
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
    boostSelected = false;
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
    boostSelected = false;
    notifyListeners();
  }

  /// The unit that could boost the attacker you have chosen, if there is one
  /// standing behind it.
  FieldUnit? get availableBooster {
    final from = selectedAttacker;
    final circle = from?.boostedBy;
    if (circle == null) return null;
    final booster = you.field[circle];
    return booster == null || booster.rested ? null : booster;
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

  /// Declares one of your attacks. The CPU guards it straight away, so what
  /// you see next is the real fight and not a guess at it.
  void attack({required Circle from, required Circle to, bool boost = false}) {
    final pending = engine.declareAttack(from: from, to: to, boost: boost);
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
      // Nothing left to swing with, so the CPU's turn is done.
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
  void confirmGuard() {
    engine.driveCheck();
    stage = PlaytestStage.cpuAttack;
    _sync();
  }

  /// Resolves the CPU's attack and moves on to its next one.
  void resolveCpuAttack() {
    engine.resolveAttack();
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

  void stride(GameCard card, List<GameCard> cost) {
    engine.stride(you, card, cost);
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
