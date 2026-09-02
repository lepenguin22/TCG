import AsyncStorage from '@react-native-async-storage/async-storage';
import type { CardDefinition, Deck } from '@/types';

const DECKS_KEY = 'tcgdecks:v1:decks';
const CARDS_KEY = 'tcgdecks:v1:cards';

async function readJson<T>(key: string, fallback: T): Promise<T> {
  try {
    const raw = await AsyncStorage.getItem(key);
    if (!raw) return fallback;
    return JSON.parse(raw) as T;
  } catch {
    return fallback;
  }
}

export async function loadDecks(): Promise<Deck[]> {
  return readJson<Deck[]>(DECKS_KEY, []);
}

export async function loadCards(): Promise<CardDefinition[]> {
  return readJson<CardDefinition[]>(CARDS_KEY, []);
}

export async function saveDecks(decks: Deck[]): Promise<void> {
  await AsyncStorage.setItem(DECKS_KEY, JSON.stringify(decks));
}

export async function saveCards(cards: CardDefinition[]): Promise<void> {
  await AsyncStorage.setItem(CARDS_KEY, JSON.stringify(cards));
}

export async function clearAll(): Promise<void> {
  await AsyncStorage.multiRemove([DECKS_KEY, CARDS_KEY]);
}
