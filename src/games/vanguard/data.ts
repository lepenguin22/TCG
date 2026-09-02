import type { CardField, FieldOption, FormatDefinition, ZoneDefinition } from '@/games/types';

export const ZONE_RIDE = 'ride';
export const ZONE_MAIN = 'main';
export const ZONE_G = 'gzone';

export const VANGUARD_ZONES: ZoneDefinition[] = [
  {
    id: ZONE_RIDE,
    name: 'Ride Deck',
    shortName: 'Ride',
    description: 'Exactly four cards: one each of grade 0, 1, 2 and 3. No trigger units.',
  },
  {
    id: ZONE_MAIN,
    name: 'Main Deck',
    shortName: 'Main',
    description: 'Exactly fifty cards, at most four copies of any one card name.',
  },
  {
    id: ZONE_G,
    name: 'G Zone',
    shortName: 'G',
    description: 'Up to sixteen G units, at most four copies of any one card name. Premium only.',
  },
];

export const GRADE_OPTIONS: FieldOption[] = [
  { value: '0', label: 'Grade 0', color: '#6EA8FE' },
  { value: '1', label: 'Grade 1', color: '#5BD6A8' },
  { value: '2', label: 'Grade 2', color: '#F5C453' },
  { value: '3', label: 'Grade 3', color: '#F58B54' },
  { value: '4', label: 'Grade 4 (G unit)', color: '#C08BF5' },
];

export const CARD_TYPE_OPTIONS: FieldOption[] = [
  { value: 'normal', label: 'Normal Unit' },
  { value: 'trigger', label: 'Trigger Unit' },
  { value: 'sentinel', label: 'Sentinel (Normal Unit)' },
  { value: 'order', label: 'Order' },
  { value: 'order-blitz', label: 'Blitz Order' },
  { value: 'order-set', label: 'Set Order' },
  { value: 'g-unit', label: 'G Unit' },
  { value: 'token', label: 'Token' },
];

export const TRIGGER_OPTIONS: FieldOption[] = [
  { value: 'critical', label: 'Critical', color: '#F26D6D' },
  { value: 'draw', label: 'Draw', color: '#6EA8FE' },
  { value: 'front', label: 'Front', color: '#F5A25B' },
  { value: 'heal', label: 'Heal', color: '#5BD6A8' },
  { value: 'stand', label: 'Stand', color: '#F5DC5B' },
  { value: 'over', label: 'Over', color: '#C08BF5' },
];

export const NATION_OPTIONS: FieldOption[] = [
  { value: 'dragon-empire', label: 'Dragon Empire', color: '#E4573D' },
  { value: 'dark-states', label: 'Dark States', color: '#8C6BD1' },
  { value: 'brandt-gate', label: 'Brandt Gate', color: '#4FB3E8' },
  { value: 'keter-sanctuary', label: 'Keter Sanctuary', color: '#F0C24B' },
  { value: 'stoicheia', label: 'Stoicheia', color: '#4FC08D' },
  { value: 'lyrical-monasterio', label: 'Lyrical Monasterio', color: '#EE85B5' },
  { value: 'united-sanctuary', label: 'United Sanctuary (legacy)', color: '#D8C48A' },
  { value: 'star-gate', label: 'Star Gate (legacy)', color: '#7FA8D8' },
  { value: 'magallanica', label: 'Magallanica (legacy)', color: '#6BC7D1' },
  { value: 'zoo', label: 'Zoo (legacy)', color: '#9BC26B' },
  { value: 'dark-zone', label: 'Dark Zone (legacy)', color: '#A0729B' },
  { value: 'cray-elemental', label: 'Cray Elemental', color: '#9AA5B1' },
  { value: 'none', label: 'No nation', color: '#7A8794' },
];

/** Card types that never take part in the trigger count. */
export const NON_TRIGGER_TYPES = new Set(['normal', 'sentinel', 'order', 'order-blitz', 'order-set', 'g-unit', 'token']);

export const VANGUARD_FIELDS: CardField[] = [
  {
    key: 'grade',
    label: 'Grade',
    type: 'select',
    options: GRADE_OPTIONS,
    required: true,
  },
  {
    key: 'cardType',
    label: 'Card type',
    type: 'select',
    options: CARD_TYPE_OPTIONS,
    required: true,
  },
  {
    key: 'trigger',
    label: 'Trigger',
    type: 'select',
    options: TRIGGER_OPTIONS,
    visibleWhen: { key: 'cardType', values: ['trigger'] },
    helper: 'Heal is capped at four copies and Over at one per deck.',
  },
  {
    key: 'nation',
    label: 'Nation',
    type: 'select',
    options: NATION_OPTIONS,
  },
  {
    key: 'clan',
    label: 'Clan / sub-clan',
    type: 'text',
    placeholder: 'Kagero, Royal Paladin, Nova Grappler…',
    helper: 'Optional. Handy for Premium decks built around a clan.',
  },
  { key: 'power', label: 'Power', type: 'number', placeholder: '13000' },
  { key: 'shield', label: 'Shield', type: 'number', placeholder: '10000' },
  { key: 'critical', label: 'Critical', type: 'number', placeholder: '1' },
  { key: 'cardNo', label: 'Card number', type: 'text', placeholder: 'D-BT01/001EN' },
  { key: 'imageUrl', label: 'Image URL', type: 'text', placeholder: 'https://…' },
  { key: 'notes', label: 'Notes', type: 'multiline', placeholder: 'Skill reminder, combo notes…' },
];

export const FORMAT_STANDARD = 'standard';
export const FORMAT_PREMIUM = 'premium';
export const FORMAT_CASUAL = 'casual';

export const VANGUARD_FORMATS: FormatDefinition[] = [
  {
    id: FORMAT_STANDARD,
    name: 'Standard',
    description: '50 card main deck plus a 4 card ride deck. D-series and V-series cards.',
    zoneIds: [ZONE_RIDE, ZONE_MAIN],
    targets: { [ZONE_RIDE]: { exact: 4 }, [ZONE_MAIN]: { exact: 50 } },
  },
  {
    id: FORMAT_PREMIUM,
    name: 'Premium',
    description: '50 card main deck plus a G zone of up to 16 G units. Every era is legal.',
    zoneIds: [ZONE_MAIN, ZONE_G],
    targets: { [ZONE_MAIN]: { exact: 50 }, [ZONE_G]: { max: 16 } },
  },
  {
    id: FORMAT_CASUAL,
    name: 'Casual / brew',
    description: 'No size limits enforced. Use this while a list is still taking shape.',
    zoneIds: [ZONE_RIDE, ZONE_MAIN, ZONE_G],
    targets: {},
  },
];

export function optionLabel(options: FieldOption[], value: string | undefined): string {
  if (!value) return '';
  return options.find((o) => o.value === value)?.label ?? value;
}

export function optionColor(options: FieldOption[], value: string | undefined): string | undefined {
  if (!value) return undefined;
  return options.find((o) => o.value === value)?.color;
}
