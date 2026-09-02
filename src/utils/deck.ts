import { getGame } from '@/games';
import { getFormat, type DeckView, type GameDefinition, type ValidationIssue } from '@/games/types';
import type { CardDefinition, Deck } from '@/types';

export function buildDeckView(deck: Deck, cards: CardDefinition[]): DeckView {
  const game = getGame(deck.gameId);
  const byId = new Map(cards.map((c) => [c.id, c]));
  const items = deck.entries
    .map((entry) => {
      const card = byId.get(entry.cardId);
      return card ? { entry, card } : null;
    })
    .filter((x): x is { entry: Deck['entries'][number]; card: CardDefinition } => x !== null);
  return { deck, format: getFormat(game, deck.formatId), items };
}

export function zoneCount(view: DeckView, zoneId: string): number {
  return view.items
    .filter((i) => i.entry.zoneId === zoneId)
    .reduce((sum, i) => sum + i.entry.quantity, 0);
}

export function totalCount(view: DeckView): number {
  return view.items.reduce((sum, i) => sum + i.entry.quantity, 0);
}

export interface DeckHealth {
  errors: number;
  warnings: number;
  issues: ValidationIssue[];
}

export function deckHealth(game: GameDefinition, view: DeckView): DeckHealth {
  const issues = game.validate(view);
  return {
    issues,
    errors: issues.filter((i) => i.level === 'error').length,
    warnings: issues.filter((i) => i.level === 'warning').length,
  };
}

/** Cards grouped for display inside one zone, sorted by the game's rules. */
export function groupZone(
  game: GameDefinition,
  view: DeckView,
  zoneId: string,
): { title: string; count: number; rows: { card: CardDefinition; quantity: number }[] }[] {
  const rows = view.items
    .filter((i) => i.entry.zoneId === zoneId)
    .map((i) => ({ card: i.card, quantity: i.entry.quantity }));

  const groups = new Map<string, { card: CardDefinition; quantity: number }[]>();
  for (const row of rows) {
    const title = game.groupOf(row.card, zoneId);
    const list = groups.get(title);
    if (list) list.push(row);
    else groups.set(title, [row]);
  }

  return [...groups.entries()]
    .sort((a, b) => game.compareGroups(a[0], b[0]))
    .map(([title, list]) => ({
      title,
      count: list.reduce((sum, r) => sum + r.quantity, 0),
      rows: list.sort((a, b) => game.compareCards(a.card, b.card)),
    }));
}

/** A plain text list, the format people paste into chats and forums. */
export function deckToText(game: GameDefinition, view: DeckView): string {
  const lines: string[] = [`${view.deck.name} — ${game.name} (${view.format.name})`];
  for (const zoneId of view.format.zoneIds) {
    const zone = game.zones.find((z) => z.id === zoneId);
    const groups = groupZone(game, view, zoneId);
    const count = zoneCount(view, zoneId);
    if (count === 0) continue;
    lines.push('', `${zone?.name ?? zoneId} (${count})`);
    for (const group of groups) {
      for (const row of group.rows) {
        lines.push(`${row.quantity}x ${row.card.name}`);
      }
    }
  }
  return lines.join('\n');
}
