import '../../models/card_definition.dart';
import '../playtest_state.dart';

/// What one device tells another about the game they are playing.
///
/// Two devices cannot share the board itself: it is a graph of live objects,
/// half of which one player is not allowed to see. So the device running the
/// game sends each player a picture of it -- everything that player is
/// entitled to see and nothing else -- and each player sends back what they
/// want to do. This file is that picture and those requests, as JSON.
///
/// Cards travel as their instance id. A card the viewer may see also travels
/// with its face; a card they may not see travels as an id with no face,
/// which is a card lying face down on a real table. Deciding what to send is
/// [snapshotFor], and it is the only place in the app where one player's
/// secrets are kept from another.

/// A card as it is sent: enough for the other device to draw it and to read
/// its abilities, which is everything the board does with a card.
class CardFace {
  const CardFace({
    required this.instanceId,
    required this.name,
    required this.attributes,
  });

  final int instanceId;
  final String name;
  final Map<String, String> attributes;

  static CardFace of(GameCard card) => CardFace(
    instanceId: card.instanceId,
    name: card.name,
    attributes: card.card.attributes,
  );

  /// The card as the board's own type, so the far device renders it with the
  /// same code as a card of its own.
  GameCard toGameCard(String gameId) => GameCard(
    instanceId,
    CardDefinition(
      id: 'wire:$instanceId',
      gameId: gameId,
      name: name,
      attributes: attributes,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    ),
  );

  Map<String, Object?> toJson() => {
    'id': instanceId,
    'name': name,
    'attributes': attributes,
  };

  static CardFace fromJson(Map<String, Object?> json) => CardFace(
    instanceId: json['id']! as int,
    name: json['name'] as String? ?? '',
    attributes: {
      for (final entry in (json['attributes'] as Map? ?? {}).entries)
        '${entry.key}': '${entry.value}',
    },
  );
}

/// A unit standing on a circle, and what this turn has done to it.
class UnitSnapshot {
  const UnitSnapshot({
    required this.cardId,
    required this.rested,
    required this.locked,
    required this.hollowed,
    required this.grantedBoost,
    required this.powerBonus,
    required this.criticalBonus,
    required this.driveBonus,
    required this.battleBonus,
  });

  final int cardId;
  final bool rested;
  final bool locked;
  final bool hollowed;
  final bool grantedBoost;
  final int powerBonus;
  final int criticalBonus;
  final int driveBonus;
  final int battleBonus;

  static UnitSnapshot of(FieldUnit unit) => UnitSnapshot(
    cardId: unit.card.instanceId,
    rested: unit.rested,
    locked: unit.locked,
    hollowed: unit.hollowed,
    grantedBoost: unit.grantedBoost,
    powerBonus: unit.powerBonus,
    criticalBonus: unit.criticalBonus,
    driveBonus: unit.driveBonus,
    battleBonus: unit.battleBonus,
  );

  Map<String, Object?> toJson() => {
    'card': cardId,
    'rested': rested,
    'locked': locked,
    'hollowed': hollowed,
    'grantedBoost': grantedBoost,
    'power': powerBonus,
    'critical': criticalBonus,
    'drive': driveBonus,
    'battle': battleBonus,
  };

  static UnitSnapshot fromJson(Map<String, Object?> json) => UnitSnapshot(
    cardId: json['card']! as int,
    rested: json['rested'] as bool? ?? false,
    locked: json['locked'] as bool? ?? false,
    hollowed: json['hollowed'] as bool? ?? false,
    grantedBoost: json['grantedBoost'] as bool? ?? false,
    powerBonus: json['power'] as int? ?? 0,
    criticalBonus: json['critical'] as int? ?? 0,
    driveBonus: json['drive'] as int? ?? 0,
    battleBonus: json['battle'] as int? ?? 0,
  );
}

/// One player's half of the board, as the viewer is allowed to see it.
///
/// Zones are lists of instance ids. Whether the viewer also gets the faces
/// for those ids is what makes a zone public or private, and that is decided
/// once, in [snapshotFor].
class SideSnapshot {
  const SideSnapshot({
    required this.name,
    required this.handIds,
    required this.deckCount,
    required this.rideDeckIds,
    required this.rideDeckCount,
    required this.units,
    required this.heartId,
    required this.damageIds,
    required this.spentDamage,
    required this.dropIds,
    required this.soulIds,
    required this.gZoneIds,
    required this.faceUpG,
    required this.removedIds,
    required this.crestIds,
    required this.energy,
    required this.energyCap,
    required this.goesFirst,
  });

