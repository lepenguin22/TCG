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

  /// Whether this is an order of any kind -- normal, blitz or set.
  bool get isOrder => cardType.startsWith('order');

  /// A set order, which is played out of hand and then stays on the table
  /// in the order zone, doing whatever it says, until something takes it
  /// away. Every other card played out of hand is gone by the time it has
  /// finished resolving.
  bool get isSetOrder => cardType == 'order-set';

  /// A blitz order, which is the one kind of card that can be played in the
  /// middle of a battle: either player may play one during a battle phase,
  /// which is what makes them the defender's answer to an attack.
  bool get isBlitz => cardType == 'order-blitz';

  /// Whether this is a ticket: a card an ability makes and hands you, which
  /// says so itself -- "(This card is a ticket card, and cannot be put in a
  /// deck)". It is in no deck, so it can only reach the board this way.
  bool get isTicket => effect.toLowerCase().contains('is a ticket card');

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

  /// A locked card is turned face down on its circle and is not a unit at
  /// all: it cannot attack, boost, be attacked or be chosen, and nothing can
  /// be called over it. It unlocks at the end of its owner's turn.
  bool locked = false;

  /// A hollowed unit fights this turn and is retired at the end of it. The
  /// bargain a Nightrose deck is built on: the power now, the body later.
  bool hollowed = false;

  /// Whether this is a unit rather than a face-down card, which is the
  /// question almost every rule about it is really asking.
  bool get isActive => !locked;

  /// Whether an ability has given this unit [Boost] for the turn. Cleared
  /// with everything else a turn hands out.
  bool grantedBoost = false;

  /// Whether this unit can boost the one in front of it.
  ///
  /// Only grades 0 and 1 have [Boost] printed on them -- a grade 2 standing
  /// in the back row is a body and nothing more -- and the rest of the game's
  /// boosting comes from abilities that grant it, which is what
  /// [grantedBoost] is for.
  bool get canBoost => isActive && (card.grade <= 1 || grantedBoost);

  /// Power added by triggers and by abilities the player applied by hand.
  /// Cleared at end of turn, as temporary power always is.
  int powerBonus = 0;

  /// Extra damage this unit deals when it hits the vanguard, from critical
  /// triggers. Also cleared at end of turn.
  int criticalBonus = 0;

  /// Extra drive checks this unit makes, from an ability that grants them.
  /// Only the vanguard drive checks at all, so this only ever matters there.
  int driveBonus = 0;

  /// Power that lasts one battle rather than one turn -- "until end of that
  /// battle", which is most of what an on-attack ability gives. Cleared when
  /// the attack resolves, so a pump for one swing does not sit on the unit
  /// for the rest of the turn.
  int battleBonus = 0;

  /// Abilities already used this turn, by their printed text. What a
  /// [1/Turn] is counted with.
  final Set<String> usedAbilities = {};

  int get power => card.power + powerBonus + battleBonus;

  int get critical => 1 + criticalBonus;

  void clearBattleEffects() {
    battleBonus = 0;
  }

  void clearTurnEffects() {
    powerBonus = 0;
    criticalBonus = 0;
    driveBonus = 0;
    battleBonus = 0;
    grantedBoost = false;
    usedAbilities.clear();
  }
}

/// Everything one player owns.
/// Where a set order goes when it leaves the order zone. Its own text says
/// which, so the board asks rather than deciding.
enum OrderExit { drop, soul, hand, removed }

class PlaytestSide {
  PlaytestSide({required this.name, required this.isCpu});

  final String name;
  final bool isCpu;

  /// The main deck, top of deck last so drawing is a cheap remove.
  final List<GameCard> deck = [];
  final List<GameCard> hand = [];

  /// The ride deck, held face down and ridden from in ascending grade order.
  final List<GameCard> rideDeck = [];

  /// The G zone, which only a Premium deck that strides has.
  final List<GameCard> gZone = [];

  /// Cards removed from the game.
  ///
  /// An over trigger goes here when it is checked: it is not put in hand from
  /// a drive check and not left in the damage zone from a damage one. The
  /// pile exists so what left is visible rather than simply gone.
  final List<GameCard> removed = [];

