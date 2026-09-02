import 'package:flutter/material.dart';

import '../../models/card_definition.dart';
import '../game_definition.dart';
import 'vanguard_data.dart';
import 'vanguard_rules.dart';

class VanguardGame extends GameDefinition {
  const VanguardGame();

  @override
  String get id => 'vanguard';

  @override
  String get name => 'Cardfight!! Vanguard';

  @override
  String get shortName => 'Vanguard';

  @override
  String get tagline => 'Stand up, my vanguard!';

  @override
  Color get accent => const Color(0xFFE4573D);

  @override
  List<ZoneDefinition> get zones => vanguardZones;

  @override
  List<FormatDefinition> get formats => vanguardFormats;

  @override
  String get defaultFormatId => formatStandard;

  @override
  List<CardField> get cardFields => vanguardFields;

  String _grade(CardDefinition card) => card.attributes['grade'] ?? '0';

  @override
  String groupOf(CardDefinition card, String zoneId) =>
      zoneId == zoneG ? 'G units' : 'Grade ${_grade(card)}';

  @override
  int compareGroups(String a, String b) => a.compareTo(b);

  @override
  int compareCards(CardDefinition a, CardDefinition b) {
    final gradeDelta =
        (int.tryParse(_grade(a)) ?? 0) - (int.tryParse(_grade(b)) ?? 0);
    if (gradeDelta != 0) return gradeDelta;
    final triggerDelta = (a.attributes['trigger'] ?? '').compareTo(
      b.attributes['trigger'] ?? '',
    );
    if (triggerDelta != 0) return triggerDelta;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  @override
  String describeCard(CardDefinition card) {
    final parts = <String>[];
    if (card.attributes['cardType'] == 'trigger' &&
        card.attribute('trigger') != null) {
      parts.add(
        '${optionLabel(triggerOptions, card.attributes['trigger'])} trigger',
      );
    } else {
      final type = optionLabel(cardTypeOptions, card.attributes['cardType']);
      if (type != null) parts.add(type);
    }
    final power = card.attribute('power');
    if (power != null) parts.add('$power power');
    final shield = card.attribute('shield');
    if (shield != null) parts.add('$shield shield');
    final nation = card.attribute('nation');
    if (nation != null && nation != 'none') {
      final label = optionLabel(nationOptions, nation);
      if (label != null) parts.add(label);
    }
    final clan = card.attribute('clan');
    if (clan != null) parts.add(clan);
    return parts.join(' · ');
  }

  @override
  CardBadge? badgeOf(CardDefinition card) {
    final trigger = card.attribute('trigger');
    if (card.attributes['cardType'] == 'trigger' && trigger != null) {
      final text = trigger == 'over' ? 'OV' : trigger[0].toUpperCase();
      return CardBadge(
        text,
        optionColor(triggerOptions, trigger) ?? const Color(0xFF7A8794),
      );
    }
    final grade = _grade(card);
    return CardBadge(
      'G$grade',
      optionColor(gradeOptions, grade) ?? const Color(0xFF7A8794),
    );
  }

  @override
  List<ValidationIssue> validate(DeckView view) => validateVanguard(view);

  @override
  List<StatGroup> stats(DeckView view) => vanguardStats(view);
}
