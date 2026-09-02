import * as Haptics from 'expo-haptics';
import { Stack, useLocalSearchParams, useRouter } from 'expo-router';
import React, { useMemo, useState } from 'react';
import { FlatList, Platform, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { CardRow } from '@/components/CardRow';
import { Button, Chip, EmptyState, Input } from '@/components/ui';
import { getGame } from '@/games';
import { useStore } from '@/store/DeckStore';
import { colors, radius, spacing } from '@/theme';

export default function AddCardsScreen() {
  const { id, zone } = useLocalSearchParams<{ id: string; zone?: string }>();
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { getDeck, cardsForGame, addToDeck } = useStore();
  const [query, setQuery] = useState('');
  const [filters, setFilters] = useState<Record<string, string>>({});

  const deck = getDeck(id);
  const game = deck ? getGame(deck.gameId) : null;
  const zoneId = zone ?? deck?.formatId ?? '';
  const zoneDef = game?.zones.find((z) => z.id === zoneId);

  const library = useMemo(() => {
    if (!deck || !game) return [];
    const needle = query.trim().toLowerCase();
    return cardsForGame(deck.gameId)
      .filter((card) => !needle || card.name.toLowerCase().includes(needle))
      .filter((card) =>
        Object.entries(filters).every(([key, value]) => !value || card.attributes[key] === value),
      )
      .sort((a, b) => game.compareCards(a, b));
  }, [cardsForGame, deck, filters, game, query]);

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

  const quickFilters = game.cardFields.filter(
    (field) => field.type === 'select' && field.options && field.options.length <= 6,
  );

  const inDeck = new Map(
    deck.entries.filter((e) => e.zoneId === zoneId).map((e) => [e.cardId, e.quantity]),
  );

  function onAdd(cardId: string) {
    addToDeck(deck!.id, cardId, zoneId, 1);
    if (Platform.OS !== 'web') void Haptics.selectionAsync();
  }

  const createHref = `/card-editor?gameId=${deck.gameId}&deckId=${deck.id}&zone=${zoneId}`;

  return (
    <View style={styles.screen}>
      <Stack.Screen options={{ title: `Add to ${zoneDef?.name ?? 'deck'}` }} />

      <FlatList
        data={library}
        keyExtractor={(card) => card.id}
        keyboardShouldPersistTaps="handled"
        contentContainerStyle={{ padding: spacing.lg, paddingBottom: insets.bottom + 96 }}
        ListHeaderComponent={
          <View style={{ marginBottom: spacing.md }}>
            <Input placeholder="Search your card library" value={query} onChangeText={setQuery} autoFocus />
            {quickFilters.map((field) => (
              <View key={field.key} style={styles.filterRow}>
                {field.options!.map((option) => (
                  <Chip
                    key={option.value}
                    label={option.label.replace('Grade ', 'G')}
                    compact
                    color={option.color}
                    selected={filters[field.key] === option.value}
                    onPress={() =>
                      setFilters((prev) => ({
                        ...prev,
                        [field.key]: prev[field.key] === option.value ? '' : option.value,
                      }))
                    }
                  />
                ))}
              </View>
            ))}
          </View>
        }
        ListEmptyComponent={
          <EmptyState
            icon="layers-outline"
            title={query ? 'No matching cards' : 'Your card library is empty'}
            message={
              query
                ? 'Nothing in your library matches. Create it as a new card instead.'
                : 'Cards you enter are saved to a personal library, so you only ever type a card in once and can reuse it in every deck.'
            }
            action={<Button label="Create a card" icon="add" onPress={() => router.push(createHref)} />}
          />
        }
        renderItem={({ item }) => {
          const quantity = inDeck.get(item.id) ?? 0;
          return (
            <CardRow
              game={game}
              card={item}
              onPress={() => onAdd(item.id)}
              trailing={
                <View style={styles.trailing}>
                  {quantity > 0 ? <Text style={styles.inDeck}>{quantity} in deck</Text> : null}
                  <Text style={styles.add}>Add</Text>
                </View>
              }
            />
          );
        }}
      />

      <View style={[styles.footer, { paddingBottom: insets.bottom + spacing.md }]}>
        <Button label="Create a new card" icon="add-circle-outline" onPress={() => router.push(createHref)} />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
    backgroundColor: colors.bg,
  },
  filterRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.sm,
    marginTop: spacing.md,
  },
  trailing: {
    alignItems: 'flex-end',
  },
  inDeck: {
    color: colors.textFaint,
    fontSize: 11,
  },
  add: {
    color: colors.accent,
    fontSize: 13,
    fontWeight: '700',
    marginTop: 2,
  },
  footer: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 0,
    padding: spacing.lg,
    paddingTop: spacing.md,
    backgroundColor: colors.bg,
    borderTopWidth: 1,
    borderTopColor: colors.border,
    borderTopLeftRadius: radius.lg,
    borderTopRightRadius: radius.lg,
  },
});
