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

- **Decks** for Standard, V Premium, Premium and a rule-free Casual/brew format,
  each with notes, a colour and a pin-to-top flag.
- **Live rules checking.** Every deck screen shows what is illegal about the list
  right now: the card pool the format draws from, deck size, the four-copy limit
  on a card name, the ride deck's one card of each grade 0-3, the exactly-16
  trigger count, the caps of four heal and one over trigger, G units outside the
  G zone, plus softer advice such as a missing perfect guard.
- **Format card pools.** Standard is D-series only, V Premium is V-series only,
  and Premium is everything from before the D-series. Every card is stamped with
  the eras it has been printed in, so a card reprinted forward into the current
  pool stays legal, while a V-series card in a Standard deck is flagged. Where
  an era cannot be established the app names the cards it could not check
  rather than guessing, and never reports an error it cannot stand behind —
  which now happens for exactly one card in the database, plus anything
  missing from it.
- **Zones** that match how the game is actually laid out — Ride Deck, Main Deck
  and G Zone — with cards grouped by grade and a quantity stepper on each row.
  The ride deck takes four units, one of each grade 0-3, plus the optional ride
  deck crest that Divinez added.
- **A card database of 13,000+ real cards**, bundled in the app and searchable
  offline. Search by name or card number, filter by grade, tap to add: grade,
  card type, nation or clan, power, shield, card number and the card's printed
  abilities are filled in for you. Every English printing is covered, from the
  original sets through the current D-series.
- **Card images and abilities.** Tap the info button on any card, or "View
  card" in a deck, for the card image at full size and its complete rules text.
  Search results and deck lists carry a thumbnail.
- **A personal card library.** Cards you add from the database, or enter by
  hand, are kept for reuse in every later deck. Editing one updates it
  everywhere. Cards saved before the database existed are repaired from it on
  the next launch, filling in only what they are missing — anything you set
  yourself always wins.
- **Breakdown screen** with the grade curve, trigger spread, card types and
  nations.
- **Import from Deck Log.** Paste a share link or deck code from Bushiroad's
  Deck Log, the site behind Fighter Navigator, and the deck comes across with
  its cards matched to the database, sorted into the right zones and ready to
  be checked against the rules. Paste several links, one per line, to import a
  whole collection at once.
