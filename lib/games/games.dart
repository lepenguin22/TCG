import 'game_definition.dart';
import 'vanguard/vanguard_game.dart';

/// Every game the app knows about.
///
/// The screens are driven entirely by this list, so adding another TCG means
/// writing a [GameDefinition] and adding it here.
const games = <GameDefinition>[VanguardGame()];

const defaultGameId = 'vanguard';

GameDefinition gameById(String gameId) {
  for (final game in games) {
    if (game.id == gameId) return game;
  }
  return games.first;
}
