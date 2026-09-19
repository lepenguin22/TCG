import '../../games/game_definition.dart';
import '../../models/card_definition.dart';
import '../../models/deck.dart';

/// A deck as it travels to the other device.
///
/// The cards go along with it rather than their names alone. Both devices
/// bundle the same card database, so names would nearly always resolve -- but
/// nearly is not good enough when a card the host cannot find is a card
/// missing from a game in progress, and a hand-entered card would never
/// resolve at all. So a deck carries what it is made of.
class WireDeck {
  const WireDeck({required this.name, required this.items});

  final String name;
  final List<WireDeckItem> items;

  static WireDeck of(DeckView view) => WireDeck(
    name: view.deck.name,
    items: [
      for (final item in view.items)
        WireDeckItem(
          zoneId: item.entry.zoneId,
          quantity: item.entry.quantity,
          name: item.card.name,
          attributes: item.card.attributes,
        ),
    ],
  );

  /// The deck as the engine deals it: entries and the cards they name.
  ///
  /// The cards are built here rather than looked up, so nothing of the other
  /// player's deck is written into this device's library. They exist for the
  /// length of the game and go when it does.
  List<DeckItem> toItems(String gameId) => [
    for (final (index, item) in items.indexed)
      DeckItem(
        DeckEntry(
          cardId: 'wire:$index',
          zoneId: item.zoneId,
          quantity: item.quantity,
        ),
        CardDefinition(
          id: 'wire:$index',
          gameId: gameId,
          name: item.name,
          attributes: item.attributes,
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
      ),
  ];

  int get cardCount => items.fold(0, (sum, item) => sum + item.quantity);

  Map<String, Object?> toJson() => {
    'name': name,
    'items': [for (final item in items) item.toJson()],
  };

  static WireDeck fromJson(Map<String, Object?> json) => WireDeck(
    name: json['name'] as String? ?? 'Their deck',
    items: [
      for (final entry in (json['items'] as List? ?? const []))
        WireDeckItem.fromJson((entry as Map).cast<String, Object?>()),
    ],
  );
}

/// One line of a deck: a card, how many, and which zone it lives in.
class WireDeckItem {
  const WireDeckItem({
    required this.zoneId,
    required this.quantity,
    required this.name,
    required this.attributes,
  });

  final String zoneId;
  final int quantity;
  final String name;
  final Map<String, String> attributes;

  Map<String, Object?> toJson() => {
    'zone': zoneId,
    'quantity': quantity,
    'name': name,
    'attributes': attributes,
  };

  static WireDeckItem fromJson(Map<String, Object?> json) => WireDeckItem(
    zoneId: json['zone'] as String? ?? 'main',
    // A quantity from the far end is not to be trusted with the deal: a
    // thousand copies of one card would be a game nobody could play.
    quantity: ((json['quantity'] as int?) ?? 1).clamp(0, 50),
    name: json['name'] as String? ?? 'Unknown card',
    attributes: {
      for (final entry in (json['attributes'] as Map? ?? const {}).entries)
        '${entry.key}': '${entry.value}',
    },
  );
}
