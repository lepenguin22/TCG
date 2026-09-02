import { Ionicons } from '@expo/vector-icons';
import React from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import type { GameDefinition } from '@/games/types';
import { colors, radius, spacing } from '@/theme';
import type { CardDefinition } from '@/types';
import { Badge } from './ui';

export function CardRow({
  game,
  card,
  quantity,
  onPress,
  onIncrement,
  onDecrement,
  trailing,
}: {
  game: GameDefinition;
  card: CardDefinition;
  quantity?: number;
  onPress?: () => void;
  onIncrement?: () => void;
  onDecrement?: () => void;
  trailing?: React.ReactNode;
}) {
  const badge = game.badgeOf(card);
  const subtitle = game.describeCard(card);

  return (
    <Pressable
      onPress={onPress}
      style={({ pressed }) => [styles.row, pressed && onPress ? { backgroundColor: colors.surfaceAlt } : null]}
    >
      {badge ? <Badge text={badge.text} color={badge.color} /> : null}
      <View style={styles.body}>
        <Text style={styles.name} numberOfLines={1}>
          {card.name}
        </Text>
        {subtitle ? (
          <Text style={styles.subtitle} numberOfLines={1}>
            {subtitle}
          </Text>
        ) : null}
      </View>
      {onDecrement && onIncrement && quantity !== undefined ? (
        <View style={styles.stepper}>
          <Pressable
            accessibilityRole="button"
            accessibilityLabel={`Remove one ${card.name}`}
            hitSlop={8}
            onPress={onDecrement}
            style={({ pressed }) => [styles.stepButton, pressed && { opacity: 0.6 }]}
          >
            <Ionicons name="remove" size={16} color={colors.textMuted} />
          </Pressable>
          <Text style={styles.quantity}>{quantity}</Text>
          <Pressable
            accessibilityRole="button"
            accessibilityLabel={`Add one ${card.name}`}
            hitSlop={8}
            onPress={onIncrement}
            style={({ pressed }) => [styles.stepButton, pressed && { opacity: 0.6 }]}
          >
            <Ionicons name="add" size={16} color={colors.textMuted} />
          </Pressable>
        </View>
      ) : null}
      {trailing}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    paddingVertical: 10,
    paddingHorizontal: spacing.md,
    borderRadius: radius.md,
  },
  body: {
    flex: 1,
  },
  name: {
    color: colors.text,
    fontSize: 15,
    fontWeight: '600',
  },
  subtitle: {
    color: colors.textFaint,
    fontSize: 12,
    marginTop: 2,
  },
  stepper: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.surfaceAlt,
    borderRadius: radius.pill,
    borderWidth: 1,
    borderColor: colors.border,
    paddingHorizontal: 4,
  },
  stepButton: {
    padding: 6,
  },
  quantity: {
    color: colors.text,
    fontSize: 14,
    fontWeight: '700',
    minWidth: 22,
    textAlign: 'center',
  },
});
