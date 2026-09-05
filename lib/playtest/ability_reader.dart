/// Reading card abilities out of the printed English.
///
/// Abilities in the database are prose written for a person -- "[AUTO](VC):When
/// this unit attacks a vanguard, this unit gets [Power]+5000 until end of that
/// battle." -- and nothing in the app encodes what they do. The board has
/// always left them to the player for that reason, but it left the CPU with
/// nothing at all: a deck built around its abilities played, against the CPU,
/// as a deck of vanilla bodies.
///
/// This reads the shapes that are unambiguous enough to execute and refuses
/// everything else. The refusal is the important half: a clause is played only
/// when every part of it -- the timing, the cost, and each effect -- is one of
/// the forms below, so a half-understood ability is never guessed at. What it
/// cannot read it hands back as text, to be applied by hand or not at all.
///
/// The reach is small and worth stating plainly: about 250 cards of the 15,000
/// in the database have an ability this can play. It covers the common simple
/// shapes -- an on-attack pump, a draw on being ridden over, a continuous
/// bonus, a charge -- and nothing that chooses a target, searches a deck,
/// calls a unit or reads the board.
library;

/// When an ability fires.
enum AbilityTiming {
  /// On being placed on the vanguard circle, by a ride.
  onRide,

  /// On being ridden over: the unit is on its way to the soul.
  onRodeUpon,

  /// On being called to a rear-guard circle.
  onCall,

  /// On being placed, where the card did not say which circle it means -- so
  /// it fires on a ride and on a call alike, subject to the zones it names.
  onPlaced,

  /// On declaring an attack.
  onAttack,

  /// On boosting the unit in front.
  onBoost,

  /// At the beginning of the main phase.
  mainPhase,

  /// An [ACT] ability, played when its controller decides to.
  activated,

  /// A [CONT] ability, which is simply true while the unit stands there.
  continuous,
}

/// What an ability costs. Everything is zero on an ability that is free.
class AbilityCost {
  const AbilityCost({
    this.counterBlast = 0,
    this.soulBlast = 0,
    this.energy = 0,
    this.discard = 0,
    this.restSelf = false,
  });

  final int counterBlast;
  final int soulBlast;
  final int energy;
  final int discard;
  final bool restSelf;

  bool get isFree =>
      counterBlast == 0 &&
      soulBlast == 0 &&
      energy == 0 &&
      discard == 0 &&
      !restSelf;
}

/// What an ability does, in the terms the engine can carry out.
class AbilityEffect {
  const AbilityEffect({
    this.selfPower = 0,
    this.allPower = 0,
    this.frontRowPower = 0,
    this.critical = 0,
    this.draw = 0,
    this.soulCharge = 0,
    this.counterCharge = 0,
    this.energyCharge = 0,
    this.untilEndOfBattle = false,
  });

  /// Power to the unit whose ability this is.
  final int selfPower;

  /// Power to every unit its controller has.
  final int allPower;

  /// Power to the front row alone.
  final int frontRowPower;

  final int critical;
  final int draw;
  final int soulCharge;
  final int counterCharge;
  final int energyCharge;

  /// Whether the power wears off at the end of the battle rather than the
  /// turn, which for an attacker is very nearly the same thing and for a
  /// booster is not.
  final bool untilEndOfBattle;

  bool get isNothing =>
      selfPower == 0 &&
      allPower == 0 &&
      frontRowPower == 0 &&
      critical == 0 &&
      draw == 0 &&
      soulCharge == 0 &&
      counterCharge == 0 &&
      energyCharge == 0;

  AbilityEffect merge(AbilityEffect other) => AbilityEffect(
    selfPower: selfPower + other.selfPower,
    allPower: allPower + other.allPower,
    frontRowPower: frontRowPower + other.frontRowPower,
    critical: critical + other.critical,
    draw: draw + other.draw,
    soulCharge: soulCharge + other.soulCharge,
    counterCharge: counterCharge + other.counterCharge,
    energyCharge: energyCharge + other.energyCharge,
    untilEndOfBattle: untilEndOfBattle || other.untilEndOfBattle,
  );
}

/// One ability the reader was able to follow all the way through.
class Ability {
  const Ability({
    required this.timing,
    required this.zones,
    required this.oncePerTurn,
    required this.cost,
    required this.effect,
    required this.text,
  });

  final AbilityTiming timing;

  /// The circles it works from: 'VC', 'RC', 'GC'. Empty means the card did not
  /// say, which for these shapes means anywhere it can be.
  final Set<String> zones;

