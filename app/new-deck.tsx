import { useRouter } from 'expo-router';
import React, { useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Button, Field, Input } from '@/components/ui';
import { OptionPicker } from '@/components/OptionPicker';
import { DEFAULT_GAME_ID, GAMES, getGame } from '@/games';
import { useStore } from '@/store/DeckStore';
import { ACCENTS, colors, radius, spacing } from '@/theme';

export default function NewDeckScreen() {
  const router = useRouter();
  const { createDeck } = useStore();
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [gameId, setGameId] = useState(DEFAULT_GAME_ID);
  const game = getGame(gameId);
  const [formatId, setFormatId] = useState(game.defaultFormatId);
  const [accent, setAccent] = useState(ACCENTS[0].key);

  const format = game.formats.find((f) => f.id === formatId) ?? game.formats[0];

  function onCreate() {
    const deck = createDeck({ name, description, gameId, formatId, accent });
    router.replace(`/deck/${deck.id}`);
  }

  return (
    <ScrollView style={styles.screen} contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
      <Field label="Deck name">
        <Input
          placeholder="Dragon Empire aggro"
          value={name}
          onChangeText={setName}
          autoFocus
          returnKeyType="done"
        />
      </Field>

      {GAMES.length > 1 ? (
        <Field label="Game">
          <OptionPicker
            options={GAMES.map((g) => ({ value: g.id, label: g.name, color: g.accent }))}
            value={gameId}
            onChange={(value) => {
              setGameId(value);
              setFormatId(getGame(value).defaultFormatId);
            }}
          />
        </Field>
      ) : (
        <Field label="Game">
          <View style={styles.gameCard}>
            <Text style={styles.gameName}>{game.name}</Text>
            <Text style={styles.gameTagline}>{game.tagline}</Text>
          </View>
        </Field>
      )}

      <Field label="Format" helper={format.description}>
        <OptionPicker
          options={game.formats.map((f) => ({ value: f.id, label: f.name }))}
          value={formatId}
          onChange={setFormatId}
        />
      </Field>

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

      <Field label="Notes" helper="Optional. Match-ups, tech choices, anything you want to remember.">
        <Input
          placeholder="What this deck is trying to do…"
          value={description}
          onChangeText={setDescription}
          multiline
        />
      </Field>

      <Button label="Create deck" icon="add" onPress={onCreate} disabled={!name.trim()} />
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
  gameCard: {
    backgroundColor: colors.surfaceAlt,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.border,
    padding: spacing.md,
  },
  gameName: {
    color: colors.text,
    fontSize: 15,
    fontWeight: '700',
  },
  gameTagline: {
    color: colors.textFaint,
    fontSize: 12,
    marginTop: 2,
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
