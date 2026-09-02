import type { CardBadge, GameDefinition } from '@/games/types';
import type { CardDefinition } from '@/types';
import {
  CARD_TYPE_OPTIONS,
  FORMAT_STANDARD,
  GRADE_OPTIONS,
  NATION_OPTIONS,
  TRIGGER_OPTIONS,
  VANGUARD_FIELDS,
  VANGUARD_FORMATS,
  VANGUARD_ZONES,
  ZONE_G,
  optionColor,
  optionLabel,
} from './data';
import { validateVanguard, vanguardStats } from './rules';

function gradeOf(card: CardDefinition): string {
  return card.attributes.grade ?? '0';
}

export const vanguard: GameDefinition = {
  id: 'vanguard',
  name: 'Cardfight!! Vanguard',
  shortName: 'Vanguard',
  tagline: 'Stand up, my vanguard!',
  accent: '#E4573D',
  zones: VANGUARD_ZONES,
  formats: VANGUARD_FORMATS,
  defaultFormatId: FORMAT_STANDARD,
  cardFields: VANGUARD_FIELDS,

  groupOf(card, zoneId) {
    if (zoneId === ZONE_G) return 'G units';
    return `Grade ${gradeOf(card)}`;
  },

  compareGroups(a, b) {
    return a.localeCompare(b);
  },

  compareCards(a, b) {
    const gradeDelta = Number(gradeOf(a)) - Number(gradeOf(b));
    if (gradeDelta !== 0) return gradeDelta;
    const aTrigger = a.attributes.trigger ?? '';
    const bTrigger = b.attributes.trigger ?? '';
    if (aTrigger !== bTrigger) return aTrigger.localeCompare(bTrigger);
    return a.name.localeCompare(b.name);
  },

  describeCard(card) {
    const parts: string[] = [];
    const type = optionLabel(CARD_TYPE_OPTIONS, card.attributes.cardType);
    if (card.attributes.cardType === 'trigger' && card.attributes.trigger) {
      parts.push(`${optionLabel(TRIGGER_OPTIONS, card.attributes.trigger)} trigger`);
    } else if (type) {
      parts.push(type);
    }
    if (card.attributes.power) parts.push(`${card.attributes.power} power`);
    if (card.attributes.shield) parts.push(`${card.attributes.shield} shield`);
    const nation = optionLabel(NATION_OPTIONS, card.attributes.nation);
    if (nation && card.attributes.nation !== 'none') parts.push(nation);
    if (card.attributes.clan) parts.push(card.attributes.clan);
    return parts.join(' · ');
  },

  badgeOf(card): CardBadge | null {
    if (card.attributes.cardType === 'trigger' && card.attributes.trigger) {
      const trigger = card.attributes.trigger;
      const letter = trigger === 'over' ? 'OV' : trigger.charAt(0).toUpperCase();
      return { text: letter, color: optionColor(TRIGGER_OPTIONS, trigger) ?? '#7A8794' };
    }
    const grade = gradeOf(card);
    return { text: `G${grade}`, color: optionColor(GRADE_OPTIONS, grade) ?? '#7A8794' };
  },

  validate: validateVanguard,
  stats: vanguardStats,
};