  final String name;

  /// The cards in hand, by id. The viewer's own hand comes with faces; the
  /// other player's comes as ids alone, which is a row of cards held up
  /// backwards.
  final List<int> handIds;

  /// The deck is a count and nothing else. Its order is the one thing in the
  /// game that not even its owner is allowed to know.
  final int deckCount;

  /// The ride deck is face down and private, so the owner sees ids and the
  /// other player sees only how many are left.
  final List<int> rideDeckIds;
  final int rideDeckCount;

  final Map<Circle, UnitSnapshot> units;
  final int? heartId;
  final List<int> damageIds;
  final List<int> spentDamage;
  final List<int> dropIds;
  final List<int> soulIds;
  final List<int> gZoneIds;
  final List<int> faceUpG;
  final List<int> removedIds;
  final List<int> crestIds;
  final int energy;
  final int energyCap;
  final bool goesFirst;

  int get handCount => handIds.length;

  Map<String, Object?> toJson() => {
    'name': name,
    'hand': handIds,
    'deck': deckCount,
    'rideDeck': rideDeckIds,
    'rideDeckCount': rideDeckCount,
    'units': {
      for (final entry in units.entries) entry.key.name: entry.value.toJson(),
    },
    'heart': heartId,
    'damage': damageIds,
    'spent': spentDamage,
    'drop': dropIds,
    'soul': soulIds,
    'gZone': gZoneIds,
    'faceUpG': faceUpG,
    'removed': removedIds,
    'crest': crestIds,
    'energy': energy,
    'energyCap': energyCap,
    'goesFirst': goesFirst,
  };

  static SideSnapshot fromJson(Map<String, Object?> json) => SideSnapshot(
    name: json['name'] as String? ?? '',
    handIds: _ids(json['hand']),
    deckCount: json['deck'] as int? ?? 0,
    rideDeckIds: _ids(json['rideDeck']),
    rideDeckCount: json['rideDeckCount'] as int? ?? 0,
    units: {
      for (final entry in (json['units'] as Map? ?? {}).entries)
        _circle('${entry.key}'): UnitSnapshot.fromJson(
          (entry.value as Map).cast<String, Object?>(),
        ),
    },
    heartId: json['heart'] as int?,
    damageIds: _ids(json['damage']),
    spentDamage: _ids(json['spent']),
    dropIds: _ids(json['drop']),
    soulIds: _ids(json['soul']),
    gZoneIds: _ids(json['gZone']),
    faceUpG: _ids(json['faceUpG']),
    removedIds: _ids(json['removed']),
    crestIds: _ids(json['crest']),
    energy: json['energy'] as int? ?? 0,
    energyCap: json['energyCap'] as int? ?? PlaytestSide.baseEnergyCap,
    goesFirst: json['goesFirst'] as bool? ?? false,
  );
}

/// The attack on the table, if there is one.
class AttackSnapshot {
  const AttackSnapshot({
    required this.attackerCircle,
    required this.targetCircle,
    required this.boosterCircle,
    required this.guardianIds,
    required this.perfectGuarded,
    required this.driveChecked,
    required this.drivesTaken,
    required this.attackPower,
    required this.defence,
  });

  final Circle attackerCircle;
  final Circle targetCircle;
  final Circle? boosterCircle;
  final List<int> guardianIds;
  final bool perfectGuarded;
  final bool driveChecked;
  final int drivesTaken;
  final int attackPower;
  final int defence;

  static AttackSnapshot of(PendingAttack attack, PlaytestState state) =>
      AttackSnapshot(
        attackerCircle: attack.attackerCircle,
        targetCircle: attack.targetCircle,
        boosterCircle: attack.booster == null
            ? null
            : attack.attackerCircle.boostedBy,
        guardianIds: [for (final card in attack.guardians) card.instanceId],
        perfectGuarded: attack.perfectGuarded,
        driveChecked: attack.driveChecked,
        drivesTaken: attack.drivesTaken,
        attackPower: attack.attackPower,
        defence: attack.defence,
      );

