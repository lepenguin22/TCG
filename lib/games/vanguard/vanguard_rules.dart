import '../../models/card_definition.dart';
import '../game_definition.dart';
import 'vanguard_data.dart';

bool isTrigger(CardDefinition card) =>
    card.attributes['cardType'] == 'trigger' &&
    (card.attribute('trigger') != null);

Map<String, int> _tally(
  Iterable<DeckItem> items,
  String? Function(CardDefinition card) pick,
) {
  final out = <String, int>{};
  for (final item in items) {
    final key = pick(item.card);
    if (key == null) continue;
    out[key] = (out[key] ?? 0) + item.entry.quantity;
  }
  return out;
}

/// Copies of each card *name*, which is what the four-copy rule counts.
Map<String, int> _copiesByName(Iterable<DeckItem> items) {
  final out = <String, int>{};
  for (final item in items) {
    final key = item.card.name.trim().toLowerCase();
    if (key.isEmpty) continue;
    out[key] = (out[key] ?? 0) + item.entry.quantity;
  }
  return out;
}

String _displayName(Iterable<DeckItem> items, String lowerName) {
  for (final item in items) {
    if (item.card.name.trim().toLowerCase() == lowerName) return item.card.name;
  }
  return lowerName;
}

int _count(Iterable<DeckItem> items) =>
    items.fold(0, (sum, item) => sum + item.entry.quantity);

List<ValidationIssue> validateVanguard(DeckView view) {
  final issues = <ValidationIssue>[];
  final formatId = view.format.id;
  final ride = view.inZone(zoneRide).toList();
  final main = view.inZone(zoneMain).toList();
  final gZone = view.inZone(zoneG).toList();
  final rideCount = _count(ride);
  final mainCount = _count(main);
  final gCount = _count(gZone);
  final strict = formatId != formatCasual;

  if (view.items.isEmpty) {
    return [
      const ValidationIssue.warning(
        'This deck is empty. Add cards to start checking it against the rules.',
      ),
    ];
  }

  // --- Deck sizes ---------------------------------------------------------
  if (strict && mainCount != 50) {
    issues.add(
      ValidationIssue.error(
        'Main deck holds $mainCount cards. It must hold exactly 50.',
      ),
    );
  }

  if (formatId == formatStandard) {
    if (rideCount != 4) {
      issues.add(
        ValidationIssue.error(
          'Ride deck holds $rideCount cards. It must hold exactly 4.',
        ),
      );
    }
    final rideGrades = _tally(ride, (card) => card.attributes['grade']);
    for (final grade in ['0', '1', '2', '3']) {
      final n = rideGrades[grade] ?? 0;
      if (n == 0) {
        issues.add(
          ValidationIssue.error('Ride deck is missing its grade $grade card.'),
        );
      } else if (n > 1) {
        issues.add(
          ValidationIssue.error(
            'Ride deck has $n grade $grade cards. It takes exactly one of each grade 0-3.',
          ),
        );
      }
    }
    for (final item in ride.where((item) => isTrigger(item.card))) {
      issues.add(
        ValidationIssue.error(
          '"${item.card.name}" is a trigger unit, so it cannot go in the ride deck.',
        ),
      );
    }
    for (final item in [...ride, ...main]) {
      if (item.card.attributes['grade'] == '4' ||
          item.card.attributes['cardType'] == 'g-unit') {
        issues.add(
          ValidationIssue.error(
            '"${item.card.name}" is a G unit, which is Premium only.',
          ),
        );
      }
    }
    if (gCount > 0) {
      issues.add(
        const ValidationIssue.error(
          'Standard decks do not use a G zone. Switch the deck to Premium or move those cards out.',
        ),
      );
    }
  }

  if (formatId == formatPremium) {
    if (gCount > 16) {
      issues.add(
        ValidationIssue.error('G zone holds $gCount cards. The limit is 16.'),
      );
    } else if (gCount > 0 && gCount < 16) {
      issues.add(
        ValidationIssue.warning('G zone holds $gCount of a possible 16 cards.'),
      );
    }
    for (final item in gZone) {
      if (item.card.attributes['grade'] != '4' &&
          item.card.attributes['cardType'] != 'g-unit') {
        issues.add(
          ValidationIssue.error(
            '"${item.card.name}" is not a G unit, so it cannot go in the G zone.',
          ),
        );
      }
    }
    for (final item in main) {
      if (item.card.attributes['grade'] == '4' ||
          item.card.attributes['cardType'] == 'g-unit') {
        issues.add(
          ValidationIssue.error(
            '"${item.card.name}" is a G unit and belongs in the G zone, not the main deck.',
          ),
        );
      }
    }
    final mainGrades = _tally(main, (card) => card.attributes['grade']);
    if ((mainGrades['0'] ?? 0) == 0) {
      issues.add(
        const ValidationIssue.error(
          'Premium decks need a grade 0 in the main deck to use as the first vanguard.',
        ),
      );
    }
    if (rideCount > 0) {
      issues.add(
        const ValidationIssue.warning(
          'Premium does not use a ride deck. Those cards are not counted towards the main deck.',
        ),
      );
    }
  }

  // --- Four copies of a name ----------------------------------------------
  final inPlay = [...ride, ...main];
  _copiesByName(inPlay).forEach((name, count) {
    if (count > 4) {
      final message =
          '"${_displayName(inPlay, name)}" appears $count times. Only 4 copies of a card name are allowed.';
      issues.add(
        strict
            ? ValidationIssue.error(message)
            : ValidationIssue.warning(message),
      );
    }
  });
  _copiesByName(gZone).forEach((name, count) {
    if (count > 4) {
      final message =
          '"${_displayName(gZone, name)}" appears $count times in the G zone. Only 4 copies of a card name are allowed.';
      issues.add(
        strict
            ? ValidationIssue.error(message)
            : ValidationIssue.warning(message),
      );
    }
  });

  // --- Triggers -----------------------------------------------------------
  final triggers = main.where((item) => isTrigger(item.card)).toList();
  final triggerCount = _count(triggers);
  final byTrigger = _tally(triggers, (card) => card.attributes['trigger']);
  final heal = byTrigger['heal'] ?? 0;
  final over = byTrigger['over'] ?? 0;

  if (strict && triggerCount != 16) {
    issues.add(
      ValidationIssue.error(
        'Main deck has $triggerCount trigger units. A legal deck runs exactly 16.',
      ),
    );
  }
  if (heal > 4) {
    issues.add(ValidationIssue.error('$heal heal triggers. The limit is 4.'));
  }
  if (over > 1) {
    issues.add(ValidationIssue.error('$over over triggers. The limit is 1.'));
  }

  // --- Soft advice --------------------------------------------------------
  if (strict && mainCount > 0) {
    final mainGrades = _tally(main, (card) => card.attributes['grade']);
    final sentinels = _count(
      main.where((item) => item.card.attributes['cardType'] == 'sentinel'),
    );
    if (sentinels == 0) {
      issues.add(
        const ValidationIssue.warning(
          'No sentinels in the main deck. Most lists run 4 perfect guards.',
        ),
      );
    } else if (sentinels > 4) {
      issues.add(
        ValidationIssue.warning(
          '$sentinels sentinels. Only 4 copies of one name are legal, so check these are different cards.',
        ),
      );
    }
    if ((mainGrades['3'] ?? 0) == 0) {
      issues.add(
        const ValidationIssue.warning('No grade 3s in the main deck.'),
      );
    }
  }

  return issues;
}

