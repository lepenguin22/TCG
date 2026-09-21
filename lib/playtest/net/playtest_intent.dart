import '../playtest_state.dart';

/// Something a player asks to do.
///
/// A player's device never moves a card itself: it asks, and the device
/// running the game decides. That is what keeps the two boards the same, and
/// it is also the only honest way to run a game where one player's device
/// cannot be trusted with the other player's deck.
enum IntentKind {
  togglePick,
  confirmMulligan,
  ride,
  call,
  playOrder,
  playBlitz,
  activateFromDrop,
  discard,
  handToSoul,
  bottomDeck,
  drawCard,
  nextPhase,
  attack,
  guard,
  driveCheck,
  resolveAttack,
  toggleRest,
  retire,
  moveUnit,
  unitToSoul,
  setEnergy,
  shuffleDeck,
  addPower,
  addCritical,
}

/// One request, named and with its arguments.
///
/// The arguments are read back out by name and checked against the game
/// before anything happens, so a message that names a card the asker cannot
/// see, or a circle that is not a circle, does nothing at all.
class PlaytestIntent {
  const PlaytestIntent(
    this.kind, {
    this.card,
    this.circle,
    this.to,
    this.amount,
  });

  final IntentKind kind;

  /// A card, by instance id.
  final int? card;

  /// The circle a unit is called to, attacks from, or is otherwise named by.
  final Circle? circle;

  /// The circle an attack is aimed at.
  final Circle? to;

  /// A number: energy, power, however many.
  final int? amount;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    if (card != null) 'card': card,
    if (circle != null) 'circle': circle!.name,
    if (to != null) 'to': to!.name,
    if (amount != null) 'amount': amount,
  };

  /// Reads an intent off the wire, or nothing at all.
  ///
  /// Anything unrecognised comes back null rather than throwing: the far end
  /// is another program, possibly a newer version of this one, and a message
  /// this build cannot read is not a crash.
  static PlaytestIntent? fromJson(Map<String, Object?> json) {
    final kind = IntentKind.values
        .where((k) => k.name == json['kind'])
        .firstOrNull;
    if (kind == null) return null;
    return PlaytestIntent(
      kind,
      card: json['card'] is int ? json['card']! as int : null,
      circle: _circle(json['circle']),
      to: _circle(json['to']),
      amount: json['amount'] is int ? json['amount']! as int : null,
    );
  }

  static Circle? _circle(Object? name) =>
      Circle.values.where((c) => c.name == name).firstOrNull;
}
