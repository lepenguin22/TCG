/// A card slotted into one of a deck's zones.
class DeckEntry {
  const DeckEntry({
    required this.cardId,
    required this.zoneId,
    required this.quantity,
  });

  final String cardId;
  final String zoneId;
  final int quantity;

  DeckEntry copyWith({String? zoneId, int? quantity}) => DeckEntry(
    cardId: cardId,
    zoneId: zoneId ?? this.zoneId,
    quantity: quantity ?? this.quantity,
  );

  Map<String, dynamic> toJson() => {
    'cardId': cardId,
    'zoneId': zoneId,
    'quantity': quantity,
  };

  static DeckEntry fromJson(Map<String, dynamic> json) => DeckEntry(
    cardId: json['cardId'] as String,
    zoneId: json['zoneId'] as String,
    quantity: (json['quantity'] as num?)?.toInt() ?? 1,
  );
}

class Deck {
  const Deck({
    required this.id,
    required this.gameId,
    required this.formatId,
    required this.name,
    required this.description,
    required this.accent,
    required this.favorite,
    required this.entries,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String gameId;
  final String formatId;
  final String name;
  final String description;

  /// Key into `accents` in the theme, used to colour the deck in lists.
  final String accent;
  final bool favorite;
  final List<DeckEntry> entries;
  final DateTime createdAt;
  final DateTime updatedAt;

  Deck copyWith({
    String? formatId,
    String? name,
    String? description,
    String? accent,
    bool? favorite,
    List<DeckEntry>? entries,
    DateTime? updatedAt,
  }) {
    return Deck(
      id: id,
      gameId: gameId,
      formatId: formatId ?? this.formatId,
      name: name ?? this.name,
      description: description ?? this.description,
      accent: accent ?? this.accent,
      favorite: favorite ?? this.favorite,
      entries: entries ?? this.entries,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'gameId': gameId,
    'formatId': formatId,
    'name': name,
    'description': description,
    'accent': accent,
    'favorite': favorite,
    'entries': entries.map((e) => e.toJson()).toList(),
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };

  static Deck fromJson(Map<String, dynamic> json) {
    final rawEntries = json['entries'];
    return Deck(
      id: json['id'] as String,
      gameId: json['gameId'] as String? ?? 'vanguard',
      formatId: json['formatId'] as String? ?? 'standard',
      name: json['name'] as String? ?? 'Untitled deck',
      description: json['description'] as String? ?? '',
      accent: json['accent'] as String? ?? 'ember',
      favorite: json['favorite'] as bool? ?? false,
      entries: rawEntries is List
          ? rawEntries
                .whereType<Map<String, dynamic>>()
                .map(DeckEntry.fromJson)
                .toList()
          : <DeckEntry>[],
      createdAt: _date(json['createdAt']),
      updatedAt: _date(json['updatedAt']),
    );
  }
}

DateTime _date(Object? value) {
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return DateTime.fromMillisecondsSinceEpoch(0);
}
