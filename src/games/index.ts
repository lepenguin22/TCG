import type { GameDefinition } from './types';
import { vanguard } from './vanguard';

/**
 * Every game the app knows about. Adding another TCG means adding a
 * `GameDefinition` here — the screens are driven entirely by this data.
 */
export const GAMES: GameDefinition[] = [vanguard];

export const DEFAULT_GAME_ID = vanguard.id;

export function getGame(gameId: string): GameDefinition {
  return GAMES.find((g) => g.id === gameId) ?? vanguard;
}

export * from './types';