  /// The order zone, where a set order sits face up once it is played.
  ///
  /// It is not a pile of spent cards: everything here is still doing
  /// something, and a deck built on set orders counts them -- "if your order
  /// zone has three or more set orders" -- so they are kept where both
  /// players can see them rather than swept into the drop.
  final List<GameCard> orderZone = [];

  /// The G zone cards that are face up.
  ///
  /// A G unit comes back face up when its stride ends, and abilities turn
  /// them up as a cost, so how many are face up is a resource in its own
  /// right -- it is what a Generation Break counts.
  final Set<int> faceUpG = {};
  final List<GameCard> drop = [];
  final List<GameCard> soul = [];
  final List<GameCard> damage = [];

  /// Damage turned face down by a counter-blast, by instance. A face down
  /// card is spent: it still counts towards the six, but cannot pay again
  /// until something counter-charges it.
  final Set<int> spentDamage = {};

  /// The unit a striding G unit is riding on top of, put back when the stride
  /// ends. In the game it sits underneath as the "heart".
  FieldUnit? heart;

  /// Divinez energy, spent on the abilities that ask for it.
  ///
  /// The ride deck crest charges this on its own every turn, which the engine
  /// does; every other way of gaining or spending it is an ability, which the
  /// player applies by hand.
  int energy = 0;

  /// The most energy the Energy Generator allows: "[CONT]:You may have up to
  /// ten energy."
  static const baseEnergyCap = 10;

  /// The most energy this player may hold, which is not always ten.
  ///
  /// Cards raise it -- "the maximum energy you may have ... gets +5" puts it
  /// at fifteen -- and a raised cap is a lasting thing, not a turn's worth of
  /// it, so it stays where it is put until something changes it back.
  int energyCap = baseEnergyCap;

  /// The ride deck crest this deck brought, while it is still in the ride
  /// deck. It moves into the crest zone on the first ride.
  GameCard? rideCrest;

  /// The crest zone.
  ///
  /// A list, because a player can have more than one crest in it at once: the
  /// Energy Generator out of the ride deck, and a stride deck's own crest put
  /// there by an ability, both at the same time.
  final List<GameCard> crestZone = [];

  /// Whether anything is in the crest zone.
  ///
  /// A ride deck crest gets there on the first ride, not at the start of the
  /// game, and that timing is the whole of the first turn energy rule: the
  /// charge happens at the beginning of the ride phase, and on turn one the
  /// crest is not there yet to do it.
  bool get crestInPlay => crestZone.isNotEmpty;

  /// Whether this side took the first turn of the game. The crest pays the
  /// player who went second three energy to make up for it.
  bool goesFirst = false;

  final Map<Circle, FieldUnit> field = {};

  FieldUnit? get vanguard => field[Circle.vanguard];

  int get damageCount => damage.length;

  /// Damage still face up, and so still able to pay a counter-blast.
  int get openDamage =>
      damage.where((c) => !spentDamage.contains(c.instanceId)).length;

  bool isSpent(GameCard card) => spentDamage.contains(card.instanceId);

  bool isFaceUp(GameCard card) => faceUpG.contains(card.instanceId);

  /// How many G zone cards are face up: the number a Generation Break is
  /// counted against.
  int get generationBreak =>
      gZone.where((card) => faceUpG.contains(card.instanceId)).length;

  /// Whether a G unit is currently riding on top of the vanguard.
  bool get isStriding => heart != null;

  /// Six damage ends the game.
  bool get isDefeated => damageCount >= 6;

  /// Running out of cards to check is the other way to lose.
  bool get isDecked => deck.isEmpty;

  /// The units on the field. Locked cards are face down and are not units,
  /// so they are not here -- which is what keeps them out of every rule that
  /// asks what this side has standing.
  Iterable<FieldUnit> get units => field.values.where((u) => u.isActive);

  /// Everything on the field, locked cards included. For the board, which
  /// still has to draw them, and for unlocking them again.
  Iterable<MapEntry<Circle, FieldUnit>> get occupied => field.entries;

