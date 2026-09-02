/// A card the user has entered into their personal library.
///
/// Game specific values (grade, trigger, nation, ...) live in [attributes].
/// Their shape is described by the game's `cardFields`, which also drives the
/// card editor form, so the app can support another TCG without changing this
/// model.
class CardDefinition {
  const CardDefinition({
    required this.id,
    required this.gameId,
    required this.name,
    required this.attributes,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String gameId;
  final String name;
  final Map<String, String> attributes;
  final DateTime createdAt;
  final DateTime updatedAt;

  String? attribute(String key) {
    final value = attributes[key];
    return (value == null || value.isEmpty) ? null : value;
  }

  CardDefinition copyWith({
    String? name,
    Map<String, String>? attributes,
    DateTime? updatedAt,
  }) {
    return CardDefinition(
      id: id,
      gameId: gameId,
      name: name ?? this.name,
      attributes: attributes ?? this.attributes,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'gameId': gameId,
    'name': name,
    'attributes': attributes,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };

  static CardDefinition fromJson(Map<String, dynamic> json) {
    final rawAttributes = json['attributes'];
    return CardDefinition(
      id: json['id'] as String,
      gameId: json['gameId'] as String? ?? 'vanguard',
      name: json['name'] as String? ?? '',
      attributes: rawAttributes is Map
          ? rawAttributes.map((key, value) => MapEntry('$key', '$value'))
          : <String, String>{},
      createdAt: _date(json['createdAt']),
      updatedAt: _date(json['updatedAt']),
    );
  }
}

DateTime _date(Object? value) {
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return DateTime.fromMillisecondsSinceEpoch(0);
}
