import 'package:flutter/material.dart';

import '../models/card_definition.dart';
import '../models/deck.dart';

enum FieldType { text, number, multiline, select }

class FieldOption {
  const FieldOption(this.value, this.label, {this.color});

  final String value;
  final String label;
  final Color? color;
}

/// Describes one game specific card attribute and how to edit it.
class CardField {
  const CardField({
    required this.key,
    required this.label,
    required this.type,
    this.options = const [],
    this.placeholder,
    this.helper,
    this.isRequired = false,
    this.promptWhenMissing = false,
    this.visibleWhenKey,
    this.visibleWhenValues = const [],
  });

  final String key;
  final String label;
  final FieldType type;
  final List<FieldOption> options;
  final String? placeholder;
  final String? helper;
  final bool isRequired;

  /// Ask for this field when a card comes from the catalog without it. Used
  /// for attributes the catalog cannot supply but the rules depend on.
  final bool promptWhenMissing;

  /// Only show the field while [visibleWhenKey] holds one of
  /// [visibleWhenValues].
  final String? visibleWhenKey;
  final List<String> visibleWhenValues;

  bool isVisible(Map<String, String> attributes) {
    final key = visibleWhenKey;
    if (key == null) return true;
    return visibleWhenValues.contains(attributes[key] ?? '');
  }
}

class ZoneDefinition {
  const ZoneDefinition({
    required this.id,
    required this.name,
    required this.shortName,
    required this.description,
  });

  final String id;
  final String name;
  final String shortName;
  final String description;
}

class ZoneTarget {
  const ZoneTarget({this.exact, this.max});

  /// The zone must hold exactly this many cards.
  final int? exact;

  /// The zone may hold at most this many cards.
  final int? max;

  int? get goal => exact ?? max;
}

class FormatDefinition {
  const FormatDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.zoneIds,
    this.targets = const {},
  });

  final String id;
  final String name;
  final String description;
  final List<String> zoneIds;
  final Map<String, ZoneTarget> targets;
}

enum IssueLevel { error, warning }

class ValidationIssue {
  const ValidationIssue(this.level, this.message);

  const ValidationIssue.error(this.message) : level = IssueLevel.error;

  const ValidationIssue.warning(this.message) : level = IssueLevel.warning;

  final IssueLevel level;
  final String message;
}

class StatBar {
  const StatBar(this.label, this.value, {this.color});

  final String label;
  final int value;
  final Color? color;
}

class StatGroup {
  const StatGroup({required this.title, required this.bars, this.caption});

  final String title;
  final String? caption;
  final List<StatBar> bars;
}

class CardBadge {
  const CardBadge(this.text, this.color);

  final String text;
  final Color color;
}

class DeckItem {
  const DeckItem(this.entry, this.card);

  final DeckEntry entry;
  final CardDefinition card;
}

/// A deck plus its resolved cards — the input to rules, stats and grouping.
class DeckView {
  const DeckView({
    required this.deck,
    required this.format,
    required this.items,
  });

  final Deck deck;
  final FormatDefinition format;
  final List<DeckItem> items;

  Iterable<DeckItem> inZone(String zoneId) =>
      items.where((item) => item.entry.zoneId == zoneId);

  int zoneCount(String zoneId) =>
      inZone(zoneId).fold(0, (sum, item) => sum + item.entry.quantity);

  int get totalCount => items.fold(0, (sum, item) => sum + item.entry.quantity);

  int get distinctCount => items.length;
}

/// One group of cards inside a zone, ready to render.
class CardGroup {
  const CardGroup(this.title, this.rows);

  final String title;
  final List<DeckItem> rows;

  int get count => rows.fold(0, (sum, row) => sum + row.entry.quantity);
}

/// Everything the screens need to know about a trading card game.
///
/// The UI is generic: it renders whatever a `GameDefinition` describes. Adding
/// another TCG means writing one of these and registering it in `games.dart`.
abstract class GameDefinition {
  const GameDefinition();

  String get id;
  String get name;
  String get shortName;
  String get tagline;
  Color get accent;

  List<ZoneDefinition> get zones;
  List<FormatDefinition> get formats;
  String get defaultFormatId;
  List<CardField> get cardFields;

  /// Bundled catalog of real printed cards for this game, or null when the
  /// game has none and cards must be entered by hand.
  String? get catalogAsset => null;

  /// Heading a card is listed under inside a zone (e.g. "Grade 2").
  String groupOf(CardDefinition card, String zoneId);

  /// Sort order for group headings.
  int compareGroups(String a, String b);

  /// Sort order for cards inside a group.
  int compareCards(CardDefinition a, CardDefinition b);

  /// One line summary shown under a card's name.
  String describeCard(CardDefinition card);

  /// Small coloured badge shown next to a card's name.
  CardBadge? badgeOf(CardDefinition card);

  /// Deck construction rules for the deck's format.
  List<ValidationIssue> validate(DeckView view);

  /// Charts for the deck breakdown screen.
  List<StatGroup> stats(DeckView view);

  ZoneDefinition? zone(String zoneId) {
    for (final zone in zones) {
      if (zone.id == zoneId) return zone;
    }
    return null;
  }

  FormatDefinition format(String formatId) {
    for (final format in formats) {
      if (format.id == formatId) return format;
    }
    return formats.first;
  }

  /// Cards grouped for display inside one zone, sorted by the game's rules.
  List<CardGroup> groupZone(DeckView view, String zoneId) {
    final groups = <String, List<DeckItem>>{};
    for (final item in view.inZone(zoneId)) {
      groups.putIfAbsent(groupOf(item.card, zoneId), () => []).add(item);
    }
    final titles = groups.keys.toList()..sort(compareGroups);
    return [
      for (final title in titles)
        CardGroup(
          title,
          groups[title]!..sort((a, b) => compareCards(a.card, b.card)),
        ),
    ];
  }
}

String? optionLabel(List<FieldOption> options, String? value) {
  if (value == null || value.isEmpty) return null;
  for (final option in options) {
    if (option.value == value) return option.label;
  }
  return value;
}

Color? optionColor(List<FieldOption> options, String? value) {
  if (value == null || value.isEmpty) return null;
  for (final option in options) {
    if (option.value == value) return option.color;
  }
  return null;
}
