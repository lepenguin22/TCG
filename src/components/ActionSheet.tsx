import { Ionicons } from '@expo/vector-icons';
import React from 'react';
import { Modal, Pressable, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { colors, radius, spacing } from '@/theme';

export interface SheetAction {
  label: string;
  icon?: keyof typeof Ionicons.glyphMap;
  destructive?: boolean;
  onPress: () => void;
}

/**
 * A bottom sheet of actions. Used instead of `Alert.alert` with many buttons,
 * which Android caps at three.
 */
export function ActionSheet({
  visible,
  title,
  actions,
  onClose,
}: {
  visible: boolean;
  title?: string;
  actions: SheetAction[];
  onClose: () => void;
}) {
  const insets = useSafeAreaInsets();

  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={onClose}>
      <Pressable style={styles.backdrop} onPress={onClose} accessibilityLabel="Close menu">
        <Pressable
          style={[styles.sheet, { paddingBottom: insets.bottom + spacing.md }]}
          onPress={(event) => event.stopPropagation()}
        >
          {title ? (
            <Text style={styles.title} numberOfLines={1}>
              {title}
            </Text>
          ) : null}
          {actions.map((action) => (
            <Pressable
              key={action.label}
              accessibilityRole="button"
              onPress={() => {
                onClose();
                action.onPress();
              }}
              style={({ pressed }) => [styles.action, pressed && { backgroundColor: colors.surfaceAlt }]}
            >
              {action.icon ? (
                <Ionicons
                  name={action.icon}
                  size={18}
                  color={action.destructive ? colors.danger : colors.textMuted}
                />
              ) : null}
              <Text style={[styles.actionLabel, action.destructive && { color: colors.danger }]}>
                {action.label}
              </Text>
            </Pressable>
          ))}
          <Pressable
            accessibilityRole="button"
            onPress={onClose}
            style={({ pressed }) => [styles.cancel, pressed && { opacity: 0.7 }]}
          >
            <Text style={styles.cancelLabel}>Cancel</Text>
          </Pressable>
        </Pressable>
      </Pressable>
    </Modal>
  );
}

const styles = StyleSheet.create({
  backdrop: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.55)',
    justifyContent: 'flex-end',
  },
  sheet: {
    backgroundColor: colors.surface,
    borderTopLeftRadius: radius.lg,
    borderTopRightRadius: radius.lg,
    borderTopWidth: 1,
    borderColor: colors.border,
    paddingTop: spacing.md,
    paddingHorizontal: spacing.md,
  },
  title: {
    color: colors.textMuted,
    fontSize: 13,
    fontWeight: '700',
    paddingHorizontal: spacing.md,
    paddingBottom: spacing.sm,
  },
  action: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    paddingVertical: 14,
    paddingHorizontal: spacing.md,
    borderRadius: radius.md,
  },
  actionLabel: {
    color: colors.text,
    fontSize: 15,
    fontWeight: '600',
  },
  cancel: {
    alignItems: 'center',
    paddingVertical: 14,
    marginTop: spacing.xs,
  },
  cancelLabel: {
    color: colors.textMuted,
    fontSize: 15,
    fontWeight: '600',
  },
});
