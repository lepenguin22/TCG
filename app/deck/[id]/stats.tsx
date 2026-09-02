import { useLocalSearchParams, useRouter } from 'expo-router';
import React, { useMemo } from 'react';
import { ScrollView, StyleSheet, Text, View } from 'react-native';
import { IssueList } from '@/components/IssueList';
import { StatChart } from '@/components/StatChart';
import { Button, EmptyState } from '@/components/ui';
import { getGame } from '@/games';
import { useStore } from '@/store/DeckStore';
import { colors, radius, spacing } from '@/theme';
import { buildDeckView, totalCount, zoneCount } from '@/utils/deck';

export default function DeckStatsScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const { getDeck, cards } = useStore();
  const deck = getDeck(id);
  const game = deck ? getGame(deck.gameId) : null;
  const view = useMemo(() => (deck ? buildDeckView(deck, cards) : null), [cards, deck]);

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

  const groups = game.stats(view);
  const issues = game.validate(view);
  const distinct = view.items.length;

  return (
    <ScrollView style={styles.screen} contentContainerStyle={styles.content}>
      <View style={styles.totals}>
        <Totals label="Cards" value={totalCount(view)} />
        <Totals label="Distinct" value={distinct} />
        {view.format.zoneIds.map((zoneId) => (
          <Totals
            key={zoneId}
            label={game.zones.find((z) => z.id === zoneId)?.shortName ?? zoneId}
            value={zoneCount(view, zoneId)}
          />
        ))}
      </View>

      <View style={{ marginBottom: spacing.lg }}>
        <IssueList issues={issues} />
      </View>

      {groups.map((group) => (
        <StatChart key={group.title} group={group} />
      ))}
    </ScrollView>
  );
}

function Totals({ label, value }: { label: string; value: number }) {
  return (
    <View style={styles.total}>
      <Text style={styles.totalValue}>{value}</Text>
      <Text style={styles.totalLabel}>{label}</Text>
    </View>
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
  totals: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.sm,
    marginBottom: spacing.lg,
  },
  total: {
    flexGrow: 1,
    minWidth: 72,
    backgroundColor: colors.surface,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.border,
    paddingVertical: spacing.md,
    paddingHorizontal: spacing.md,
  },
  totalValue: {
    color: colors.text,
    fontSize: 20,
    fontWeight: '800',
  },
  totalLabel: {
    color: colors.textFaint,
    fontSize: 11,
    textTransform: 'uppercase',
    letterSpacing: 0.6,
    marginTop: 2,
  },
});
