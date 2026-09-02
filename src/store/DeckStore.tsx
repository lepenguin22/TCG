import React, { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';
import { DEFAULT_GAME_ID, getGame } from '@/games';
import type { BackupPayload, CardDefinition, Deck, DeckEntry } from '@/types';
import { createId } from '@/utils/id';
import * as storage from './storage';

export interface NewDeckInput {
  name: string;
  gameId?: string;
  formatId?: string;
  description?: string;
  accent?: string;
}

export interface CardInput {
  id?: string;
  gameId: string;
  name: string;
  attributes: Record<string, string>;
}

interface StoreValue {
  ready: boolean;
  decks: Deck[];
  cards: CardDefinition[];
  getDeck: (id: string) => Deck | undefined;
  getCard: (id: string) => CardDefinition | undefined;
  cardsForGame: (gameId: string) => CardDefinition[];
  createDeck: (input: NewDeckInput) => Deck;
  updateDeck: (id: string, patch: Partial<Omit<Deck, 'id' | 'createdAt'>>) => void;
  deleteDeck: (id: string) => void;
  duplicateDeck: (id: string) => Deck | undefined;
  toggleFavorite: (id: string) => void;
  saveCard: (input: CardInput) => CardDefinition;
  deleteCard: (cardId: string) => void;
  addToDeck: (deckId: string, cardId: string, zoneId: string, quantity?: number) => void;
  setQuantity: (deckId: string, cardId: string, zoneId: string, quantity: number) => void;
  moveEntry: (deckId: string, cardId: string, fromZone: string, toZone: string) => void;
  exportBackup: () => BackupPayload;
  importBackup: (payload: BackupPayload) => { decks: number; cards: number };
  resetAll: () => void;
}

const StoreContext = createContext<StoreValue | null>(null);

function touch(deck: Deck): Deck {
  return { ...deck, updatedAt: Date.now() };
}

export function DeckStoreProvider({ children }: { children: React.ReactNode }) {
  const [ready, setReady] = useState(false);
  const [decks, setDecks] = useState<Deck[]>([]);
  const [cards, setCards] = useState<CardDefinition[]>([]);
  const loaded = useRef(false);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const [storedDecks, storedCards] = await Promise.all([storage.loadDecks(), storage.loadCards()]);
      if (cancelled) return;
      setDecks(storedDecks);
      setCards(storedCards);
      loaded.current = true;
      setReady(true);
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  // Persist after the first load so we never write an empty list over real data.
  useEffect(() => {
    if (loaded.current) void storage.saveDecks(decks);
  }, [decks]);
  useEffect(() => {
    if (loaded.current) void storage.saveCards(cards);
  }, [cards]);

  const getDeck = useCallback((id: string) => decks.find((d) => d.id === id), [decks]);
  const getCard = useCallback((id: string) => cards.find((c) => c.id === id), [cards]);
  const cardsForGame = useCallback(
    (gameId: string) => cards.filter((c) => c.gameId === gameId),
    [cards],
  );

  const createDeck = useCallback((input: NewDeckInput) => {
    const gameId = input.gameId ?? DEFAULT_GAME_ID;
    const game = getGame(gameId);
    const now = Date.now();
    const deck: Deck = {
      id: createId('deck'),
      gameId,
      formatId: input.formatId ?? game.defaultFormatId,
      name: input.name.trim() || 'Untitled deck',
      description: input.description?.trim() ?? '',
      accent: input.accent ?? 'ember',
      favorite: false,
      entries: [],
      createdAt: now,
      updatedAt: now,
    };
    setDecks((prev) => [deck, ...prev]);
    return deck;
  }, []);

  const updateDeck = useCallback((id: string, patch: Partial<Omit<Deck, 'id' | 'createdAt'>>) => {
    setDecks((prev) => prev.map((d) => (d.id === id ? touch({ ...d, ...patch }) : d)));
  }, []);

  const deleteDeck = useCallback((id: string) => {
    setDecks((prev) => prev.filter((d) => d.id !== id));
  }, []);

  const duplicateDeck = useCallback(
    (id: string) => {
      const source = decks.find((d) => d.id === id);
      if (!source) return undefined;
      const now = Date.now();
      const copy: Deck = {
        ...source,
        id: createId('deck'),
        name: `${source.name} (copy)`,
        favorite: false,
        entries: source.entries.map((e) => ({ ...e })),
        createdAt: now,
        updatedAt: now,
      };
      setDecks((prev) => [copy, ...prev]);
      return copy;
    },
    [decks],
  );

  const toggleFavorite = useCallback((id: string) => {
    setDecks((prev) => prev.map((d) => (d.id === id ? { ...d, favorite: !d.favorite } : d)));
  }, []);

  const saveCard = useCallback((input: CardInput) => {
    const now = Date.now();
    if (input.id) {
      const updated: CardDefinition = {
        id: input.id,
        gameId: input.gameId,
        name: input.name.trim(),
        attributes: input.attributes,
        createdAt: now,
        updatedAt: now,
      };
      setCards((prev) =>
        prev.map((c) => (c.id === input.id ? { ...updated, createdAt: c.createdAt } : c)),
      );
      return updated;
    }
    const card: CardDefinition = {
      id: createId('card'),
      gameId: input.gameId,
      name: input.name.trim(),
      attributes: input.attributes,
      createdAt: now,
      updatedAt: now,
    };
    setCards((prev) => [card, ...prev]);
    return card;
  }, []);

  const deleteCard = useCallback((cardId: string) => {
    setCards((prev) => prev.filter((c) => c.id !== cardId));
    setDecks((prev) =>
      prev.map((d) =>
        d.entries.some((e) => e.cardId === cardId)
          ? touch({ ...d, entries: d.entries.filter((e) => e.cardId !== cardId) })
          : d,
      ),
    );
  }, []);

  const setQuantity = useCallback((deckId: string, cardId: string, zoneId: string, quantity: number) => {
    setDecks((prev) =>
      prev.map((deck) => {
        if (deck.id !== deckId) return deck;
        const exists = deck.entries.some((e) => e.cardId === cardId && e.zoneId === zoneId);
        let entries: DeckEntry[];
        if (quantity <= 0) {
          entries = deck.entries.filter((e) => !(e.cardId === cardId && e.zoneId === zoneId));
        } else if (exists) {
          entries = deck.entries.map((e) =>
            e.cardId === cardId && e.zoneId === zoneId ? { ...e, quantity } : e,
          );
        } else {
          entries = [...deck.entries, { cardId, zoneId, quantity }];
        }
        return touch({ ...deck, entries });
      }),
    );
  }, []);

  const addToDeck = useCallback((deckId: string, cardId: string, zoneId: string, quantity = 1) => {
    setDecks((prev) =>
      prev.map((deck) => {
        if (deck.id !== deckId) return deck;
        const existing = deck.entries.find((e) => e.cardId === cardId && e.zoneId === zoneId);
        const entries = existing
          ? deck.entries.map((e) =>
              e.cardId === cardId && e.zoneId === zoneId ? { ...e, quantity: e.quantity + quantity } : e,
            )
          : [...deck.entries, { cardId, zoneId, quantity }];
        return touch({ ...deck, entries });
      }),
    );
  }, []);

  const moveEntry = useCallback((deckId: string, cardId: string, fromZone: string, toZone: string) => {
    setDecks((prev) =>
      prev.map((deck) => {
        if (deck.id !== deckId) return deck;
        const moving = deck.entries.find((e) => e.cardId === cardId && e.zoneId === fromZone);
        if (!moving) return deck;
        const rest = deck.entries.filter((e) => !(e.cardId === cardId && e.zoneId === fromZone));
        const target = rest.find((e) => e.cardId === cardId && e.zoneId === toZone);
        const entries = target
          ? rest.map((e) =>
              e.cardId === cardId && e.zoneId === toZone
                ? { ...e, quantity: e.quantity + moving.quantity }
                : e,
            )
          : [...rest, { ...moving, zoneId: toZone }];
        return touch({ ...deck, entries });
      }),
    );
  }, []);

  const exportBackup = useCallback(
    (): BackupPayload => ({
      app: 'tcg-decks',
      version: 1,
      exportedAt: Date.now(),
      decks,
      cards,
    }),
    [cards, decks],
  );

  const importBackup = useCallback((payload: BackupPayload) => {
    const incomingCards = Array.isArray(payload.cards) ? payload.cards : [];
    const incomingDecks = Array.isArray(payload.decks) ? payload.decks : [];
    setCards((prev) => {
      const known = new Set(prev.map((c) => c.id));
      return [...incomingCards.filter((c) => !known.has(c.id)), ...prev];
    });
    setDecks((prev) => {
      const known = new Set(prev.map((d) => d.id));
      return [...incomingDecks.filter((d) => !known.has(d.id)), ...prev];
    });
    return { decks: incomingDecks.length, cards: incomingCards.length };
  }, []);

  const resetAll = useCallback(() => {
    setDecks([]);
    setCards([]);
    void storage.clearAll();
  }, []);

  const value = useMemo<StoreValue>(
    () => ({
      ready,
      decks,
      cards,
      getDeck,
      getCard,
      cardsForGame,
      createDeck,
      updateDeck,
      deleteDeck,
      duplicateDeck,
      toggleFavorite,
      saveCard,
      deleteCard,
      addToDeck,
      setQuantity,
      moveEntry,
      exportBackup,
      importBackup,
      resetAll,
    }),
    [
      ready,
      decks,
      cards,
      getDeck,
      getCard,
      cardsForGame,
      createDeck,
      updateDeck,
      deleteDeck,
      duplicateDeck,
      toggleFavorite,
      saveCard,
      deleteCard,
      addToDeck,
      setQuantity,
      moveEntry,
      exportBackup,
      importBackup,
      resetAll,
    ],
  );

  return <StoreContext.Provider value={value}>{children}</StoreContext.Provider>;
}

export function useStore(): StoreValue {
  const value = useContext(StoreContext);
  if (!value) throw new Error('useStore must be used inside <DeckStoreProvider>');
  return value;
}
