import { Ionicons } from '@expo/vector-icons';
import React from 'react';
import { StyleSheet, Text, View } from 'react-native';
import type { ValidationIssue } from '@/games/types';
import { colors, radius, spacing } from '@/theme';

export function IssueList({ issues }: { issues: ValidationIssue[] }) {
  if (issues.length === 0) {
    return (
      <View style={[styles.wrapper, { borderColor: `${colors.success}55`, backgroundColor: `${colors.success}12` }]}>
        <Ionicons name="checkmark-circle" size={18} color={colors.success} />
        <Text style={[styles.text, { color: colors.success }]}>
          Deck is legal for this format.
        </Text>
      </View>
    );
  }

  const errors = issues.filter((i) => i.level === 'error');
  const warnings = issues.filter((i) => i.level === 'warning');
  const tint = errors.length > 0 ? colors.danger : colors.warning;

  return (
    <View style={[styles.wrapper, styles.column, { borderColor: `${tint}55`, backgroundColor: `${tint}12` }]}>
      {[...errors, ...warnings].map((issue, index) => (
        <View key={`${issue.level}-${index}`} style={styles.issue}>
          <Ionicons
            name={issue.level === 'error' ? 'alert-circle' : 'warning'}
            size={16}
            color={issue.level === 'error' ? colors.danger : colors.warning}
            style={{ marginTop: 1 }}
          />
          <Text style={styles.text}>{issue.message}</Text>
        </View>
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  wrapper: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    borderWidth: 1,
    borderRadius: radius.md,
    padding: spacing.md,
  },
  column: {
    flexDirection: 'column',
    alignItems: 'stretch',
  },
  issue: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: spacing.sm,
    paddingVertical: 3,
  },
  text: {
    color: colors.text,
    fontSize: 13,
    flex: 1,
    lineHeight: 18,
  },
});
