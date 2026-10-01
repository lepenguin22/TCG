/// Decks built around a single ability, for the tests that read them.
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tcg_decks/games/vanguard/vanguard_data.dart';
import 'package:tcg_decks/models/deck.dart';
import 'package:tcg_decks/playtest/playtest_engine.dart';
import 'package:tcg_decks/store/deck_store.dart';

/// A deck built out of one ability, so what the board did with it is not a
/// guess: nothing else on the field could have caused it.
Future<(DeckStore, Deck)> deckWith({
  required String boosterEffect,
  String beaterEffect = '',
  String vanguardEffect = '',
}) async {
  SharedPreferences.setMockInitialValues({});
  final store = DeckStore();
  await store.load();
  final deck = store.createDeck(name: 'Ability deck', formatId: formatStandard);

  void add(String name, String zone, int quantity, Map<String, String> attrs) {
    final card = store.saveCard(
      gameId: 'vanguard',
      name: name,
      attributes: attrs,
    );
    store.addToDeck(deck.id, card.id, zone, quantity: quantity);
  }

  for (var grade = 0; grade <= 3; grade += 1) {
    add('Ride $grade', zoneRide, 1, {
      'grade': '$grade',
      'cardType': 'normal',
      'power': '${9000 + grade * 2000}',
      'shield': grade == 0 ? '10000' : '0',
      'effect': vanguardEffect,
    });
  }
  add('Critical Trigger', zoneMain, 16, {
    'grade': '0',
    'cardType': 'trigger',
    'trigger': 'critical',
    'power': '5000',
    'shield': '15000',
  });
  add('Beater', zoneMain, 20, {
    'grade': '2',
    'cardType': 'normal',
    'power': '13000',
    'shield': '5000',
    'effect': beaterEffect,
  });
  add('Booster', zoneMain, 14, {
    'grade': '1',
    'cardType': 'normal',
    'power': '8000',
    'shield': '10000',
    'effect': boosterEffect,
  });
  return (store, store.decks.firstWhere((d) => d.id == deck.id));
}

PlaytestEngine engineFor(DeckStore store, Deck deck, {int seed = 7}) =>
    PlaytestEngine.start(
      store: store,
      yourDeck: deck,
      opponentDeck: deck,
      random: Random(seed),
    );

bool logHas(PlaytestEngine engine, String fragment) =>
    engine.state.log.any((entry) => entry.text.contains(fragment));