  Map<String, Object?> toJson() => {
    'from': attackerCircle.name,
    'to': targetCircle.name,
    'booster': boosterCircle?.name,
    'guardians': guardianIds,
    'perfect': perfectGuarded,
    'drove': driveChecked,
    'drives': drivesTaken,
    'power': attackPower,
    'defence': defence,
  };

  static AttackSnapshot fromJson(Map<String, Object?> json) => AttackSnapshot(
    attackerCircle: _circle(json['from'] as String? ?? ''),
    targetCircle: _circle(json['to'] as String? ?? ''),
    boosterCircle: json['booster'] == null
        ? null
        : _circle(json['booster']! as String),
    guardianIds: _ids(json['guardians']),
    perfectGuarded: json['perfect'] as bool? ?? false,
    driveChecked: json['drove'] as bool? ?? false,
    drivesTaken: json['drives'] as int? ?? 0,
    attackPower: json['power'] as int? ?? 0,
    defence: json['defence'] as int? ?? 0,
  );
}

/// A card a check has turned face up, which both players see.
class CheckSnapshot {
  const CheckSnapshot({
    required this.cardId,
    required this.kind,
    required this.sideName,
  });

  final int cardId;
  final CheckKind kind;
  final String sideName;

  Map<String, Object?> toJson() => {
    'card': cardId,
    'kind': kind.name,
    'side': sideName,
  };

  static CheckSnapshot fromJson(Map<String, Object?> json) => CheckSnapshot(
    cardId: json['card']! as int,
    kind: CheckKind.values.firstWhere(
      (k) => k.name == json['kind'],
      orElse: () => CheckKind.drive,
    ),
    sideName: json['side'] as String? ?? '',
  );
}

/// The whole board, from one player's seat.
///
/// [me] is always the player this snapshot was made for, so the far device
/// draws its own side at the bottom without having to work out which one it
/// is.
class PlaytestSnapshot {
  const PlaytestSnapshot({
    required this.me,
    required this.them,
    required this.faces,
    required this.turn,
    required this.phase,
    required this.activeName,
    required this.ridden,
    required this.attack,
    required this.triggerZone,
    required this.log,
    required this.winnerName,
  });

  final SideSnapshot me;
  final SideSnapshot them;

  /// The identities of every card in this snapshot the viewer may see. An id
  /// with no face here is a card lying face down.
  final Map<int, CardFace> faces;

  final int turn;
  final PlaytestPhase phase;
  final String activeName;
  final bool ridden;
  final AttackSnapshot? attack;
  final List<CheckSnapshot> triggerZone;
  final List<String> log;
  final String? winnerName;

  bool get myTurn => activeName == me.name;

  /// Whether the viewer may see what this card is.
  bool knows(int instanceId) => faces.containsKey(instanceId);

  Map<String, Object?> toJson() => {
    'me': me.toJson(),
    'them': them.toJson(),
    'faces': [for (final face in faces.values) face.toJson()],
    'turn': turn,
    'phase': phase.name,
    'active': activeName,
    'ridden': ridden,
    'attack': attack?.toJson(),
    'checks': [for (final check in triggerZone) check.toJson()],
    'log': log,
    'winner': winnerName,
  };

  static PlaytestSnapshot fromJson(Map<String, Object?> json) {
    final faces = <int, CardFace>{};
    for (final entry in (json['faces'] as List? ?? const [])) {
      final face = CardFace.fromJson((entry as Map).cast<String, Object?>());
      faces[face.instanceId] = face;
    }
    return PlaytestSnapshot(
      me: SideSnapshot.fromJson((json['me']! as Map).cast<String, Object?>()),
      them: SideSnapshot.fromJson(
        (json['them']! as Map).cast<String, Object?>(),
      ),
      faces: faces,
      turn: json['turn'] as int? ?? 0,
      phase: PlaytestPhase.values.firstWhere(
        (p) => p.name == json['phase'],
        orElse: () => PlaytestPhase.mulligan,
      ),
      activeName: json['active'] as String? ?? '',
      ridden: json['ridden'] as bool? ?? false,
      attack: json['attack'] == null
          ? null
          : AttackSnapshot.fromJson(
              (json['attack']! as Map).cast<String, Object?>(),
            ),
      triggerZone: [
        for (final entry in (json['checks'] as List? ?? const []))
          CheckSnapshot.fromJson((entry as Map).cast<String, Object?>()),
      ],
      log: [for (final line in (json['log'] as List? ?? const [])) '$line'],
      winnerName: json['winner'] as String?,
    );
  }
}

