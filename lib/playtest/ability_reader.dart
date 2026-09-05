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
/// The reach is small and worth stating plainly: about 580 cards of the 15,000
/// in the database have an ability this can play. It covers the common simple
/// shapes -- an on-attack pump, a draw on being ridden over, a continuous
/// bonus, a charge, the hollow keyword -- and the conditions the board can
/// actually answer: a named crest in the crest zone, a named vanguard of a
/// grade, a Generation Break, a drop that deep, whether the unit is hollowed,
/// whether its controller went second.
///
/// It still refuses everything that chooses a target, searches a deck, calls
/// a unit or asks the board something it cannot count.
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

  /// On becoming hollowed.
  onHollowed,

  /// On being discarded from hand to pay for a stride.
  onDiscardedForStride,

  /// At the beginning of the main phase.
  mainPhase,

  /// An [ACT] ability, played when its controller decides to.
  activated,

  /// A [CONT] ability, which is simply true while the unit stands there.
  continuous,
}

/// What has to be true for an ability to do anything.
///
/// The reader used to refuse every clause carrying a condition, which is most
/// of a real deck: a card that only works with its own crest out, or once the
/// drop is deep enough, reads as unplayable text. These are the conditions the
/// board can actually answer, and a clause carrying any other one is still
/// refused rather than assumed true.
class AbilityCondition {
  const AbilityCondition({
    this.crestNamed,
    this.vanguardNamed,
    this.vanguardGrade,
    this.hollowed = false,
    this.wentSecond = false,
    this.dropAtLeast,
    this.generationBreak,
  });

  /// A crest with this in its name has to be in the crest zone.
  ///
  /// Folded to lower case, as the whole clause is when it is read, so the
  /// board matches it without regard to case.
  final String? crestNamed;

  /// The vanguard has to carry this in its name, and be at least
  /// [vanguardGrade] where that is given too. Folded to lower case too.
  final String? vanguardNamed;
  final int? vanguardGrade;

  /// This unit has to be hollowed.
  final bool hollowed;

  /// Its controller has to have gone second.
  final bool wentSecond;

  /// The drop zone has to hold at least this many cards.
  final int? dropAtLeast;

  /// This many cards in the G zone have to be face up -- a Generation Break.
  final int? generationBreak;

  bool get isAlways =>
      crestNamed == null &&
      vanguardNamed == null &&
      vanguardGrade == null &&
      !hollowed &&
      !wentSecond &&
      dropAtLeast == null &&
      generationBreak == null;

  AbilityCondition merge(AbilityCondition other) => AbilityCondition(
    crestNamed: other.crestNamed ?? crestNamed,
    vanguardNamed: other.vanguardNamed ?? vanguardNamed,
    vanguardGrade: other.vanguardGrade ?? vanguardGrade,
    hollowed: hollowed || other.hollowed,
    wentSecond: wentSecond || other.wentSecond,
    dropAtLeast: other.dropAtLeast ?? dropAtLeast,
    generationBreak: other.generationBreak ?? generationBreak,
  );
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
    this.becomeHollowed = false,
    this.perFaceUpG = false,
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

  /// Whether the unit becomes hollowed: it fights this turn and is retired at
  /// the end of it. A Nightrose deck is built on the trade.
  final bool becomeHollowed;

  /// Whether the power is paid "for each face up card in your G zone", which
  /// multiplies it rather than adding it once.
  final bool perFaceUpG;

  bool get isNothing =>
      selfPower == 0 &&
      allPower == 0 &&
      frontRowPower == 0 &&
      critical == 0 &&
      draw == 0 &&
      soulCharge == 0 &&
      counterCharge == 0 &&
      energyCharge == 0 &&
      !becomeHollowed;

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
    becomeHollowed: becomeHollowed || other.becomeHollowed,
    perFaceUpG: perFaceUpG || other.perFaceUpG,
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
    this.condition = const AbilityCondition(),
  });

  final AbilityTiming timing;

  /// The circles it works from: 'VC', 'RC', 'GC'. Empty means the card did not
  /// say, which for these shapes means anywhere it can be.
  final Set<String> zones;

  final bool oncePerTurn;
  final AbilityCost cost;
  final AbilityEffect effect;

  /// What has to be true for it to happen at all.
  final AbilityCondition condition;

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
  r'^\[(auto|act|cont)\](\(([a-z/]{1,9})\))?'
  r'((?:\[1/turn\]|\[generation break \d+\])*):(.*)$',
);
final _costBlock = RegExp(r'\[cost\]((?:\[[^\]]+\])+),?\s*');

