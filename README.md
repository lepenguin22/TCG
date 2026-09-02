# TCG Decks

An offline mobile app for storing trading card game decklists, built with Expo and
React Native. The first game it supports is **Cardfight!! Vanguard**, and it knows
the format rules — it checks a list as you build it and tells you exactly what is
wrong with it.

## What it does

- **Decks** for Standard, Premium and a rule-free Casual/brew format, each with
  notes, a colour and a pin-to-top flag.
- **Live rules checking.** Every deck screen shows what is illegal about the list
  right now: deck size, the four-copy limit on a card name, the ride deck's one
  card of each grade 0-3, the exactly-16 trigger count, the caps of four heal and
  one over trigger, G units in the wrong format or zone, plus softer advice such
  as a missing perfect guard.
- **Zones** that match how the game is actually laid out — Ride Deck, Main Deck
  and G Zone — with cards grouped by grade and a quantity stepper on each row.
- **A personal card library.** You type a card in once and reuse it in every
  deck. Cards carry grade, card type, trigger, nation, clan, power, shield,
  critical, card number, image URL and notes.
- **Breakdown screen** with the grade curve, trigger spread, card types and
  nations.
- **Copy as text** to paste a list into a chat, and a JSON backup you can copy to
  the clipboard and import on another device.

Everything is stored on the device with AsyncStorage. There is no account, no
server and no network call.

## Running it

```bash
npm install
npm start
```

Then scan the QR code with [Expo Go](https://expo.dev/go) on your phone, or press
`a` / `i` to open an Android emulator or iOS simulator.

To build a standalone app you can install without Expo Go, use
[EAS Build](https://docs.expo.dev/build/setup/):

```bash
npx eas-cli build --profile preview --platform android
```

## Checks

```bash
npm run typecheck   # tsc --noEmit
npm test            # the deck construction rules, run under node --test
```

## Adding another game

The screens are generic; a game is data. `src/games/types.ts` defines a
`GameDefinition` — its zones, formats, card fields, grouping, validation and
stats — and `src/games/vanguard/` implements it. To add One Piece, Pokémon or
anything else, write a new folder next to it and add the definition to the array
in `src/games/index.ts`. The deck list, deck screen, card editor and breakdown
screen all read from that definition, so they pick the new game up with no other
changes.

## Layout

```
app/                     expo-router screens
  index.tsx              deck list
  new-deck.tsx           create a deck
  card-editor.tsx        create or edit a card in the library
  settings.tsx           backup, rules reference, reset
  deck/[id]/index.tsx    the deck itself
  deck/[id]/add.tsx      add cards from the library to a zone
  deck/[id]/stats.tsx    breakdown and curve
  deck/[id]/settings.tsx rename, change format, delete
src/
  games/                 game definitions (vanguard/ implements the first one)
  store/                 AsyncStorage persistence and the React context
  components/            shared UI
  utils/deck.ts          deck views, grouping, plain text export
```
