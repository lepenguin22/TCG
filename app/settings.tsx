import * as Clipboard from 'expo-clipboard';
import { useRouter } from 'expo-router';
import React from 'react';
import { Alert, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Button, SectionHeader } from '@/components/ui';
import { GAMES } from '@/games';
import { useStore } from '@/store/DeckStore';
import { colors, radius, spacing } from '@/theme';
import type { BackupPayload } from '@/types';

export default function SettingsScreen() {
  const router = useRouter();
  const { decks, cards, exportBackup, importBackup, resetAll } = useStore();

  async function onExport() {
    const payload = exportBackup();
    await Clipboard.setStringAsync(JSON.stringify(payload, null, 2));
    Alert.alert(
      'Backup copied',
      `${payload.decks.length} decks and ${payload.cards.length} cards are on your clipboard as JSON. Paste it somewhere safe.`,
    );
  }

  async function onImport() {
    const raw = await Clipboard.getStringAsync();
    if (!raw.trim()) {
      Alert.alert('Clipboard is empty', 'Copy a backup as JSON first, then try again.');
      return;
    }
    let payload: BackupPayload;
    try {
      payload = JSON.parse(raw) as BackupPayload;
    } catch {
      Alert.alert('Could not read that', 'The clipboard does not contain valid JSON.');
      return;
    }
    if (payload.app !== 'tcg-decks' || !Array.isArray(payload.decks)) {
      Alert.alert('Not a backup', 'That JSON was not exported by this app.');
      return;
    }
    Alert.alert(
      'Import backup?',
      `Adds ${payload.decks.length} decks and ${payload.cards?.length ?? 0} cards. Anything already on this device is kept.`,
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Import',
          onPress: () => {
            const result = importBackup(payload);
            Alert.alert('Imported', `${result.decks} decks and ${result.cards} cards added.`);
          },
        },
      ],
    );
  }

  function onReset() {
    Alert.alert('Delete everything?', 'Every deck and every card in your library will be erased.', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Delete all',
        style: 'destructive',
        onPress: () => {
          resetAll();
          router.replace('/');
        },
      },
    ]);
  }

  return (
    <ScrollView style={styles.screen} contentContainerStyle={styles.content}>
      <View style={styles.stats}>
        <Stat label="Decks" value={decks.length} />
        <Stat label="Cards in library" value={cards.length} />
      </View>

      <SectionHeader title="Backup" caption="Everything lives on this device only." />
      <Button label="Copy backup to clipboard" icon="copy-outline" variant="secondary" onPress={() => void onExport()} />
      <Button
        label="Import from clipboard"
        icon="download-outline"
        variant="secondary"
        onPress={() => void onImport()}
        style={{ marginTop: spacing.sm }}
      />

      <View style={{ height: spacing.xl }} />

      <SectionHeader title="Deck building rules" caption="What the app checks for you." />
      {GAMES.map((game) => (
        <View key={game.id} style={styles.rules}>
          <Text style={styles.gameName}>{game.name}</Text>
          {game.formats.map((format) => (
            <View key={format.id} style={styles.rule}>
              <Text style={styles.ruleTitle}>{format.name}</Text>
              <Text style={styles.ruleText}>{format.description}</Text>
            </View>
          ))}
          {game.zones.map((zone) => (
            <View key={zone.id} style={styles.rule}>
              <Text style={styles.ruleTitle}>{zone.name}</Text>
              <Text style={styles.ruleText}>{zone.description}</Text>
            </View>
          ))}
          <View style={styles.rule}>
            <Text style={styles.ruleTitle}>Triggers</Text>
            <Text style={styles.ruleText}>
              Exactly 16 trigger units in the main deck, at most 4 heal triggers and at most 1 over trigger.
            </Text>
          </View>
        </View>
      ))}

      <View style={{ height: spacing.xl }} />

      <SectionHeader title="Danger zone" />
      <Button label="Delete all data" icon="trash-outline" variant="danger" onPress={onReset} />

      <Text style={styles.footer}>TCG Decks · offline decklist tracker</Text>
    </ScrollView>
  );
}

function Stat({ label, value }: { label: string; value: number }) {
  return (
    <View style={styles.stat}>
      <Text style={styles.statValue}>{value}</Text>
      <Text style={styles.statLabel}>{label}</Text>
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
  stats: {
    flexDirection: 'row',
    gap: spacing.sm,
    marginBottom: spacing.xl,
  },
  stat: {
    flex: 1,
    backgroundColor: colors.surface,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: colors.border,
    padding: spacing.md,
  },
  statValue: {
    color: colors.text,
    fontSize: 22,
    fontWeight: '800',
  },
  statLabel: {
    color: colors.textFaint,
    fontSize: 11,
    textTransform: 'uppercase',
    letterSpacing: 0.6,
    marginTop: 2,
  },
  rules: {
    backgroundColor: colors.surface,
    borderRadius: radius.lg,
    borderWidth: 1,
    borderColor: colors.border,
    padding: spacing.lg,
  },
  gameName: {
    color: colors.text,
    fontSize: 15,
    fontWeight: '700',
    marginBottom: spacing.sm,
  },
  rule: {
    marginTop: spacing.md,
  },
  ruleTitle: {
    color: colors.textMuted,
    fontSize: 12,
    fontWeight: '700',
    textTransform: 'uppercase',
    letterSpacing: 0.6,
  },
  ruleText: {
    color: colors.textFaint,
    fontSize: 13,
    lineHeight: 19,
    marginTop: 3,
  },
  footer: {
    color: colors.textFaint,
    fontSize: 12,
    textAlign: 'center',
    marginTop: spacing.xl,
  },
});
