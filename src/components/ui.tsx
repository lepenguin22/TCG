import { Ionicons } from '@expo/vector-icons';
import React from 'react';
import {
  ActivityIndicator,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  type TextInputProps,
  View,
  type ViewStyle,
} from 'react-native';
import { colors, radius, spacing } from '@/theme';

export function Card({ children, style }: { children: React.ReactNode; style?: ViewStyle }) {
  return <View style={[styles.card, style]}>{children}</View>;
}

export function SectionHeader({
  title,
  caption,
  right,
}: {
  title: string;
  caption?: string;
  right?: React.ReactNode;
}) {
  return (
    <View style={styles.sectionHeader}>
      <View style={{ flex: 1 }}>
        <Text style={styles.sectionTitle}>{title}</Text>
        {caption ? <Text style={styles.sectionCaption}>{caption}</Text> : null}
      </View>
      {right}
    </View>
  );
}

export function Button({
  label,
  onPress,
  icon,
  variant = 'primary',
  tint,
  disabled,
  style,
}: {
  label: string;
  onPress: () => void;
  icon?: keyof typeof Ionicons.glyphMap;
  variant?: 'primary' | 'secondary' | 'ghost' | 'danger';
  tint?: string;
  disabled?: boolean;
  style?: ViewStyle;
}) {
  const background =
    variant === 'primary'
      ? tint ?? colors.accent
      : variant === 'danger'
        ? 'rgba(242,109,109,0.12)'
        : variant === 'secondary'
          ? colors.surfaceAlt
          : 'transparent';
  const foreground =
    variant === 'primary' ? '#0E1116' : variant === 'danger' ? colors.danger : colors.text;

  return (
    <Pressable
      accessibilityRole="button"
      disabled={disabled}
      onPress={onPress}
      style={({ pressed }) => [
        styles.button,
        { backgroundColor: background, opacity: disabled ? 0.4 : pressed ? 0.75 : 1 },
        variant === 'ghost' && styles.buttonGhost,
        style,
      ]}
    >
      {icon ? <Ionicons name={icon} size={16} color={foreground} /> : null}
      <Text style={[styles.buttonLabel, { color: foreground }]}>{label}</Text>
    </Pressable>
  );
}

export function Chip({
  label,
  selected,
  onPress,
  color,
  compact,
}: {
  label: string;
  selected?: boolean;
  onPress?: () => void;
  color?: string;
  compact?: boolean;
}) {
  const tint = color ?? colors.accent;
  return (
    <Pressable
      accessibilityRole={onPress ? 'button' : undefined}
      onPress={onPress}
      style={({ pressed }) => [
        styles.chip,
        compact && styles.chipCompact,
        selected && { backgroundColor: `${tint}22`, borderColor: tint },
        pressed && onPress ? { opacity: 0.7 } : null,
      ]}
    >
      <Text style={[styles.chipLabel, selected && { color: tint }]} numberOfLines={1}>
        {label}
      </Text>
    </Pressable>
  );
}

export function Field({
  label,
  helper,
  children,
}: {
  label: string;
  helper?: string;
  children: React.ReactNode;
}) {
  return (
    <View style={styles.field}>
      <Text style={styles.fieldLabel}>{label}</Text>
      {children}
      {helper ? <Text style={styles.fieldHelper}>{helper}</Text> : null}
    </View>
  );
}

export function Input(props: TextInputProps) {
  return (
    <TextInput
      placeholderTextColor={colors.textFaint}
      {...props}
      style={[styles.input, props.multiline && styles.inputMultiline, props.style]}
    />
  );
}

export function Badge({ text, color }: { text: string; color: string }) {
  return (
    <View style={[styles.badge, { backgroundColor: `${color}22`, borderColor: `${color}55` }]}>
      <Text style={[styles.badgeText, { color }]}>{text}</Text>
    </View>
  );
}