- **Playtest against a CPU.** Play a deck out against the computer — a mirror
  match, or any other deck in the library — from the play button on the deck
  screen. See [Playtesting](#playtesting) for what the board does and does not
  run for you.
- **Copy as text** to paste a list into a chat, and a JSON backup you can copy to
  the clipboard and import on another device.

Decks, cards and settings live on the device in `shared_preferences`. There is
no account and no server.

Card **images** are the one part that uses the network: they are fetched from
the official card list the first time each card is shown and cached on the
device afterwards. Everything else — searching the database, reading a card's
abilities, building and checking decks — works with no connection, and a card
with no image simply shows a placeholder.

## About the card database

`assets/cards/vanguard.json` is generated by `tool/build_catalog.dart` from two
sources: the community [Card Game Simulator
dataset](https://github.com/dragogodev/cgs) for everything up to DZ-BT09, and
Bushiroad's official card list for everything after, read by
`tool/scrape_cardlist.py` into `data/cardlist/extra_sets.json`.

That split exists because the community dataset stopped. Its scrape of the
Vanguard list ends at DZ-BT09, and the reason is worth recording: **the card
list answers `404` to anything that does not look like a browser.** It had not
moved and it was not down — a plain HTTP request simply gets a 404 for every
path, including the site root, which reads exactly like a site that is gone.
Sending a browser's `User-Agent` returns the real thing.

The scraper runs in CI rather than locally, since the site is unreachable from
some networks. Each card's own page is server-rendered and carries more than
the mirror ever did: card type, nation, race, clan, grade, power, critical,
shield, the rules text, **the trigger a trigger unit is**, and the format the
card is legal in. The generator takes the
attributes the deck builder needs — name, number, grade, card type, nation or
clan, power, shield and the printed rules text — plus the URL of each card's
official image. Images are referenced rather than bundled: there are over
twenty thousand of them.

To pick up a new set, run the generator and commit the result:

```bash
dart run tool/build_catalog.dart
flutter test test/card_catalog_test.dart
```

Or run the **Refresh card database** workflow from the Actions tab, which does
the same thing and opens a pull request.

### One entry per card, not per name

The game remakes cards under their old names. An 8000 power original and its
10000 power reissue are two different cards; "Flash Shield, Iseult" is a grade 0
trigger unit in one era and a grade 1 normal unit in another. So a card is
identified by its name *and* its stats, and each entry carries the numbers of
every printing it has had — a deck can name any of them, and matching only the
shown one used to fall through to matching by name, which is how one card ended
up standing in for another.

Stats are not the whole of it either. A remake can match the original's numbers
exactly and still be a different card: `DZ-SS13/002` and `D-BT05/005` Blaster
Blade are both grade 2, 10000 power, 5000 shield Keter Sanctuary units, and do
entirely different things — one searches the ride deck for a card with an Aichi
icon, the other retires a rear-guard. Held as one card, a deck naming either was
shown the other's abilities and artwork. So what a card *does* is part of its
identity too, which is also what makes a genuine reprint recognisable: the
printings that agree on it are the ones that should share an entry.

Only what it does, though — not how the text is set. The two sources write the
same ability differently, one bracketing `[Energy-Charge 3]` where the other
does not, one carrying a line of reminder text the other leaves off. Comparing
those verbatim tore genuine reprints apart, so the comparison drops punctuation,
spacing, and parenthesised reminders, while keeping short parentheses like
`(VC)` — the zone an ability works in is a real difference. What survives is
one entry per card, and no card number claimed by two of them.

A deck records the printing it names. Blaster Blade has twenty printings and
the database shows one of them, so a deck built from the Blaster Blade Start
Deck used to come out reading `D-BT05/005EN` — the right card, under a number
its owner had never entered. Where the number a deck gives is one the card is
known by, that printing is what gets stored, in the database's own English
form, so a Japanese deck still reads as English.

Not every printing can be read. The community mirror maps a card's status line
positionally, so one missing or extra field shifts every value along and leaves
a unit with no power, or a power of 3. Those printings are not allowed to invent
a card: where the same name has printings that were read properly, the bad one
folds into them. Only where a name has nothing readable at all does it stand
alone, because 306 cards exist in no other printing.

### Dating a card that carries no date

Formats are eras, so every card needs one, and a few hundred old `PR/` promos
carry nothing in their number to date them by. They can still be placed: the
D-series replaced clans with nations, and the only clans on D-series cards
belong to its collaboration sets, so a card carrying an ordinary clan predates
the D-series. Which older era it is from stays unknown, and the database says
so rather than picking one.

That is enough to answer the question each format actually asks. Standard is
D-series only, so such a card is a clear error. Premium takes every older era,
so it is clearly legal. Only V Premium needs to know *which* older era, and
there the app says it cannot tell. This took the undated count from 196 cards
to one.

### The one thing the database cannot tell you

The source data does not record which trigger a trigger unit is — critical,
draw, front, heal or stand. Over triggers and sentinels are recoverable from the
rules text and are filled in automatically; the rest is not.

So the app asks. The first time you add a trigger unit from the database, it
shows one row of buttons and remembers your answer in your card library, for
that card, forever. For a deck that arrived from an import, where nobody was
asked anything, **Set trigger icons** in the deck menu puts every trigger unit
in the deck on one screen to be answered in a single pass. And if Deck Log
itself names the trigger, the import takes it and nothing needs answering.

The two questions are kept apart, though, because only one of them needs an
answer. Whether a card *is* a trigger unit is in the data, so the "exactly 16
triggers" count is always right, including for a deck imported from Deck Log,
where nobody was asked anything. The icon is needed only for the "at most 4
heal, at most 1 over" caps, and while any of it is unset the deck screen says
those two limits could not be checked instead of passing the deck as clean. The
trigger breakdown counts the unanswered ones under *Not set* rather than
dropping them.

## Importing from Deck Log

[Deck Log](https://decklog-en.bushiroad.com/) is Bushiroad's official deck
site, reached through Fighter Navigator. A shared deck lives at
`decklog-en.bushiroad.com/view/<CODE>`, or on the Japanese site at
`decklog.bushiroad.com/view/<CODE>`; the page is a script driven app fed by a
JSON endpoint that takes the same code, and that endpoint is what the app reads
— one request per import, with the same headers the site's own page sends.

**Both sites work.** They share a code space but not their decks, so a link's
site travels with its code and only that site is asked; a bare code with no
site to go on tries the English one and then the Japanese one.

The payload files each card with a type, a slot and a grade of its own, so the
ride deck is read from what Deck Log says rather than guessed at: type 3 is the
ride deck, and the crest sits in a slot of its own with no grade. Where a
payload carries none of that, the older reading still applies — the section
whose shape fits a ride deck, being four or five cards, one copy each, no two
of a grade.

Paste a link, a link with text around it, or the bare code. Paste several, one
per line, and they all come across in one go — fetched one at a time, in order,
with the same deck pasted twice imported once. One bad code does not cost the
rest: it is reported on its own and the other decks still land.

Cards are matched to the bundled database by card number first and name second,
so an imported deck arrives with grades, triggers, abilities and images filled
in.

Matching by number first is what makes a Japanese deck work. Its cards come back
with Japanese names the English database cannot match, but the two releases of a
set number their cards identically apart from the `EN` the English printings
carry — `D-BT02/001` and `D-BT02/001EN` are the same card — so dropping that
marker bridges the languages and the deck arrives in English. Where an English
printing adds a variant marker (`EB10/021EN-W`, `G-CB04/001EN SGR`) a second,
looser key drops that too, and is used only where it picks out a single card.

A Japanese number carries its rarity where the English one carries `EN` —
`DZ-SS14/001R` against `DZ-SS14/001EN` — so the looser key strips every letter
after the digits.

Then the **card image**, which is the backstop: both sites draw a card's artwork
from the same filename, so `dbt02/dbt02_001.png` finds the card even when the
number is written in a shape the app does not recognise, or is not in the
payload at all. All three keys are checked against the whole database by tests —
numbers collide with nothing, and image filenames identify 11,137 of 11,139
cards, the two that clash being dropped rather than guessed at.

A card with no English printing yet keeps its Japanese name and is still
imported, so a deck ahead of the English releases is never short. It keeps the
grade Deck Log gave it and is dated by its card number, so it is checked
against the format and counted in the curve properly rather than reporting that
it could not be. The import screen lists what it could not match
**with each card's number**, which is what distinguishes a set the English
release has not reached from a number the app failed to read. A card the database does not know is still imported, with the name and count
Deck Log gave, and the import screen lists what it could not match rather than
quietly leaving the deck short.

Zones are worked out from the cards, not from what Deck Log calls its sections.
It serves every game it hosts through one endpoint, so the sections are named
`list`, `sub_list` and `p_list` rather than after what they hold, and nothing
in the payload says which one is a Vanguard ride deck. Instead a G unit goes to
the G zone and a ride deck crest to the ride deck on their own account, and the
ride deck section is recognised by its shape: a handful of cards, one copy of
each, no two of the same grade and nothing above grade 3. A fifty card main
deck cannot be mistaken for that, and neither can a G zone. If a deck arrives
as one flat list, everything stays in the main deck and the import says so
rather than splitting it on a guess.

The import screen shows how many cards landed in each zone, so a deck that came
out in the wrong place is visible immediately.

If the request is ever refused, the endpoint can be opened in a browser and its
JSON pasted into the same box — it is read the same way.

## Playtesting

The play button on a deck screen deals the deck out against the CPU. Pick a
mirror match, or any other deck in the library to test a matchup against.

The board runs the game the way it sits on a table: your opponent's six circles
across the top, yours below, your hand along the bottom, and a control bar that
only ever offers the move the rules are waiting for. It plays out an opening
mulligan, the ride deck climbed a grade at a time, calling to the front and back
rows, boosting from behind, attacks that only the front row can make or receive,
drive checks sized to the vanguard's grade, damage checks, guarding with shields
and perfect guards, and the sixth damage that ends it. Triggers resolve
properly: critical adds power and a critical, draw draws, front lifts the front
row, heal heals when you are not ahead on damage, stand stands a unit. Both
players draw on their own first turn; nobody skips it.

Boosting is asked for rather than assumed. A booster behind the attacker shows
up as a checkbox in the control bar, off until you tick it, because it is not
always wanted — a unit that restands wants its booster kept back for the second
swing, and one spent on the first is not there for it.

### The zones

The zones beside the field are where the game actually happens once abilities
come into it, so they are on the board and tappable rather than left as numbers:

- **Damage** is laid out as the cards it is. A counter-blast turns them face
  down, a counter-charge turns them back, and a spent card still counts towards
  the six that ends the game.
- **Soul** takes a soul-blast per card and a soul-charge off the top of the deck.
- **Deck** shuffles, and lists itself so an ability that searches can be played —
  it reshuffles after a search. It is there for the cards that tell you to look.
- **Drop** hands a card back where something returns one.
- **G zone** appears only for a deck that has one. With a grade 3 vanguard and
  grade 3 worth of cards in hand to discard, a G unit strides on top of the
  vanguard: it triple drives, the unit underneath stays as the heart, and both
  go back where they came from when the turn ends.

### What it will not do for you

It will not play your cards' abilities, and neither will the CPU.

Abilities are English prose in the card database — "[AUTO]:When this unit is
placed on (VC), [COST][Counter-Blast 1], choose one of your opponent's
rear-guards, and retire it" — and there is no encoding of them for a program to
follow. Rather than pretend otherwise, the board runs everything around them and
leaves the abilities to you: tap any unit to read its text and apply what it
says, with controls there for power, standing and resting, retiring, drawing,
energy and damage, and every zone above open for the costs. It is a patient
paper opponent, not a rules engine.

That still answers the questions a deck list cannot. Does it ride through grade
3 reliably? Does the mulligan leave a workable hand? Are sixteen triggers enough
to keep up in the damage race? How much shield is left in hand by turn four? The
CPU climbs its ride deck, builds a board, boosts, swings at your vanguard and
guards to save itself when a hit would be lethal, so those questions get asked
under pressure rather than in a goldfish.

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
  store/catalog_backfill.dart    repairs cards saved before the database
  store/decklog_import.dart      turns a Deck Log deck into one of ours
  import/decklog.dart            the Deck Log client and payload reader
  screens/                       deck list, deck, add cards, card editor,
                                 breakdown, trigger icons, deck settings,
                                 settings
  widgets/                       card rows, images, charts, chips, sheets
  utils/deck_text.dart           plain text export
  games/card_catalog.dart        loading and searching the bundled database
tool/
  build_catalog.dart             regenerates the card database
  scrape_cardlist.py             reads new sets from the official card list
data/
  cardlist/extra_sets.json       what it read, an input to the generator
assets/
  cards/vanguard.json            the generated card database
test/
  vanguard_rules_test.dart       the deck construction rules
  deck_store_test.dart           state, persistence, import and export
  card_catalog_test.dart         search, plus checks on the real asset
  catalog_backfill_test.dart     repairing old cards without losing edits
  trigger_icons_test.dart        setting a deck's trigger icons in one pass
  decklog_import_test.dart       reading Deck Log links, payloads and decks
  decklog_screen_test.dart       the import screen, driven end to end
  catalog_flow_test.dart         searching and adding a card, end to end
  app_flow_test.dart             the screens, driven end to end
```

## Adding iOS

The project is Android only right now, since the goal was an APK. Adding iOS is
one command on a Mac — `flutter create --platforms ios .` — and no Dart code
changes, because nothing in the app is Android specific.
