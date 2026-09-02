export const colors = {
  bg: '#0E1116',
  surface: '#161B22',
  surfaceAlt: '#1C232C',
  border: '#252D38',
  text: '#E9EEF5',
  textMuted: '#9AA5B1',
  textFaint: '#6B7683',
  danger: '#F26D6D',
  warning: '#F5C453',
  success: '#5BD6A8',
  accent: '#E4573D',
};

export interface Accent {
  key: string;
  label: string;
  color: string;
}

export const ACCENTS: Accent[] = [
  { key: 'ember', label: 'Ember', color: '#E4573D' },
  { key: 'violet', label: 'Violet', color: '#8C6BD1' },
  { key: 'azure', label: 'Azure', color: '#4FB3E8' },
  { key: 'gold', label: 'Gold', color: '#F0C24B' },
  { key: 'jade', label: 'Jade', color: '#4FC08D' },
  { key: 'rose', label: 'Rose', color: '#EE85B5' },
];

export function accentColor(key: string): string {
  return ACCENTS.find((a) => a.key === key)?.color ?? ACCENTS[0].color;
}

export const spacing = {
  xs: 4,
  sm: 8,
  md: 12,
  lg: 16,
  xl: 24,
  xxl: 32,
};

export const radius = {
  sm: 8,
  md: 12,
  lg: 16,
  pill: 999,
};
