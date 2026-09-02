import '../games/game_definition.dart';

/// A plain text list, the format people paste into chats and forums.
String deckToText(GameDefinition game, DeckView view) {
  final lines = <String>[
    '${view.deck.name} — ${game.name} (${view.format.name})',
  ];
  for (final zoneId in view.format.zoneIds) {
    final count = view.zoneCount(zoneId);
    if (count == 0) continue;
    lines
      ..add('')
      ..add('${game.zone(zoneId)?.name ?? zoneId} ($count)');
    for (final group in game.groupZone(view, zoneId)) {
      for (final row in group.rows) {
        lines.add('${row.entry.quantity}x ${row.card.name}');
      }
    }
  }
  return lines.join('\n');
}
