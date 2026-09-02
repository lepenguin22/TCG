import { Ionicons } from '@expo/vector-icons';
import { Stack, useRouter } from 'expo-router';
import React, { useMemo, useState } from 'react';
import { FlatList, Pressable, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Button, Chip, EmptyState, IconButton, Input, Loading } from '@/components/ui';
import { GAMES, getGame } from '@/games';
import { useStore } from '@/store/DeckStore';
import { accentColor, colors, radius, spacing } from '@/theme';
import type { Deck } from '@/types';
import { buildDeckView, deckHealth, zoneCount } from '@/utils/deck';

export default function DeckListScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { ready, decks, cards } = useStore();
  const [query, setQuery] = useState('');
  const [gameFilter, setGameFilter] = useState<string>('all');

  const summaries = useMemo(() => {
    const needle = query.trim().toLowerCase();
    return decks
      .filter((deck) => gameFilter === 'all' || deck.gameId === gameFilter)
      .filter(
        (deck) =>
          !needle ||
          deck.name.toLowerCase().includes(needle) ||
          deck.description.toLowerCase().includes(needle),
      )
      .sort((a, b) => Number(b.favorite) - Number(a.favorite) || b.updatedAt - a.updatedAt)
      .map((deck) => {
        const game = getGame(deck.gameId);
        const view = buildDeckView(deck, cards);
        const health = deckHealth(game, view);
        return {
          deck,
          game,
          health,
          counts: view.format.zoneIds.map((zoneId) => ({
            zone: game.zones.find((z) => z.id === zoneId),
            count: zoneCount(view, zoneId),
            target: view.format.targets[zoneId],
          })),
        };
      });
  }, [cards, decks, gameFilter, query]);

  if (!ready) return <Loading />;

  return (
    <View style={styles.screen}>
      <Stack.Screen
        options={{
          headerRight: () => (
            <IconButton
              icon="settings-outline"
              accessibilityLabel="Settings"
              onPress={() => router.push('/settings')}
            />
          ),
        }}
      />

      <FlatList
        data={summaries}
        keyExtractor={(item) => item.deck.id}
        contentContainerStyle={{ padding: spacing.lg, paddingBottom: insets.bottom + 96 }}
        ListHeaderComponent={
          decks.length > 0 ? (
            <View style={{ marginBottom: spacing.lg }}>
              <Input placeholder="Search decks" value={query} onChangeText={setQuery} />
              {GAMES.length > 1 ? (
                <View style={styles.filters}>
                  <Chip
                    label="All games"
                    compact
                    selected={gameFilter === 'all'}
                    onPress={() => setGameFilter('all')}
                  />
                  {GAMES.map((game) => (
                    <Chip
                      key={game.id}
                      label={game.shortName}
                      compact
                      color={game.accent}
                      selected={gameFilter === game.id}
                      onPress={() => setGameFilter(game.id)}
                    />
                  ))}
                </View>
              ) : null}
            </View>
          ) : null
        }
        ListEmptyComponent={
          <EmptyState
            icon="albums-outline"
            title={decks.length === 0 ? 'No decks yet' : 'Nothing matches'}
            message={
              decks.length === 0
                ? 'Build your first Cardfight!! Vanguard list. The app checks it against the format rules as you go.'
                : 'Try a different search or clear the game filter.'
            }
            action={
              decks.length === 0 ? (
                <Button label="Create a deck" icon="add" onPress={() => router.push('/new-deck')} />
              ) : null
            }
          />
        }
        renderItem={({ item }) => (
          <DeckCard
            deck={item.deck}
            gameName={item.game.shortName}
            formatName={item.game.formats.find((f) => f.id === item.deck.formatId)?.name ?? ''}
            errors={item.health.errors}
            warnings={item.health.warnings}
            counts={item.counts}
            onPress={() => router.push(`/deck/${item.deck.id}`)}
          />
        )}
      />

      <View style={[styles.fabWrap, { bottom: insets.bottom + spacing.lg }]}>
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="New deck"
          onPress={() => router.push('/new-deck')}
          style={({ pressed }) => [styles.fab, pressed && { opacity: 0.85 }]}
        >
          <Ionicons name="add" size={22} color="#0E1116" />
          <Text style={styles.fabLabel}>New deck</Text>
        </Pressable>
      </View>
    </View>
  );
}

