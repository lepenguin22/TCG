import * as Clipboard from 'expo-clipboard';
import { Stack, useLocalSearchParams, useRouter } from 'expo-router';
import React, { useMemo, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { ActionSheet, type SheetAction } from '@/components/ActionSheet';
import { CardRow } from '@/components/CardRow';
import { IssueList } from '@/components/IssueList';
import { Button, EmptyState, IconButton } from '@/components/ui';
import { getGame } from '@/games';
import { useStore } from '@/store/DeckStore';
import { accentColor, colors, radius, spacing } from '@/theme';
import { buildDeckView, deckToText, groupZone, zoneCount } from '@/utils/deck';

export default function DeckScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { getDeck, cards, setQuantity, moveEntry, duplicateDeck, deleteDeck, toggleFavorite } = useStore();
  const [showAllIssues, setShowAllIssues] = useState(false);
  const [menu, setMenu] = useState<{ title: string; actions: SheetAction[] } | null>(null);

  const deck = getDeck(id);
  const game = useMemo(() => (deck ? getGame(deck.gameId) : null), [deck]);

  const view = useMemo(() => (deck ? buildDeckView(deck, cards) : null), [cards, deck]);
  const issues = useMemo(() => (game && view ? game.validate(view) : []), [game, view]);

  if (!deck || !game || !view) {
    return (
      <EmptyState
        icon="help-circle-outline"
        title="Deck not found"
        message="It may have been deleted."
        action={<Button label="Back to decks" onPress={() => router.replace('/')} />}
      />
    );
  }

  const tint = accentColor(deck.accent);
  const visibleIssues = showAllIssues ? issues : issues.slice(0, 3);

  async function onCopy() {
    if (!game || !view) return;
    await Clipboard.setStringAsync(deckToText(game, view));
    Alert.alert('Copied', 'The decklist is on your clipboard as plain text.');
  }

  function onMenu() {
    if (!deck) return;
    setMenu({
      title: deck.name,
      actions: [
        {
          label: deck.favorite ? 'Unpin from top' : 'Pin to top',
          icon: deck.favorite ? 'star-outline' : 'star',
          onPress: () => toggleFavorite(deck.id),
        },
        { label: 'Copy as text', icon: 'copy-outline', onPress: () => void onCopy() },
        {
          label: 'Duplicate deck',
          icon: 'duplicate-outline',
          onPress: () => {
            const copy = duplicateDeck(deck.id);
            if (copy) router.replace(`/deck/${copy.id}`);
          },
        },
        {
          label: 'Deck settings',
          icon: 'options-outline',
          onPress: () => router.push(`/deck/${deck.id}/settings`),
        },
        {
          label: 'Delete deck',
          icon: 'trash-outline',
          destructive: true,
          onPress: () =>
            Alert.alert('Delete deck?', `"${deck.name}" will be removed. This cannot be undone.`, [
              { text: 'Cancel', style: 'cancel' },
              {
                text: 'Delete',
                style: 'destructive',
                onPress: () => {
                  deleteDeck(deck.id);
                  router.replace('/');
                },
              },
            ]),
        },
      ],
    });
  }

  function onCardOptions(cardId: string, cardName: string, zoneId: string) {
    if (!deck || !game || !view) return;
    const otherZones = view.format.zoneIds.filter((z) => z !== zoneId);
    setMenu({
      title: cardName,
      actions: [
        {
          label: 'Edit card details',
          icon: 'create-outline',
          onPress: () => router.push(`/card-editor?cardId=${cardId}&gameId=${deck.gameId}`),
        },
        ...otherZones.map((target) => ({
          label: `Move to ${game.zones.find((z) => z.id === target)?.name ?? target}`,
          icon: 'swap-horizontal-outline' as const,
          onPress: () => moveEntry(deck.id, cardId, zoneId, target),
        })),
        {
          label: 'Remove from deck',
          icon: 'trash-outline',
          destructive: true,
          onPress: () => setQuantity(deck.id, cardId, zoneId, 0),
        },
      ],
    });
  }

  return (
    <ScrollView
      style={styles.screen}
      contentContainerStyle={{ padding: spacing.lg, paddingBottom: insets.bottom + spacing.xxl }}
    >
      <Stack.Screen
        options={{
          title: deck.name,
          headerRight: () => (
            <View style={styles.headerActions}>
              <IconButton
                icon="stats-chart-outline"
                accessibilityLabel="Deck breakdown"
                onPress={() => router.push(`/deck/${deck.id}/stats`)}
              />
              <IconButton icon="ellipsis-horizontal" accessibilityLabel="Deck actions" onPress={onMenu} />
            </View>
          ),
        }}
      />

      <View style={[styles.summary, { borderLeftColor: tint }]}>
        <Text style={styles.formatName}>
          {game.shortName} · {view.format.name}
        </Text>
        {deck.description ? <Text style={styles.description}>{deck.description}</Text> : null}
        <View style={styles.counters}>
          {view.format.zoneIds.map((zoneId) => {
            const zone = game.zones.find((z) => z.id === zoneId);
            const target = view.format.targets[zoneId];
            const count = zoneCount(view, zoneId);
            const goal = target?.exact ?? target?.max;
            const good = goal === undefined ? true : target?.exact ? count === goal : count <= goal;
            return (
              <View key={zoneId} style={styles.counter}>
                <Text style={[styles.counterValue, { color: good ? colors.text : colors.warning }]}>
                  {count}
                  {goal !== undefined ? <Text style={styles.counterGoal}>{` / ${goal}`}</Text> : null}
                </Text>
                <Text style={styles.counterLabel}>{zone?.name ?? zoneId}</Text>
              </View>
            );
          })}
        </View>
      </View>

      <View style={{ marginBottom: spacing.lg }}>
        <IssueList issues={visibleIssues} />
        {issues.length > 3 ? (
          <Pressable onPress={() => setShowAllIssues((v) => !v)} style={styles.moreIssues}>
            <Text style={styles.moreIssuesText}>
              {showAllIssues ? 'Show fewer' : `Show all ${issues.length} issues`}
            </Text>
          </Pressable>
        ) : null}
      </View>

      {view.format.zoneIds.map((zoneId) => {
        const zone = game.zones.find((z) => z.id === zoneId);
        const groups = groupZone(game, view, zoneId);
        const count = zoneCount(view, zoneId);
        const target = view.format.targets[zoneId];
        const goal = target?.exact ?? target?.max;

        return (
          <View key={zoneId} style={styles.zone}>
            <View style={styles.zoneHeader}>
              <View style={{ flex: 1 }}>
                <Text style={styles.zoneTitle}>{zone?.name ?? zoneId}</Text>
                <Text style={styles.zoneCaption}>
                  {count}
                  {goal !== undefined ? ` of ${goal}` : ''} · {zone?.description ?? ''}
                </Text>
              </View>
            </View>

            {groups.length === 0 ? (
              <Text style={styles.zoneEmpty}>Nothing here yet.</Text>
            ) : (
              groups.map((group) => (
                <View key={group.title} style={styles.group}>
                  <View style={styles.groupHeader}>
                    <Text style={styles.groupTitle}>{group.title}</Text>
                    <Text style={styles.groupCount}>{group.count}</Text>
                  </View>
                  {group.rows.map((row) => (
                    <View key={row.card.id}>
                      <CardRow
                        game={game}
                        card={row.card}
                        quantity={row.quantity}
                        onPress={() => onCardOptions(row.card.id, row.card.name, zoneId)}
                        onDecrement={() => setQuantity(deck.id, row.card.id, zoneId, row.quantity - 1)}
                        onIncrement={() => setQuantity(deck.id, row.card.id, zoneId, row.quantity + 1)}
                      />
                    </View>
                  ))}
                </View>
              ))
            )}

            <Button
              label={`Add to ${zone?.shortName ?? 'zone'}`}
              icon="add"
              variant="ghost"
              onPress={() => router.push(`/deck/${deck.id}/add?zone=${zoneId}`)}
              style={{ marginTop: spacing.sm }}
            />
          </View>
        );
      })}

      <Button
        label="Breakdown & curve"
        icon="stats-chart-outline"
        variant="secondary"
        onPress={() => router.push(`/deck/${deck.id}/stats`)}
        style={{ marginTop: spacing.md }}
      />

      <ActionSheet
        visible={menu !== null}
        title={menu?.title}
        actions={menu?.actions ?? []}
        onClose={() => setMenu(null)}
      />
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
    backgroundColor: colors.bg,
  },
  headerActions: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  summary: {
    backgroundColor: colors.surface,
    borderRadius: radius.lg,
    borderWidth: 1,
    borderColor: colors.border,
    borderLeftWidth: 4,
    padding: spacing.lg,
    marginBottom: spacing.lg,
  },
  formatName: {
    color: colors.textMuted,
    fontSize: 13,
    fontWeight: '600',
  },
  description: {
    color: colors.textFaint,
    fontSize: 13,
    marginTop: spacing.sm,
    lineHeight: 19,
  },
  counters: {
    flexDirection: 'row',
    gap: spacing.xl,
    marginTop: spacing.md,
  },
  counter: {},
  counterValue: {
    color: colors.text,
    fontSize: 22,
    fontWeight: '800',
  },
  counterGoal: {
    color: colors.textFaint,
    fontSize: 14,
    fontWeight: '600',
  },
  counterLabel: {
    color: colors.textFaint,
    fontSize: 11,
    textTransform: 'uppercase',
    letterSpacing: 0.6,
    marginTop: 2,
  },
  moreIssues: {
    paddingVertical: spacing.sm,
    alignItems: 'center',
  },
  moreIssuesText: {
    color: colors.textMuted,
    fontSize: 13,
    fontWeight: '600',
  },
  zone: {
    marginBottom: spacing.xl,
  },
  zoneHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: spacing.sm,
  },
  zoneTitle: {
    color: colors.text,
    fontSize: 17,
    fontWeight: '700',
  },
  zoneCaption: {
    color: colors.textFaint,
    fontSize: 12,
    marginTop: 2,
  },
  zoneEmpty: {
    color: colors.textFaint,
    fontSize: 13,
    fontStyle: 'italic',
    paddingVertical: spacing.md,
    paddingHorizontal: spacing.md,
  },
  group: {
    marginTop: spacing.sm,
  },
  groupHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: spacing.md,
    paddingVertical: 6,
  },
  groupTitle: {
    color: colors.textMuted,
    fontSize: 12,
    fontWeight: '700',
    textTransform: 'uppercase',
    letterSpacing: 0.6,
  },
  groupCount: {
    color: colors.textFaint,
    fontSize: 12,
    fontWeight: '700',
  },
});