List<StatGroup> vanguardStats(DeckView view) {
  final main = view.inZone(zoneMain).toList();
  final everything = [...main, ...view.inZone(zoneRide), ...view.inZone(zoneG)];
  final groups = <StatGroup>[];

  final grades = _tally(main, (card) => card.attributes['grade'] ?? '0');
  groups.add(
    StatGroup(
      title: 'Grade curve',
      caption: '${_count(main)} cards in the main deck',
      bars: [
        for (final option in gradeOptions)
          if (option.value != '4' || (grades['4'] ?? 0) > 0)
            StatBar(
              'Grade ${option.value}',
              grades[option.value] ?? 0,
              color: option.color,
            ),
      ],
    ),
  );

  final triggerItems = main.where((item) => isTrigger(item.card)).toList();
  final triggers = _tally(triggerItems, (card) => card.attributes['trigger']);
  groups.add(
    StatGroup(
      title: 'Triggers',
      caption: '${_count(triggerItems)} of 16',
      bars: [
        for (final option in triggerOptions)
          if ((triggers[option.value] ?? 0) > 0 ||
              const {'critical', 'draw', 'heal'}.contains(option.value))
            StatBar(
              option.label,
              triggers[option.value] ?? 0,
              color: option.color,
            ),
      ],
    ),
  );

  final types = _tally(everything, (card) => card.attributes['cardType']);
  groups.add(
    StatGroup(
      title: 'Card types',
      bars: [
        for (final option in cardTypeOptions)
          if ((types[option.value] ?? 0) > 0)
            StatBar(option.label, types[option.value]!),
      ],
    ),
  );

  final nations = _tally(everything, (card) => card.attributes['nation']);
  final nationBars = [
    for (final option in nationOptions)
      if ((nations[option.value] ?? 0) > 0)
        StatBar(option.label, nations[option.value]!, color: option.color),
  ];
  if (nationBars.isNotEmpty) {
    groups.add(StatGroup(title: 'Nations', bars: nationBars));
  }

  return groups;
}
