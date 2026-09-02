import type { CardDefinition, Deck } from '@/types';

export type FieldType = 'text' | 'number' | 'select' | 'multiline';

export interface FieldOption {
  value: string;
  label: string;
  /** Optional colour used for chips and charts. */
  color?: string;
}

/** Describes one game specific card attribute and how to edit it. */
export interface CardField {
  key: string;
  label: string;
  type: FieldType;
  options?: FieldOption[];
  placeholder?: string;
  helper?: string;
  required?: boolean;
  /** Only show the field while another field holds one of these values. */
  visibleWhen?: { key: string; values: string[] };
}

export interface ZoneDefinition {
  id: string;
  name: string;
  shortName: string;
  description: string;
}

export interface ZoneTarget {
  /** The zone must hold exactly this many cards. */
  exact?: number;
  /** The zone may hold at most this many cards. */
  max?: number;
}

export interface FormatDefinition {
  id: string;
  name: string;
  description: string;
  /** Zone ids in display order. */
  zoneIds: string[];
  targets: Record<string, ZoneTarget>;
}

export interface ValidationIssue {
  level: 'error' | 'warning';
  message: string;
}

export interface StatBar {
  label: string;
  value: number;
  color?: string;
}

export interface StatGroup {
  title: string;
  caption?: string;
  bars: StatBar[];
}

/** A deck plus its resolved cards — the input to rules, stats and grouping. */
export interface DeckView {
  deck: Deck;
  format: FormatDefinition;
  /** Every entry paired with its card, in the order the deck stores them. */
  items: { entry: { cardId: string; zoneId: string; quantity: number }; card: CardDefinition }[];
}

export interface CardBadge {
  text: string;
  color: string;
}

export interface GameDefinition {
  id: string;
  name: string;
  shortName: string;
  tagline: string;
  accent: string;
  zones: ZoneDefinition[];
  formats: FormatDefinition[];
  defaultFormatId: string;
  cardFields: CardField[];
  /** Heading a card is listed under inside a zone (e.g. "Grade 2"). */
  groupOf(card: CardDefinition, zoneId: string): string;
  /** Sort order for group headings. */
  compareGroups(a: string, b: string): number;
  /** Sort order for cards inside a group. */
  compareCards(a: CardDefinition, b: CardDefinition): number;
  /** One line summary shown under a card's name. */
  describeCard(card: CardDefinition): string;
  /** Small coloured badge shown next to a card's name. */
  badgeOf(card: CardDefinition): CardBadge | null;
  /** Deck construction rules for the deck's format. */
  validate(view: DeckView): ValidationIssue[];
  /** Charts for the deck breakdown screen. */
  stats(view: DeckView): StatGroup[];
}

export function getZone(game: GameDefinition, zoneId: string): ZoneDefinition | undefined {
  return game.zones.find((z) => z.id === zoneId);
}

export function getFormat(game: GameDefinition, formatId: string): FormatDefinition {
  return game.formats.find((f) => f.id === formatId) ?? game.formats[0];
}