  final bool oncePerTurn;
  final AbilityCost cost;
  final AbilityEffect effect;

  /// The clause as printed, for the log and for the once-a-turn bookkeeping.
  final String text;

  bool worksOn({required bool vanguard}) =>
      zones.isEmpty || zones.contains(vanguard ? 'VC' : 'RC');
}

/// Everything the reader made of one card: what it can play, and what it
/// could not follow.
class CardAbilities {
  const CardAbilities({required this.playable, required this.unread});

  final List<Ability> playable;

  /// Clauses the reader refused, as printed. Worth showing rather than
  /// swallowing: they are the reason a CPU board is doing less than the deck
  /// really does.
  final List<String> unread;

  static const CardAbilities none = CardAbilities(playable: [], unread: []);
}

final _reminder = RegExp(r'\([^)]{9,}\)');
final _header = RegExp(
  r'^\[(auto|act|cont)\](\(([a-z/]{1,9})\))?(\[1/turn\])?:(.*)$',
);
final _costBlock = RegExp(r'\[cost\]((?:\[[^\]]+\])+),?\s*');
final _splitter = RegExp(r',\s*and\s+|,\s*then\s+|,\s*');

final _costForms = <RegExp, AbilityCost Function(Match)>{
  RegExp(r'^\[counter-blast (\d+)\]$'): (m) =>
      AbilityCost(counterBlast: int.parse(m.group(1)!)),
  RegExp(r'^\[soul-blast (\d+)\]$'): (m) =>
      AbilityCost(soulBlast: int.parse(m.group(1)!)),
  RegExp(r'^\[energy-blast (\d+)\]$'): (m) =>
      AbilityCost(energy: int.parse(m.group(1)!)),
  RegExp(r'^\[discard a card from (?:your )?hand\]$'): (m) =>
      const AbilityCost(discard: 1),
  RegExp(r'^\[rest this unit\]$'): (m) => const AbilityCost(restSelf: true),
};

final _effectForms = <RegExp, AbilityEffect Function(Match)>{
  RegExp(
    r'^(?:during your turn, )?this unit gets \[power\]\+(\d+)'
    r'(?: until end of (turn|that battle))?$',
  ): (m) => AbilityEffect(
    selfPower: int.parse(m.group(1)!),
    untilEndOfBattle: m.group(2) == 'that battle',
  ),
  RegExp(r'^this unit gets \[critical\]\+(\d+)(?: until end of turn)?$'): (m) =>
      AbilityEffect(critical: int.parse(m.group(1)!)),
  RegExp(
    r'^(?:during your turn, )?all of your units get \[power\]\+(\d+)'
    r'(?: until end of turn)?$',
  ): (m) =>
      AbilityEffect(allPower: int.parse(m.group(1)!)),
  RegExp(
    r'^(?:during your turn, )?all of your front row units get \[power\]\+(\d+)'
    r'(?: until end of turn)?$',
  ): (m) =>
      AbilityEffect(frontRowPower: int.parse(m.group(1)!)),
  RegExp(r'^draw a card$'): (m) => const AbilityEffect(draw: 1),
  RegExp(r'^draw two cards$'): (m) => const AbilityEffect(draw: 2),
  RegExp(r'^\[soul-charge (\d+)\]$'): (m) =>
      AbilityEffect(soulCharge: int.parse(m.group(1)!)),
  RegExp(r'^\[counter-charge (\d+)\]$'): (m) =>
      AbilityEffect(counterCharge: int.parse(m.group(1)!)),
  RegExp(r'^\[energy-charge (\d+)\]$'): (m) =>
      AbilityEffect(energyCharge: int.parse(m.group(1)!)),
};

final _timingForms = <RegExp, AbilityTiming>{
  RegExp(r'^when this unit is placed on \(rc\)$'): AbilityTiming.onCall,
  RegExp(r'^when this unit is placed on \(vc\)$'): AbilityTiming.onRide,
  RegExp(r'^when placed$'): AbilityTiming.onPlaced,
  RegExp(r'^when this unit is placed$'): AbilityTiming.onPlaced,
  RegExp(r'^when this unit is rode upon$'): AbilityTiming.onRodeUpon,
  RegExp(r'^when rode upon$'): AbilityTiming.onRodeUpon,
  RegExp(r'^when this unit attacks(?: a vanguard)?$'): AbilityTiming.onAttack,
  RegExp(r'^when this unit boosts$'): AbilityTiming.onBoost,
  RegExp(r'^at the beginning of your main phase$'): AbilityTiming.mainPhase,
  RegExp(r'^during your turn$'): AbilityTiming.continuous,
};