  Iterable<MapEntry<Circle, FieldUnit>> get rearGuards =>
      field.entries.where((e) => e.key.isRearGuard && e.value.isActive);
}

/// Who takes the first turn.
///
/// It is a real decision rather than a formality: the player going second is
/// paid three energy by the crest to make up for it, and the player going
/// first gets to build a board a turn earlier. A real game settles it with
/// rock-paper-scissors, which [random] stands in for.
enum TurnOrder {
  youFirst('You go first'),
  cpuFirst('The CPU goes first'),
  random('Decided at random');

  const TurnOrder(this.label);

  final String label;

  /// The same choice said in the words of a game where both hands are yours.
  String get soloLabel => switch (this) {
    TurnOrder.youFirst => 'Player 1 goes first',
    TurnOrder.cpuFirst => 'Player 2 goes first',
    TurnOrder.random => 'Decided at random',
  };
}

/// Who plays the other side of the board.
enum PlaytestMode {
  /// The CPU does, as far as it can: it rides, calls, attacks and guards,
  /// and plays the abilities the reader can follow.
  vsCpu,

  /// You do. Both hands are yours, nothing moves unless you move it, and no
  /// ability goes unplayed because a program could not read it -- which is
  /// what a real test of a deck against a deck needs.
  bothSides,
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

/// Which kind of check turned a card face up.
enum CheckKind {
  drive('Drive'),
  damage('Damage');

  const CheckKind(this.label);

  final String label;
}

/// A card turned face up by a check, sitting in the trigger zone.
///
/// In the game the checked card is put face up where both players can see it
/// before it goes to hand or to damage, which is the moment a trigger is read
/// off it. The board keeps that moment rather than only its consequences.
class CheckedCard {
  CheckedCard(this.card, this.kind, this.sideName);

  final GameCard card;
  final CheckKind kind;

  /// Whose check it was: your drive and their damage come off the same
  /// attack, so the two have to be told apart.
  final String sideName;

  /// Where this trigger's gift went, and how much of it there was.
  ///
  /// The board hands a trigger to the unit that is fighting, which is the
  /// common case. The game lets you split it -- the critical on the vanguard
  /// and the power on a rear-guard about to swing is the classic -- so what
  /// was given is remembered here, and can be handed to another unit
  /// afterwards without guessing at the numbers.
  Circle? powerTo;
  int powerGiven = 0;
  Circle? criticalTo;
  int criticalGiven = 0;

  /// Whether there is anything on this card to hand around.
  bool get isSplittable => powerGiven > 0 || criticalGiven > 0;
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

  /// Shield from something other than a guardian: a blitz order played in
  /// the middle of the battle, or an ability that hands the defending unit
  /// shield or power for the battle. It goes with the battle, as everything
  /// bought for one battle does.
  int shieldBonus = 0;

  /// Whether a sentinel has cancelled the attack outright.
  bool perfectGuarded = false;

  /// Whether the drive check has been made, so the board knows the attack is
  /// ready to resolve rather than still owing a check.
  bool driveChecked = false;

  /// How many of this attack's drive checks have been flipped.
  ///
  /// They come one at a time -- a twin drive is two moments, and the first
  /// can change what the second is worth -- so the attack counts them off
  /// rather than being handed all of them at once.
  int drivesTaken = 0;

  bool get isVanguardAttack => attackerCircle == Circle.vanguard;

  bool get hitsVanguard => targetCircle == Circle.vanguard;

  /// The attacker's power plus the booster's, both as they stand.
  ///
  /// The booster's *current* power, not its printed one: a booster given
  /// +5000 pushes with that too -- an 8000 booster on a 5000 pump boosts for
  /// 13000 -- which is how the game works and what a deck built on pumping
  /// the back row is counting on.
  int get attackPower => attacker.power + (booster?.power ?? 0);

  int get shield =>
      guardians.fold(shieldBonus, (sum, card) => sum + card.shield);

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

  /// The cards this battle has turned face up, drive and damage together, in
  /// the order they were checked. Cleared when the next attack is declared.
  final List<CheckedCard> triggerZone = [];

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
