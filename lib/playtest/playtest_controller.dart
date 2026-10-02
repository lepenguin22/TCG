import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/card_definition.dart';
import '../models/deck.dart';
import '../store/deck_store.dart';
import 'playtest_engine.dart';
import 'playtest_state.dart';

/// What the board is waiting for.
enum PlaytestStage {
  /// You are still choosing which opening cards to put back.
  mulligan,

  /// Your turn, and yours to drive.
  yours,

  /// The attack has been guarded: the drive check and the damage are the
  /// attacking player's to confirm, so what came off the top can be read
  /// before it resolves.
  yourAttack,

  /// An attack has been declared and the defender is being asked to guard it.
  guarding,

  over,
}

/// Drives a game and tells the screen what to show.
///
/// The engine knows the rules; this is the
/// piece that decides when each of them gets to move, and holds the little
/// bits of presentation state -- what the last drive check turned up -- that
/// the board needs in order to show a player what just happened to them.
class PlaytestController extends ChangeNotifier {
  PlaytestController({
    required DeckStore store,
    required Deck yourDeck,
    required Deck opponentDeck,
    TurnOrder turnOrder = TurnOrder.playerOneFirst,
    Random? random,
  }) {
    engine = PlaytestEngine.start(
      store: store,
      yourDeck: yourDeck,
      opponentDeck: opponentDeck,
      turnOrder: turnOrder,
      random: random,
    );
    gameId = yourDeck.gameId;
    mulliganSide = state.you;
  }

  /// The game being played, for the screens that need to ask its rules or its
  /// card database something -- choosing a crest to play, among them.
  late final String gameId;

  late final PlaytestEngine engine;

  PlaytestState get state => engine.state;

  /// The near side of the board: the deck you set up as yours. It stays at
  /// the bottom of the screen whoever is playing it.
  PlaytestSide get you => state.you;

  /// The far side.
  PlaytestSide get opponent => state.opponent;

  /// The side you are acting as right now: whoever's turn it is.
  ///
  /// Both hands are yours, so every control on the board goes on working and
  /// it works for the player whose turn it is.
  PlaytestSide get me => state.active;

  /// Whether you are the one playing [side]. Both of them are.
  bool controls(PlaytestSide side) => true;

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
    // Both hands are yours, so the other player decides their own opening
    // before the game starts rather than having one decided for them.
    if (mulliganSide == state.you) {
      mulliganSide = state.opponent;
      notifyListeners();
      return;
    }
    engine.beginPlay();
    stage = PlaytestStage.yours;
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

  /// Plays a blitz order from the hand the board is showing, which during a
  /// guard is the defender's.
  void playBlitz(GameCard card, {int shield = 0}) {
    engine.playBlitz(handSide, card, shield: shield);
    holding = null;
    _sync();
  }

  void addShield(PlaytestSide side, int amount) {
    engine.addShield(side, amount);
    _sync();
  }

  void playSetOrder(GameCard card) {
    engine.playSetOrder(handSide, card);
    holding = null;
    _sync();
  }

  void removeOrder(
    PlaytestSide side,
    GameCard card, {
    OrderExit to = OrderExit.drop,
  }) {
    engine.removeOrder(side, card, to: to);
    _sync();
  }

  void playOrder(GameCard card) {
    engine.playOrder(me, card);
    holding = null;
    _sync();
  }

  void activateFromDrop(PlaytestSide side, GameCard card) {
    engine.activateFromDrop(side, card);
    _sync();
  }

  void removeFromDrop(PlaytestSide side, GameCard card) {
    engine.removeFromDrop(side, card);
    _sync();
  }

  void discard(GameCard card) {
    engine.discard(handSide, card);
    holding = null;
    _sync();
  }

  void handToSoul(GameCard card) {
    engine.handToSoul(handSide, card);
    holding = null;
    _sync();
  }

  void nextPhase() {
    selectedAttacker = null;
    boostSelected = false;
    holding = null;
    engine.advancePhase();
    // The turn simply passes to the other player, who is also you.
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

  /// Declares an attack. The guard is yours to make as well, so the board
  /// asks the defender for it before handing the attack back to be resolved.
  void attack({required Circle from, required Circle to, bool boost = false}) {
    // The turn one rule, kept here as well as in what the board offers: a
    // caller that has not asked cannot make an attack that is not allowed.
    if (!engine.canAttack(me)) return;
    engine.declareAttack(from: from, to: to, boost: boost);
    stage = PlaytestStage.guarding;
    _sync();
  }

  /// Flips the next drive check for the attack on the table.
  ///
  /// One per tap: a twin drive is two moments, and what the first turns up
  /// changes what the second is worth reading against.
  void driveCheck() {
    engine.driveCheckOne();
    notifyListeners();
  }

  /// How many checks the attack still owes.
  int get drivesLeft => engine.drivesLeft();

  /// Settles your attack and returns the board to you.
  void resolveYourAttack() {
    engine.resolveAttack();
    // The trigger zone is deliberately left standing: the damage this attack
    // just dealt was checked during the resolve, and clearing it here would
    // hide the card before it had been read.
    stage = state.isOver ? PlaytestStage.over : PlaytestStage.yours;
    _sync();
  }

  /// Adds a card from the defender's hand to the guardian circle.
  void guardWith(GameCard card) {
    engine.addGuardian(card);
    _sync();
  }

  /// Finishes the guard, which hands the board back to the attacking player:
  /// they drive and resolve it the way they would any attack of their own.
  void confirmGuard() {
    stage = PlaytestStage.yourAttack;
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

  /// Hands a checked trigger's power or critical to a different unit.
  void moveTriggerGift(
    PlaytestSide side,
    CheckedCard checked,
    Circle to, {
    required bool power,
  }) {
    engine.moveTriggerGift(side, checked, to, power: power);
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

  void swapUnits(PlaytestSide side, Circle from, Circle to) {
    engine.swapUnits(side, from, to);
    _sync();
  }

  void setEnergy(PlaytestSide side, int value) {
    engine.setEnergy(side, value);
    _sync();
  }

  void setEnergyCap(PlaytestSide side, int cap) {
    engine.setEnergyCap(side, cap);
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

  void takeFromTop(PlaytestSide side, GameCard card, DeckPick to) {
    engine.takeFromTop(side, card, to);
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

  void unitToSoul(PlaytestSide side, Circle circle) {
    engine.unitToSoul(side, circle);
    _sync();
  }

  void playCrest(PlaytestSide side, CardDefinition card) {
    engine.playCrest(side, card);
    _sync();
  }

  void addToken(PlaytestSide side, CardDefinition card) {
    engine.addToken(side, card);
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