/// How many lines of the log travel with a snapshot. The whole thing would
/// grow without bound, and nobody reads the first turn again.
const logTail = 60;

/// The board as [viewer] is entitled to see it.
///
/// The rule this file exists for: a card's face is sent only to a player who
/// may see it. Everything on the field, in the drop, the soul, the damage,
/// the G zone, the crest zone and the trigger zone is public and goes to
/// both. A hand goes to its owner. A ride deck goes to its owner. A deck goes
/// to nobody, because its order is not even its owner's to know.
PlaytestSnapshot snapshotFor(PlaytestState state, PlaytestSide viewer) {
  final foe = viewer == state.you ? state.opponent : state.you;
  final faces = <int, CardFace>{};

  void reveal(Iterable<GameCard> cards) {
    for (final card in cards) {
      faces[card.instanceId] = CardFace.of(card);
    }
  }

  // Public everywhere: what is on the table for both players to read.
  for (final side in [viewer, foe]) {
    reveal([for (final unit in side.field.values) unit.card]);
    if (side.heart != null) reveal([side.heart!.card]);
    reveal(side.damage);
    reveal(side.drop);
    reveal(side.soul);
    // The G zone is open information in the game: either player may look
    // through it, face-down cards included.
    reveal(side.gZone);
    reveal(side.removed);
    reveal(side.crestZone);
  }
  reveal([for (final check in state.triggerZone) check.card]);
  if (state.attack != null) reveal(state.attack!.guardians);

  // And the viewer's own, which the other player does not get.
  reveal(viewer.hand);
  reveal(viewer.rideDeck);

  return PlaytestSnapshot(
    me: _sideSnapshot(viewer, ownedByViewer: true),
    them: _sideSnapshot(foe, ownedByViewer: false),
    faces: faces,
    turn: state.turn,
    phase: state.phase,
    activeName: state.active.name,
    ridden: state.ridden,
    attack: state.attack == null
        ? null
        : AttackSnapshot.of(state.attack!, state),
    triggerZone: [
      for (final check in state.triggerZone)
        CheckSnapshot(
          cardId: check.card.instanceId,
          kind: check.kind,
          sideName: check.sideName,
        ),
    ],
    log: [
      for (final entry
          in state.log.length > logTail
              ? state.log.sublist(state.log.length - logTail)
              : state.log)
        entry.text,
    ],
    winnerName: state.winner?.name,
  );
}

SideSnapshot _sideSnapshot(PlaytestSide side, {required bool ownedByViewer}) =>
    SideSnapshot(
      name: side.name,
      handIds: [for (final card in side.hand) card.instanceId],
      deckCount: side.deck.length,
      rideDeckIds: ownedByViewer
          ? [for (final card in side.rideDeck) card.instanceId]
          : const [],
      rideDeckCount: side.rideDeck.length,
      units: {
        for (final entry in side.field.entries)
          entry.key: UnitSnapshot.of(entry.value),
      },
      heartId: side.heart?.card.instanceId,
      damageIds: [for (final card in side.damage) card.instanceId],
      spentDamage: side.spentDamage.toList(),
      dropIds: [for (final card in side.drop) card.instanceId],
      soulIds: [for (final card in side.soul) card.instanceId],
      gZoneIds: [for (final card in side.gZone) card.instanceId],
      faceUpG: side.faceUpG.toList(),
      removedIds: [for (final card in side.removed) card.instanceId],
      crestIds: [for (final card in side.crestZone) card.instanceId],
      energy: side.energy,
      energyCap: side.energyCap,
      goesFirst: side.goesFirst,
    );

List<int> _ids(Object? value) => [
  for (final each in (value as List? ?? const [])) each as int,
];

Circle _circle(String name) => Circle.values.firstWhere(
  (c) => c.name == name,
  orElse: () => Circle.vanguard,
);