export function EmptyState({
  icon,
  title,
  message,
  action,
}: {
  icon: keyof typeof Ionicons.glyphMap;
  title: string;
  message: string;
  action?: React.ReactNode;
}) {
  return (
    <View style={styles.empty}>
      <Ionicons name={icon} size={40} color={colors.textFaint} />
      <Text style={styles.emptyTitle}>{title}</Text>
      <Text style={styles.emptyMessage}>{message}</Text>
      {action ? <View style={{ marginTop: spacing.lg }}>{action}</View> : null}
    </View>
  );
}

export function Loading() {
  return (
    <View style={styles.loading}>
      <ActivityIndicator color={colors.accent} />
    </View>
  );
}

export function IconButton({
  icon,
  onPress,
  color,
  size = 20,
  accessibilityLabel,
}: {
  icon: keyof typeof Ionicons.glyphMap;
  onPress: () => void;
  color?: string;
  size?: number;
  accessibilityLabel: string;
}) {
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel}
      hitSlop={10}
      onPress={onPress}
      style={({ pressed }) => [styles.iconButton, pressed && { opacity: 0.6 }]}
    >
      <Ionicons name={icon} size={size} color={color ?? colors.textMuted} />
    </Pressable>
  );
}

const styles = StyleSheet.create({
  card: {
    backgroundColor: colors.surface,
    borderRadius: radius.lg,
    borderWidth: 1,
    borderColor: colors.border,
    padding: spacing.lg,
  },
  sectionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    marginBottom: spacing.md,
  },
  sectionTitle: {
    color: colors.text,
    fontSize: 17,
    fontWeight: '700',
  },
  sectionCaption: {
    color: colors.textMuted,
    fontSize: 13,
    marginTop: 2,
  },
  button: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: spacing.sm,
    paddingVertical: 12,
    paddingHorizontal: spacing.lg,
    borderRadius: radius.md,
  },
  buttonGhost: {
    borderWidth: 1,
    borderColor: colors.border,
  },
  buttonLabel: {
    fontSize: 15,
    fontWeight: '600',
  },
  chip: {
    paddingVertical: 8,
    paddingHorizontal: spacing.md,
    borderRadius: radius.pill,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.surfaceAlt,
  },
  chipCompact: {
    paddingVertical: 5,
    paddingHorizontal: 10,
  },
  chipLabel: {
    color: colors.textMuted,
    fontSize: 13,
    fontWeight: '600',
  },
  field: {
    marginBottom: spacing.lg,
  },
  fieldLabel: {
    color: colors.textMuted,
    fontSize: 13,
    fontWeight: '600',
    marginBottom: spacing.sm,
    textTransform: 'uppercase',
    letterSpacing: 0.6,
  },
  fieldHelper: {
    color: colors.textFaint,
    fontSize: 12,
    marginTop: 6,
  },
  input: {
    backgroundColor: colors.surfaceAlt,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.border,
    color: colors.text,
    fontSize: 15,
    paddingHorizontal: spacing.md,
    paddingVertical: 12,
  },
  inputMultiline: {
    minHeight: 90,
    textAlignVertical: 'top',
  },
  badge: {
    minWidth: 30,
    paddingHorizontal: 6,
    paddingVertical: 3,
    borderRadius: radius.sm,
    borderWidth: 1,
    alignItems: 'center',
  },
  badgeText: {
    fontSize: 11,
    fontWeight: '800',
  },
  empty: {
    alignItems: 'center',
    paddingVertical: spacing.xxl,
    paddingHorizontal: spacing.xl,
  },
  emptyTitle: {
    color: colors.text,
    fontSize: 17,
    fontWeight: '700',
    marginTop: spacing.md,
  },
  emptyMessage: {
    color: colors.textMuted,
    fontSize: 14,
    textAlign: 'center',
    marginTop: spacing.sm,
    lineHeight: 20,
  },
  loading: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  iconButton: {
    padding: 6,
  },
});
