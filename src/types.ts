/** Core data model shared by every trading card game supported by the app. */

/** A card the user has entered into their personal library. */
export interface CardDefinition {
  id: string;
  gameId: string;
  name: string;
  /**
   * Game specific values (grade, trigger, nation, ...). The shape is described
   * by `GameDefinition.cardFields`, which also drives the card editor form.
   */
  attributes: Record<string, string>;
  createdAt: number;
  updatedAt: number;
}

/** A card slotted into one of a deck's zones. */
export interface DeckEntry {
  cardId: string;
  zoneId: string;
  quantity: number;
}

export interface Deck {
  id: string;
  gameId: string;
  formatId: string;
  name: string;
  description: string;
  /** Key into `ACCENTS` in the theme, used to colour the deck in lists. */
  accent: string;
  favorite: boolean;
  entries: DeckEntry[];
  createdAt: number;
  updatedAt: number;
}

/** Shape of the JSON produced by "export" and accepted by "import". */
export interface BackupPayload {
  app: 'tcg-decks';
  version: 1;
  exportedAt: number;
  decks: Deck[];
  cards: CardDefinition[];
}
