import React from 'react';
import { StyleSheet, Text, View } from 'react-native';
import type { StatGroup } from '@/games/types';
import { colors, radius, spacing } from '@/theme';

export function StatChart({ group }: { group: StatGroup }) {
  const max = Math.max(1, ...group.bars.map((b) => b.value));
  return (
    <View style={styles.wrapper}>
      <View style={styles.header}>
        <Text style={styles.title}>{group.title}</Text>
        {group.caption ? <Text style={styles.caption}>{group.caption}</Text> : null}
      </View>
      {group.bars.map((bar) => (
        <View key={bar.label} style={styles.barRow}>
          <Text style={styles.barLabel} numberOfLines={1}>
            {bar.label}
          </Text>
          <View style={styles.track}>
            <View
              style={[
                styles.fill,
                {
                  width: `${Math.round((bar.value / max) * 100)}%`,
                  backgroundColor: bar.color ?? colors.accent,
                },
              ]}
            />
          </View>
          <Text style={styles.barValue}>{bar.value}</Text>
        </View>
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  wrapper: {
    backgroundColor: colors.surface,
    borderRadius: radius.lg,
    borderWidth: 1,
    borderColor: colors.border,
    padding: spacing.lg,
    marginBottom: spacing.md,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'baseline',
    justifyContent: 'space-between',
    marginBottom: spacing.md,
  },
  title: {
    color: colors.text,
    fontSize: 15,
    fontWeight: '700',
  },
  caption: {
    color: colors.textMuted,
    fontSize: 12,
  },
  barRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    marginBottom: spacing.sm,
  },
  barLabel: {
    color: colors.textMuted,
    fontSize: 12,
    width: 96,
  },
  track: {
    flex: 1,
    height: 10,
    borderRadius: radius.pill,
    backgroundColor: colors.surfaceAlt,
    overflow: 'hidden',
  },
  fill: {
    height: '100%',
    borderRadius: radius.pill,
  },
  barValue: {
    color: colors.text,
    fontSize: 13,
    fontWeight: '700',
    width: 26,
    textAlign: 'right',
  },
});