/// Reads a card's printed abilities.
CardAbilities readAbilities(String effect) {
  final text = effect.trim();
  if (text.isEmpty) return CardAbilities.none;

  final playable = <Ability>[];
  final unread = <String>[];

  for (final printed in text.split('\n')) {
    final clause = printed.trim();
    if (clause.isEmpty || clause == '-') continue;
    final ability = _readClause(clause);
    if (ability == null) {
      unread.add(clause);
    } else {
      playable.add(ability);
    }
  }
  return CardAbilities(playable: playable, unread: unread);
}

/// One clause, or null where any part of it was not one of the known forms.
Ability? _readClause(String printed) {
  final line = printed
      .replaceAll(_reminder, '')
      .replaceAll('[Power] +', '[Power]+')
      .replaceAll('[Critical] +', '[Critical]+')
      .toLowerCase()
      .trim();

  final header = _header.firstMatch(line);
  if (header == null) return null;
  final kind = header.group(1)!;
  final zones = _zonesOf(header.group(3));
  final oncePerTurn = header.group(4) != null;
  var body = header.group(5)!;

  // The cost comes out first: it is bracketed, so it does not survive being
  // split on commas along with everything else.
  var cost = const AbilityCost();
  final costs = _costBlock.firstMatch(body);
  if (costs != null) {
    for (final part in RegExp(r'\[[^\]]+\]').allMatches(costs.group(1)!)) {
      final paid = _readCost(part.group(0)!);
      if (paid == null) return null;
      cost = AbilityCost(
        counterBlast: cost.counterBlast + paid.counterBlast,
        soulBlast: cost.soulBlast + paid.soulBlast,
        energy: cost.energy + paid.energy,
        discard: cost.discard + paid.discard,
        restSelf: cost.restSelf || paid.restSelf,
      );
    }
    body = body.replaceRange(costs.start, costs.end, '');
  }

  var timing = switch (kind) {
    'act' => AbilityTiming.activated,
    'cont' => AbilityTiming.continuous,
    _ => null,
  };
  var effect = const AbilityEffect();

  for (final piece
      in body.trim().replaceAll(RegExp(r'\.$'), '').split(_splitter)) {
    final part = piece.trim();
    if (part.isEmpty) continue;

    final read = _readEffect(part);
    if (read != null) {
      effect = effect.merge(read);
      continue;
    }
    final fires = _readTiming(part);
    if (fires != null) {
      // A [CONT] whose "during your turn" is the whole condition stays
      // continuous; anything else naming two timings is beyond this reader.
      if (timing != null && timing != AbilityTiming.continuous) return null;
      timing = fires == AbilityTiming.continuous && kind == 'cont'
          ? AbilityTiming.continuous
          : fires;
      continue;
    }
    return null; // A part of the clause the reader cannot follow.
  }

  if (timing == null || effect.isNothing) return null;
  // "When placed" on a card that only works from one circle can only have
  // meant that circle.
  if (timing == AbilityTiming.onPlaced && zones.length == 1) {
    timing = zones.first == 'VC' ? AbilityTiming.onRide : AbilityTiming.onCall;
  }
  // An [AUTO] with no timing of its own has nothing to fire on.
  if (kind == 'auto' && timing == AbilityTiming.continuous) return null;
  return Ability(
    timing: timing,
    zones: zones,
    oncePerTurn: oncePerTurn,
    cost: cost,
    effect: effect,
    text: printed.trim(),
  );
}

Set<String> _zonesOf(String? printed) {
  if (printed == null) return const {};
  final zones = <String>{};
  for (final part in printed.split('/')) {
    switch (part) {
      case 'vc':
        zones.add('VC');
      case 'rc':
        zones.add('RC');
      case 'gc':
        zones.add('GC');
      default:
        // An unknown zone -- (hand), (drop) -- is left as an empty set, which
        // the caller reads as "wherever", so it is refused here instead.
        return const {'?'};
    }
  }
  return zones;
}

AbilityCost? _readCost(String part) {
  for (final entry in _costForms.entries) {
    final match = entry.key.firstMatch(part);
    if (match != null) return entry.value(match);
  }
  return null;
}

AbilityEffect? _readEffect(String part) {
  for (final entry in _effectForms.entries) {
    final match = entry.key.firstMatch(part);
    if (match != null) return entry.value(match);
  }
  return null;
}

AbilityTiming? _readTiming(String part) {
  for (final entry in _timingForms.entries) {
    if (entry.key.hasMatch(part)) return entry.value;
  }
  return null;
}
