import { useLocalSearchParams, useRouter } from 'expo-router';
import React, { useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { OptionPicker } from '@/components/OptionPicker';
import { Button, EmptyState, Field, Input } from '@/components/ui';
import { getGame } from '@/games';
import { useStore } from '@/store/DeckStore';
import { ACCENTS, colors, spacing } from '@/theme';

export default function DeckSettingsScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const { getDeck, updateDeck, deleteDeck } = useStore();
  const deck = getDeck(id);
  const game = deck ? getGame(deck.gameId) : null;

  const [name, setName] = useState(deck?.name ?? '');
  const [description, setDescription] = useState(deck?.description ?? '');
  const [formatId, setFormatId] = useState(deck?.formatId ?? '');
  const [accent, setAccent] = useState(deck?.accent ?? ACCENTS[0].key);

  if (!deck || !game) {
    return (
      <EmptyState
        icon="help-circle-outline"
        title="Deck not found"
        message="It may have been deleted."
        action={<Button label="Back to decks" onPress={() => router.replace('/')} />}
      />
    );
  }

  const format = game.formats.find((f) => f.id === formatId) ?? game.formats[0];

  function onSave() {
    updateDeck(deck!.id, { name: name.trim() || deck!.name, description, formatId, accent });
    router.back();
  }

  function onDelete() {
    Alert.alert('Delete deck?', `"${deck!.name}" will be removed. This cannot be undone.`, [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Delete',
        style: 'destructive',
        onPress: () => {
          deleteDeck(deck!.id);
          router.replace('/');
        },
      },
    ]);
  }

  return (
    <ScrollView style={styles.screen} contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
      <Field label="Deck name">
        <Input value={name} onChangeText={setName} />
      </Field>

      <Field label="Format" helper={format.description}>
        <OptionPicker
          options={game.formats.map((f) => ({ value: f.id, label: f.name }))}
          value={formatId}
          onChange={setFormatId}
        />
      </Field>

      {formatId !== deck.formatId ? (
        <Text style={styles.warning}>
          Changing format keeps every card. Cards in a zone the new format does not use stay saved but
          stop counting.
        </Text>
      ) : null}

      <Field label="Colour">
        <View style={styles.swatches}>
          {ACCENTS.map((option) => (
            <Pressable
              key={option.key}
              accessibilityRole="button"
              accessibilityLabel={option.label}
              onPress={() => setAccent(option.key)}
              style={[
                styles.swatch,
                { backgroundColor: option.color },
                accent === option.key && styles.swatchSelected,
              ]}
            />
          ))}
        </View>
      </Field>

      <Field label="Notes">
        <Input value={description} onChangeText={setDescription} multiline />
      </Field>

      <Button label="Save" icon="checkmark" onPress={onSave} />
      <Button
        label="Delete deck"
        icon="trash-outline"
        variant="danger"
        onPress={onDelete}
        style={{ marginTop: spacing.md }}
      />
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
    paddingBottom: spacing.xxl,
  },
  warning: {
    color: colors.warning,
    fontSize: 12,
    marginTop: -spacing.sm,
    marginBottom: spacing.lg,
    lineHeight: 18,
  },
  swatches: {
    flexDirection: 'row',
    gap: spacing.md,
  },
  swatch: {
    width: 34,
    height: 34,
    borderRadius: 17,
    borderWidth: 2,
    borderColor: 'transparent',
  },
  swatchSelected: {
    borderColor: colors.text,
  },
});
