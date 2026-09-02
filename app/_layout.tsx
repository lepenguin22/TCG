import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import React from 'react';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { DeckStoreProvider } from '@/store/DeckStore';
import { colors } from '@/theme';

export default function RootLayout() {
  return (
    <SafeAreaProvider>
      <DeckStoreProvider>
        <StatusBar style="light" />
        <Stack
          screenOptions={{
            headerStyle: { backgroundColor: colors.bg },
            headerTintColor: colors.text,
            headerTitleStyle: { fontWeight: '700' },
            headerShadowVisible: false,
            contentStyle: { backgroundColor: colors.bg },
          }}
        >
          <Stack.Screen name="index" options={{ title: 'My Decks' }} />
          <Stack.Screen name="new-deck" options={{ title: 'New Deck', presentation: 'modal' }} />
          <Stack.Screen name="card-editor" options={{ title: 'Card', presentation: 'modal' }} />
          <Stack.Screen name="settings" options={{ title: 'Settings' }} />
          <Stack.Screen name="deck/[id]/index" options={{ title: 'Deck' }} />
          <Stack.Screen name="deck/[id]/add" options={{ title: 'Add Cards' }} />
          <Stack.Screen name="deck/[id]/stats" options={{ title: 'Breakdown' }} />
          <Stack.Screen name="deck/[id]/settings" options={{ title: 'Deck Settings' }} />
        </Stack>
      </DeckStoreProvider>
    </SafeAreaProvider>
  );
}
