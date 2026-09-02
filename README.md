# TCG Decks

An offline Android app for storing trading card game decklists, written in
Flutter. The first game it supports is **Cardfight!! Vanguard**, and it knows the
format rules — it checks a list as you build it and tells you exactly what is
wrong with it.

## Getting the APK onto your phone

**From GitHub Actions (no toolchain needed).** Every push builds a signed,
installable APK. Open the repository's **Actions** tab, click the most recent
*Build APK* run, and download the `tcg-decks-apk` artifact at the bottom of the
page. Unzip it, copy the `.apk` to your phone, and open it — Android will ask you
to allow installs from that source the first time.

**As a release.** Tag a commit and the APK is published on the Releases page,
which is a nicer link to open from the phone itself:

```bash
git tag v1.0.0 && git push origin v1.0.0
```

**Building it yourself.** With the Flutter SDK and Android SDK installed:

```bash
flutter pub get
flutter build apk --release
# build/app/outputs/flutter-apk/app-release.apk
```

Plug the phone in and `flutter install` puts it straight on the device.

### About the signing key

`android/debug.keystore` is checked in on purpose. It holds the well-known
Android debug credentials, guards nothing, and is not a secret — but sharing one
key means every build (yours, CI's) is signature-compatible, so a new APK
installs as an update over the old one instead of being refused. The CI build
number becomes the Android `versionCode`, so newer builds always win.

Android installs these APKs happily. The Play Store will not accept them; swap in
a real release key first if you ever go that way.

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
  critical, card number and notes.
- **Breakdown screen** with the grade curve, trigger spread, card types and
  nations.
- **Copy as text** to paste a list into a chat, and a JSON backup you can copy to
  the clipboard and import on another device.

Everything is stored on the device with `shared_preferences`. There is no
account, no server and no network call.

## Checks

```bash
flutter analyze                    # static analysis
flutter test                       # rules, store and widget tests
dart format --set-exit-if-changed lib test
```

CI runs all three before it builds the APK, so a red run means no artifact.

The test suite covers the deck construction rules case by case, the store
(quantities, moving cards between zones, persistence, backup round trips) and the
main screens end to end — creating a deck, entering a card, and seeing it land in
the list.

## Adding another game

The screens are generic; a game is data. `lib/games/game_definition.dart` defines
a `GameDefinition` — its zones, formats, card fields, grouping, validation and
stats — and `lib/games/vanguard/` implements it. To add One Piece, Pokémon or
anything else, write a new folder next to it and add the definition to the list
in `lib/games/games.dart`. The deck list, deck screen, card editor and breakdown
screen all read from that definition, so they pick the new game up with no other
changes. The game filter on the deck list appears on its own once a second game
exists.

## Layout

```
lib/
  main.dart                      app entry and theme wiring
  theme.dart                     dark palette and Material theme
  models/                        Deck, DeckEntry, CardDefinition
  games/
    game_definition.dart         the interface every game implements
    games.dart                   the registry
    vanguard/                    zones, fields, formats, rules, stats
  store/deck_store.dart          state and shared_preferences persistence
  screens/                       deck list, deck, add cards, card editor,
                                 breakdown, deck settings, settings
  widgets/                       card rows, charts, chips, sheets
  utils/deck_text.dart           plain text export
test/
  vanguard_rules_test.dart       the deck construction rules
  deck_store_test.dart           state, persistence, import and export
  app_flow_test.dart             the screens, driven end to end
```

## Adding iOS

The project is Android only right now, since the goal was an APK. Adding iOS is
one command on a Mac — `flutter create --platforms ios .` — and no Dart code
changes, because nothing in the app is Android specific.