function DeckCard({
  deck,
  gameName,
  formatName,
  errors,
  warnings,
  counts,
  onPress,
}: {
  deck: Deck;
  gameName: string;
  formatName: string;
  errors: number;
  warnings: number;
  counts: { zone?: { shortName: string }; count: number; target?: { exact?: number; max?: number } }[];
  onPress: () => void;
}) {
  const tint = accentColor(deck.accent);
  const status =
    errors > 0
      ? { color: colors.danger, label: `${errors} rule ${errors === 1 ? 'issue' : 'issues'}` }
      : warnings > 0
        ? { color: colors.warning, label: `${warnings} ${warnings === 1 ? 'note' : 'notes'}` }
        : { color: colors.success, label: 'Legal' };

  return (
    <Pressable
      onPress={onPress}
      style={({ pressed }) => [styles.deckCard, { borderLeftColor: tint }, pressed && { opacity: 0.8 }]}
    >
      <View style={styles.deckHeader}>
        <Text style={styles.deckName} numberOfLines={1}>
          {deck.favorite ? '★ ' : ''}
          {deck.name}
        </Text>
        <View style={[styles.statusDot, { backgroundColor: status.color }]} />
      </View>
      <Text style={styles.deckMeta}>
        {gameName} · {formatName}
      </Text>
      {deck.description ? (
        <Text style={styles.deckDescription} numberOfLines={2}>
          {deck.description}
        </Text>
      ) : null}
      <View style={styles.deckCounts}>
        {counts.map((c, i) => (
          <View key={i} style={styles.countPill}>
            <Text style={styles.countLabel}>{c.zone?.shortName ?? ''}</Text>
            <Text style={styles.countValue}>
              {c.count}
              {c.target?.exact ? `/${c.target.exact}` : c.target?.max ? `/${c.target.max}` : ''}
            </Text>
          </View>
        ))}
        <Text style={[styles.statusLabel, { color: status.color }]}>{status.label}</Text>
      </View>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
    backgroundColor: colors.bg,
  },
  filters: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.sm,
    marginTop: spacing.md,
  },
  deckCard: {
    backgroundColor: colors.surface,
    borderRadius: radius.lg,
    borderWidth: 1,
    borderColor: colors.border,
    borderLeftWidth: 4,
    padding: spacing.lg,
    marginBottom: spacing.md,
  },
  deckHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
  },
  deckName: {
    color: colors.text,
    fontSize: 17,
    fontWeight: '700',
    flex: 1,
  },
  statusDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
  },
  deckMeta: {
    color: colors.textMuted,
    fontSize: 12,
    marginTop: 4,
  },
  deckDescription: {
    color: colors.textFaint,
    fontSize: 13,
    marginTop: spacing.sm,
    lineHeight: 18,
  },
  deckCounts: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    marginTop: spacing.md,
  },
  countPill: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 5,
    backgroundColor: colors.surfaceAlt,
    borderRadius: radius.sm,
    paddingHorizontal: spacing.sm,
    paddingVertical: 4,
  },
  countLabel: {
    color: colors.textFaint,
    fontSize: 11,
    fontWeight: '700',
    textTransform: 'uppercase',
  },
  countValue: {
    color: colors.text,
    fontSize: 12,
    fontWeight: '700',
  },
  statusLabel: {
    fontSize: 12,
    fontWeight: '600',
    marginLeft: 'auto',
  },
  fabWrap: {
    position: 'absolute',
    right: spacing.lg,
  },
  fab: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    backgroundColor: colors.accent,
    paddingHorizontal: spacing.lg,
    paddingVertical: 14,
    borderRadius: radius.pill,
  },
  fabLabel: {
    color: '#0E1116',
    fontWeight: '700',
    fontSize: 15,
  },
});
