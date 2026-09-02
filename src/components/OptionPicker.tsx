import React from 'react';
import { StyleSheet, View } from 'react-native';
import type { FieldOption } from '@/games/types';
import { spacing } from '@/theme';
import { Chip } from './ui';

export function OptionPicker({
  options,
  value,
  onChange,
  allowClear,
  compact,
}: {
  options: FieldOption[];
  value?: string;
  onChange: (value: string) => void;
  allowClear?: boolean;
  compact?: boolean;
}) {
  return (
    <View style={styles.wrapper}>
      {options.map((option) => (
        <Chip
          key={option.value}
          label={option.label}
          color={option.color}
          compact={compact}
          selected={value === option.value}
          onPress={() => onChange(allowClear && value === option.value ? '' : option.value)}
        />
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  wrapper: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.sm,
  },
});
