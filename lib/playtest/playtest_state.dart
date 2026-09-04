import '../games/vanguard/vanguard_rules.dart';
import '../models/card_definition.dart';

/// A place on the field a unit can stand.
///
/// The front row is what fights: only these three can attack, and only these
/// three can be attacked, which is why a booster tucked into the back row is
/// safe there. The back row boosts the circle directly in front of it.
enum Circle {
  frontLeft('Front left'),
  vanguard('Vanguard'),
  frontRight('Front right'),
  backLeft('Back left'),
  backCenter('Back centre'),
  backRight('Back right');

  const Circle(this.label);

  final String label;

  bool get isFrontRow =>
      this == frontLeft || this == vanguard || this == frontRight;

  bool get isRearGuard => this != vanguard;

  /// The circle this one boosts, if it is a back row circle.
  Circle? get boosts => switch (this) {
    backLeft => frontLeft,
    backCenter => vanguard,
    backRight => frontRight,
    _ => null,
  };

  /// The circle that can boost this one.
  Circle? get boostedBy => switch (this) {
    frontLeft => backLeft,
    vanguard => backCenter,
    frontRight => backRight,
    _ => null,
  };
}

/// One physical card in a game, as opposed to the card it is a copy of.
///
/// A deck holds four copies of a card and each is its own piece on the board,
/// so they need to be told apart by something other than their name.
class GameCard {
  GameCard(this.instanceId, this.card);

  final int instanceId;
  final CardDefinition card;

  String get name => card.name;

  int get grade => int.tryParse(card.attributes['grade'] ?? '') ?? 0;

  /// Printed power. Orders and crests have none, and never fight.
  int get power => int.tryParse(card.attributes['power'] ?? '') ?? 0;

  /// Printed shield. A card with none cannot be called to guard -- that is
  /// what stops a grade 3 being thrown in front of an attack.
  int get shield => int.tryParse(card.attributes['shield'] ?? '') ?? 0;

  String get cardType => card.attributes['cardType'] ?? '';

  bool get isUnit =>
      cardType == 'normal' || cardType == 'trigger' || cardType == 'g-unit';

  /// A sentinel guards perfectly: it cancels the attack outright rather than
  /// adding shield, which is why it is worth a card off the top of the hand.
  bool get isSentinel => cardType == 'sentinel';

  bool get canGuard => shield > 0 || isSentinel;

  String? get trigger => triggerIcon(card);

  String get effect => card.attributes['effect'] ?? '';

  String? get imageUrl => card.attribute('imageUrl');

  @override
  String toString() => '$name#$instanceId';
}

/// A unit standing on a circle, with whatever this turn has done to it.
class FieldUnit {
  FieldUnit(this.card);

  final GameCard card;

  /// A rested unit has attacked or boosted and cannot do either again until
  /// it stands.
  bool rested = false;

  /// Power added by triggers and by abilities the player applied by hand.
  /// Cleared at end of turn, as temporary power always is.
  int powerBonus = 0;

  /// Extra damage this unit deals when it hits the vanguard, from critical
  /// triggers. Also cleared at end of turn.
  int criticalBonus = 0;

  int get power => card.power + powerBonus;

  int get critical => 1 + criticalBonus;

  void clearTurnEffects() {
    powerBonus = 0;
    criticalBonus = 0;
  }
}

/// Everything one player owns.
class PlaytestSide {
  PlaytestSide({required this.name, required this.isCpu});

  final String name;
  final bool isCpu;

  /// The main deck, top of deck last so drawing is a cheap remove.
  final List<GameCard> deck = [];
  final List<GameCard> hand = [];

  /// The ride deck, held face down and ridden from in ascending grade order.
  final List<GameCard> rideDeck = [];
  final List<GameCard> drop = [];
  final List<GameCard> soul = [];
  final List<GameCard> damage = [];

  /// Divinez energy. Every way of gaining it is an ability, so the engine
  /// never awards it -- the player sets it as the cards they play say to.
  int energy = 0;

  /// The ride deck crest, once it is in play.
  GameCard? crest;

  final Map<Circle, FieldUnit> field = {};

  FieldUnit? get vanguard => field[Circle.vanguard];

  int get damageCount => damage.length;

  /// Six damage ends the game.
  bool get isDefeated => damageCount >= 6;

  /// Running out of cards to check is the other way to lose.
  bool get isDecked => deck.isEmpty;

  Iterable<FieldUnit> get units => field.values;

  Iterable<MapEntry<Circle, FieldUnit>> get rearGuards =>
      field.entries.where((e) => e.key.isRearGuard);
}

enum PlaytestPhase {
  /// Both players are still deciding which opening cards to put back.
  mulligan('Mulligan'),
  stand('Stand'),
  draw('Draw'),
  ride('Ride'),
  main('Main'),
  battle('Battle'),
  end('End'),
  over('Game over');

  const PlaytestPhase(this.label);

  final String label;
}

/// An attack that has been declared and is waiting to be guarded and resolved.
class PendingAttack {
  PendingAttack({
    required this.attacker,
    required this.attackerCircle,
    required this.target,
    required this.targetCircle,
    this.booster,
  });

  final FieldUnit attacker;
  final Circle attackerCircle;
  final FieldUnit target;
  final Circle targetCircle;
  final FieldUnit? booster;

  /// Cards called to the guardian circle to stop this attack.
  final List<GameCard> guardians = [];

  /// Whether a sentinel has cancelled the attack outright.
  bool perfectGuarded = false;

  bool get isVanguardAttack => attackerCircle == Circle.vanguard;

  bool get hitsVanguard => targetCircle == Circle.vanguard;

  int get attackPower => attacker.power + (booster?.card.power ?? 0);

  int get shield => guardians.fold(0, (sum, card) => sum + card.shield);

  int get defence => target.power + shield;

  bool get connects => !perfectGuarded && attackPower >= defence;
}

/// One line of the running account of the game.
class LogEntry {
  const LogEntry(this.text, {this.turn = 0, this.bySide});

  final String text;
  final int turn;

  /// Which player did it, so the log can be read at a glance.
  final String? bySide;
}

/// The whole game.
class PlaytestState {
  PlaytestState({required this.you, required this.opponent});

  final PlaytestSide you;
  final PlaytestSide opponent;

  /// Turn one is the first player's.
  int turn = 0;
  bool yourTurn = true;
  PlaytestPhase phase = PlaytestPhase.mulligan;

  /// Whether this turn's ride has been used. One ride a turn.
  bool ridden = false;

  PendingAttack? attack;

  final List<LogEntry> log = [];

  PlaytestSide get active => yourTurn ? you : opponent;

  PlaytestSide get inactive => yourTurn ? opponent : you;

  bool get isOver => phase == PlaytestPhase.over;

  /// Who won, once somebody has.
  PlaytestSide? get winner {
    if (you.isDefeated || you.isDecked) return opponent;
    if (opponent.isDefeated || opponent.isDecked) return you;
    return null;
  }

  void note(String text, {PlaytestSide? by}) {
    log.add(LogEntry(text, turn: turn, bySide: by?.name));
  }
}
