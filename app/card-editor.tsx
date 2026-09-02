import { Stack, useLocalSearchParams, useRouter } from 'expo-router';
import React, { useMemo, useState } from 'react';
import { Alert, ScrollView, StyleSheet, Text, View } from 'react-native';
import { OptionPicker } from '@/components/OptionPicker';
import { Button, Field, Input } from '@/components/ui';
import { DEFAULT_GAME_ID, getGame } from '@/games';
import type { CardField } from '@/games/types';
import { useStore } from '@/store/DeckStore';
import { colors, spacing } from '@/theme';

function isVisible(field: CardField, attributes: Record<string, string>): boolean {
  if (!field.visibleWhen) return true;
  return field.visibleWhen.values.includes(attributes[field.visibleWhen.key] ?? '');
}

export default function CardEditorScreen() {
  const params = useLocalSearchParams<{
    cardId?: string;
    gameId?: string;
    deckId?: string;
    zone?: string;
  }>();
  const router = useRouter();
  const { getCard, saveCard, deleteCard, addToDeck } = useStore();

  const existing = params.cardId ? getCard(params.cardId) : undefined;
  const gameId = existing?.gameId ?? params.gameId ?? DEFAULT_GAME_ID;
  const game = getGame(gameId);

  const [name, setName] = useState(existing?.name ?? '');
  const [attributes, setAttributes] = useState<Record<string, string>>(() => {
    if (existing) return { ...existing.attributes };
    const defaults: Record<string, string> = {};
    for (const field of game.cardFields) {
      if (field.required && field.options?.length) defaults[field.key] = field.options[0].value;
    }
    return defaults;
  });

  const missing = useMemo(
    () =>
      game.cardFields.filter(
        (field) => field.required && isVisible(field, attributes) && !attributes[field.key],
      ),
    [attributes, game.cardFields],
  );

  const canSave = name.trim().length > 0 && missing.length === 0;

  function setValue(key: string, value: string) {
    setAttributes((prev) => ({ ...prev, [key]: value }));
  }

  function onSave() {
    const cleaned: Record<string, string> = {};
    for (const field of game.cardFields) {
      const value = attributes[field.key];
      if (isVisible(field, attributes) && value) cleaned[field.key] = value;
    }
    const card = saveCard({ id: existing?.id, gameId, name, attributes: cleaned });
    if (!existing && params.deckId && params.zone) {
      addToDeck(params.deckId, card.id, params.zone, 1);
    }
    router.back();
  }

  function onDelete() {
    if (!existing) return;
    Alert.alert(
      'Delete card?',
      `"${existing.name}" will be removed from your library and from every deck that uses it.`,
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete',
          style: 'destructive',
          onPress: () => {
            deleteCard(existing.id);
            router.back();
          },
        },
      ],
    );
  }

  return (
    <ScrollView
      style={styles.screen}
      contentContainerStyle={styles.content}
      keyboardShouldPersistTaps="handled"
    >
      <Stack.Screen options={{ title: existing ? 'Edit Card' : 'New Card' }} />

      <Field label="Card name">
        <Input
          placeholder="Dragontree Maiden, Sharlka"
          value={name}
          onChangeText={setName}
          autoFocus={!existing}
        />
      </Field>

      {game.cardFields.filter((field) => isVisible(field, attributes)).map((field) => (
        <Field key={field.key} label={field.label} helper={field.helper}>
          {field.type === 'select' ? (
            <OptionPicker
              options={field.options ?? []}
              value={attributes[field.key]}
              onChange={(value) => setValue(field.key, value)}
              allowClear={!field.required}
              compact
            />
          ) : (
            <Input
              placeholder={field.placeholder}
              value={attributes[field.key] ?? ''}
              onChangeText={(value) => setValue(field.key, value)}
              keyboardType={field.type === 'number' ? 'number-pad' : 'default'}
              multiline={field.type === 'multiline'}
            />
          )}
        </Field>
      ))}

      {params.deckId && !existing ? (
        <Text style={styles.hint}>Saving adds one copy to the deck you came from.</Text>
      ) : null}

      <Button label={existing ? 'Save changes' : 'Save card'} icon="checkmark" onPress={onSave} disabled={!canSave} />

      {existing ? (
        <Button
          label="Delete card"
          icon="trash-outline"
          variant="danger"
          onPress={onDelete}
          style={{ marginTop: spacing.md }}
        />
      ) : null}

      <View style={{ height: spacing.xxl }} />
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
    backgroundColor: colors.bg,
  },
  content: {
    padding: spacing.lg,
  },
  hint: {
    color: colors.textFaint,
    fontSize: 12,
    marginBottom: spacing.md,
  },
});