/// Splits a clause into its parts, leaving anything inside quotes alone.
///
/// Card names have commas in them -- "Vampire Princess of Night Fog,
/// Nightrose" -- so splitting on every comma cut the name in half and left
/// two halves that matched nothing at all.
List<String> _parts(String body) {
  final pieces = <String>[];
  final buffer = StringBuffer();
  var quoted = false;
  for (var i = 0; i < body.length; i += 1) {
    final char = body[i];
    if (char == '"') quoted = !quoted;
    if (!quoted && char == ',') {
      pieces.add(buffer.toString());
      buffer.clear();
      continue;
    }
    buffer.write(char);
  }
  pieces.add(buffer.toString());
  return [
    for (final piece in pieces)
      piece.trim().replaceFirst(RegExp(r'^(and|then)\s+'), '').trim(),
  ]..removeWhere((piece) => piece.isEmpty);
}

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
  RegExp(
    r'^(?:during your turn, )?all of your front row units get \[power\]'
    r'\+(\d+) for each face up card in your g zone$',
  ): (m) =>
      AbilityEffect(frontRowPower: int.parse(m.group(1)!), perFaceUpG: true),
  RegExp(r'^draw a card$'): (m) => const AbilityEffect(draw: 1),
  RegExp(r'^draw two cards$'): (m) => const AbilityEffect(draw: 2),
  RegExp(r'^\[soul-charge (\d+)\]$'): (m) =>
      AbilityEffect(soulCharge: int.parse(m.group(1)!)),
  RegExp(r'^\[counter-charge (\d+)\]$'): (m) =>
      AbilityEffect(counterCharge: int.parse(m.group(1)!)),
  RegExp(r'^\[energy-charge (\d+)\]$'): (m) =>
      AbilityEffect(energyCharge: int.parse(m.group(1)!)),
};

/// The conditions the board can answer. Anything else is refused.
final _conditionForms = <RegExp, AbilityCondition Function(Match)>{
  RegExp(r'^if you have an? "([^"]+)" crest$'): (m) =>
      AbilityCondition(crestNamed: m.group(1)),
  RegExp(
    r'^if you have a grade (\d+) or greater vanguard with "([^"]+)" in '
    r'its card name$',
  ): (m) => AbilityCondition(
    vanguardGrade: int.parse(m.group(1)!),
    vanguardNamed: m.group(2),
  ),
  RegExp(r'^if this unit is hollowed$'): (m) =>
      const AbilityCondition(hollowed: true),
  RegExp(r'^if you went second$'): (m) =>
      const AbilityCondition(wentSecond: true),
  RegExp(r'^if your drop has (\w+) or more cards$'): (m) {
    final many = _numberWords[m.group(1)];
    return many == null
        ? const AbilityCondition()
        : AbilityCondition(dropAtLeast: many);
  },
};

/// The number words the card text uses where it does not print a digit.
const _numberWords = <String, int>{
  'one': 1,
  'two': 2,
  'three': 3,
  'four': 4,
  'five': 5,
  'six': 6,
  'seven': 7,
  'eight': 8,
  'nine': 9,
  'ten': 10,
  'fifteen': 15,
  'twenty': 20,
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
  RegExp(r'^when this unit becomes hollowed$'): AbilityTiming.onHollowed,
  RegExp(
    r'^when this card is discarded from hand while paying the cost for '
    r'\[stride\]$',
  ): AbilityTiming.onDiscardedForStride,
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

/// The Hollow keyword, which is a clause with nothing in it but its own name
/// and a reminder: "[AUTO]:Hollow (When placed on (RC), you may have it become
/// hollowed. If you do, retire it at the end of turn)".
final _hollowKeyword = RegExp(r'^\[auto\]:hollow\b', caseSensitive: false);

/// One clause, or null where any part of it was not one of the known forms.
Ability? _readClause(String printed) {
  if (_hollowKeyword.hasMatch(printed.trim())) {
    return Ability(
      timing: AbilityTiming.onCall,
      zones: const {'RC'},
      oncePerTurn: false,
      cost: const AbilityCost(),
      effect: const AbilityEffect(becomeHollowed: true),
      text: printed.trim(),
    );
  }

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
  final markers = header.group(4) ?? '';
  final oncePerTurn = markers.contains('[1/turn]');
  // "[Generation Break 2]" is a condition written into the header: it works
  // once that many cards in the G zone are face up.
  final generationBreak = RegExp(r'\[generation break (\d+)\]')
      .firstMatch(markers);
  var condition = AbilityCondition(
    generationBreak: generationBreak == null
        ? null
        : int.parse(generationBreak.group(1)!),
  );
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

  for (final part in _parts(body.trim().replaceAll(RegExp(r'\.$'), ''))) {
    final read = _readEffect(part);
    if (read != null) {
      effect = effect.merge(read);
      continue;
    }
    final asked = _readCondition(part);
    if (asked != null) {
      condition = condition.merge(asked);
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
    condition: condition,
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

AbilityCondition? _readCondition(String part) {
  for (final entry in _conditionForms.entries) {
    final match = entry.key.firstMatch(part);
    if (match != null) {
      final read = entry.value(match);
      // A form that matched but could not read its own number is a refusal,
      // not a condition that is always true.
      return read.isAlways ? null : read;
    }
  }
  return null;
}

AbilityTiming? _readTiming(String part) {
  for (final entry in _timingForms.entries) {
    if (entry.key.hasMatch(part)) return entry.value;
  }
  return null;
}
