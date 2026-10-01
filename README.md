# Vanguard Simulator

An offline app for storing trading card game decklists and playing them out,
written in Flutter. It runs on Android and on Windows, from the one codebase:
the screens, the rules and the card database are shared, and each platform
adds only the folder that wraps them. The game it supports is **Cardfight!! Vanguard**, and it
knows the format rules — it checks a list as you build it and tells you exactly
what is wrong with it.

The Dart package is still called `tcg_decks`, and the icon is drawn by
`tool/make_icon.py` rather than kept as a binary nobody can edit.

## Getting the APK onto your phone

**As a release (no toolchain needed).** Tag a commit and a signed, installable
APK is published on the Releases page, which is a link the phone itself can
open:

```bash
git tag v1.0.0 && git push origin v1.0.0
```

Open it on the phone and Android will ask to allow installs from that source
the first time. A release does not expire, and the same run publishes the
Windows build beside it.

Every push still builds the APK, to prove it builds, but does not keep it —
see [Why a build is not a download](#why-a-build-is-not-a-download).

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

## Getting it onto a Windows PC

**As a release.** Every tagged release carries a
`vanguard-simulator-<tag>-windows-x64.zip` next to the APK.

It arrives as a folder: unzip the lot somewhere and run
`vanguard_simulator.exe`. The `.exe` needs the files beside it, so moving it
out on its own will not work. Windows SmartScreen will say it does not
recognise the app, because the build is not signed with a paid-for
certificate; **More info** then **Run anyway** gets past it.

**Building it yourself.** On Windows, with the Flutter SDK and Visual Studio's
"Desktop development with C++" workload:

```powershell
flutter pub get
flutter build windows --release
# build/windows/x64/runner/Release/vanguard_simulator.exe
./tool/package_windows.ps1 -Name vanguard-simulator-windows-x64   # zips it
```

A Windows binary cannot be cross-compiled from Linux or a Mac, which is why
that one job in CI runs on a Windows machine.

## Why a build is not a download

Every push builds both apps, and keeps neither. A release is the only place a
file comes from.

Attaching them to the run was the obvious thing and it did not last. Run
artifacts are charged against a storage allowance the whole account shares,
a 55MB APK on every push spent it inside a few weeks, and from then on every
run went red on the upload while the build itself passed — a red cross that
means nothing, on every push, which is how a real failure gets missed. The
builds still run, so a broken one is still caught on the push that broke it;
what changed is that the file is not kept.

Release assets are not artifacts and are not charged the same way, so a
tagged release is unaffected by any of this, and a release does not expire.

### What is different on a desktop

Almost nothing, deliberately. The same board, the same decks, the same rules.
Two things are worth knowing:

- **The board is laid out for the window above 820 logical pixels wide.** The
  cards are drawn to whatever size fits both players on the screen at once,
  the piles move to a column beside each field, and the battle and the log —
  which a phone squeezes between the boards and hides behind a button — get a
  column of their own down the left. The whole app is held to 1100 pixels
  wide, since six circles stretched across a maximised monitor is a row nobody
  would deal out on a table. Below 820 a phone gets the board it always had.
- **Decks do not travel by themselves.** A PC and a phone are separate devices
  with separate storage, and there is no account and no server. Settings →
  *Copy a backup* puts the library on the clipboard, and Settings on the other
  device reads it back.

Two-player mode works between a PC and a phone on the same network. Windows
asks whether to allow the app through the firewall the first time it hosts;
without that, nothing can dial in.

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
  yourself always wins. The repair matches on the card number the way an
  import does, so a card saved under a Japanese printing, or one carrying its
  rarity, still finds the English entry; a number two different cards could
  answer to repairs neither, since guessing there writes one card's abilities
  onto the other.
- **Breakdown screen** with the grade curve, trigger spread, card types and
  nations.
- **Import from Deck Log.** Paste a share link or deck code from Bushiroad's
  Deck Log, the site behind Fighter Navigator, and the deck comes across with
  its cards matched to the database, sorted into the right zones and ready to
  be checked against the rules. Paste several links, one per line, to import a
  whole collection at once.
- **Playtest a deck out.** Play a deck against a mirror match, or against any
  other deck in the library, from the play button on the deck screen. Both
  hands are yours; the board offers each ability at the moment it fires. See
  [Playtesting](#playtesting) for what it does and does not run for you.
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

### The cards that are not deck cards

A Stride Deckset's crest is filed by the card list under no card type at all
— "Others", the same label it gives a Plant token and a marker — so the
generator dropped it with them, and a deck built around Nightrose or Harri
could be imported, checked and played out with the one card that makes it
work missing entirely.

They are kept now, typed `crest`, identified by the line that is the whole
point of them: *"[CONT]:You can perform [Stride]"*. That is a narrow rule on
purpose. The rest of what the card list calls "Others" really is undeckable
noise, and a broader rule would put Plant tokens in the card search.

Being in the database does not make one a deck card: a deck holding one is an
error, since an ability puts it into play from outside the deck.

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

The play button on a deck screen deals the deck out. Pick a mirror match, or
any other deck in the library to test a matchup against, and who takes the
first turn. Turn order is not a formality: whoever goes second is paid three
energy by the crest to make up for being a turn behind on the board, so a deck
is worth trying from both sides. Choosing the roll re-rolls it on every restart
rather than fixing it once.

### One board, two hands

There is no computer opponent. A program that reads card text can play the
simple abilities and not the rest, which for a deck built on the rest is not a
test at all -- the deck comes out as a set of vanilla bodies and the game it
really plays never happens. So both hands are yours.

It is one board with two hands on it. Both openings are mulliganed, one after
the other. The turn passes from one player to the other and stops there, and
every control on the board goes on working for whoever's turn it is -- the ride
sheet rides their deck, a card called comes out of their hand, the abilities
applied by hand are applied to their units. When an attack is declared the
board asks the *defender* to guard it, with the defender's own cards, before
handing it back to the attacker to drive and resolve.

The sides are **Player 1** and **Player 2**, and the board says which of them
it is talking to at every step: the title bar names whose turn it is, the hand
strip names whose hand it is showing, and the control bar prefixes what it is
waiting for with the name of the player it wants it from. Player 1's board
stays at the bottom throughout, so the half you are looking at does not move
when the turn does.

For a game against another person on another phone, see **two devices** on the
setup screen: each plays their own deck off their own device.

### Lock

A locked card is turned face down on its circle, and the board treats it as
what it is: **not a unit**. It cannot attack, boost, be attacked or be chosen,
a front trigger passes it by, it does not move or swap up its column, and
nothing can be called over it — the circle is held shut, which is the whole
point of locking one.

Lock is on any rear-guard's sheet, on either board, since the card being
locked is usually the opponent's. It shows face down on the circle, art
upside down under a lock, with no power on it.

It unlocks on its own at the end of its owner's turn, which is the rule: a lock
laid on your turn costs them that unit for exactly one turn of theirs. **Unlock**
is on the locked card's sheet for the effects that turn it back over early.

Rear-guards move between the rows of their own column during your main phase,
which is how a booster becomes an attacker or an attacker drops back to push.
Tap one and the sheet offers the move, or the swap when its opposite number is
occupied; the unit keeps its power and its rested state, since only where it
stands has changed. The middle column has no move: nothing goes onto the
vanguard circle, so the unit behind it stays where it is.

Boosting is asked for rather than assumed. A booster behind the attacker shows
up as a checkbox in the control bar, off until you tick it, because it is not
always wanted — a unit that restands wants its booster kept back for the second
swing, and one spent on the first is not there for it.

A boost is worth the booster's power **as it stands**, not as printed: an
8000 booster given +5000 pushes for 13000. That matters for a deck that pumps
its back row, and the number in the checkbox is the one being added, so what
the attack comes to can be read off the board before it is made.

**Only grades 0 and 1 boost.** [Boost] is printed on those and on nothing
else, so a grade 2 or 3 standing in the back row is a body and not a booster:
the checkbox does not appear, and the control bar says which unit it is and
why rather than leaving a tap unanswered.

Plenty of cards hand the keyword out all the same — *"this unit gets 'Boost'
until end of turn"* — so any grade 2 or greater rear-guard's sheet offers
**Give [Boost]**, on either board. A unit carrying it is marked **⇧** beside
its power and boosts like any grade 1 until the end of the turn, when it wears
off with everything else a turn hands out. **Take [Boost] back** undoes it.

### Abilities the board offers you

Abilities in the database are prose written for a person — "[AUTO](VC):When
this unit attacks a vanguard, this unit gets [Power]+5000 until end of that
battle" — and nothing in the app encodes what they do. Carrying one out
automatically is a high bar: it needs the timing, the cost **and** every
effect, and most of a real card pool fails it.

But you are not in that position. You are holding the cards, and what you are
missing is never what the ability means — it is printed in front of you — it is
the two things easy to lose track of mid-game: **the moment it applies**, and
**what it costs**.

So that is the half the board reads. Where it can work out when a clause fires
and what it takes, it says so at the moment it fires:

```
Shiranui has an ability now                                        Read ›

  Shiranui, Vice-Emperor Dragon            Front left · Counter-Blast 1
  [AUTO](RC):When this unit is placed on (RC), [COST][Counter-Blast 1],
  choose one of your rear-guards, and [Stand] it.

                                                    Skip   Pay and use
```

Accepting turns the damage face down, writes the line into the log, and stops
there. Standing the rear-guard is yours, with the same controls you would have
used anyway. The board is not playing the card for you — it is knowing when to
ask, which is the part a person actually loses track of.

Nothing about this is written per card, which is the whole point. One strip
serves the entire pool: **5,946 clauses of the 22,595 in the database**, and
the number grows with the reader rather than with anything typed out by hand.

The moments it watches are the ones the board can see happen: a unit being
**called**, a **ride**, an **attack** declared, the **boost** behind it, a
**stride**, and a card **discarded to pay for a stride**. An [ACT] ability is
asked for rather than raised, since it happens when its controller decides.

Two things are refused outright rather than guessed at:

- **A cost it cannot read**, since paying the cost is the whole of what
  accepting does. A cost whose number it cannot make out is a refusal, never a
  free ability.
- **A clause naming two different moments**, since one raised at the wrong
  moment is worse than none.

A cost that spends the unit itself — retiring it, or putting it into the soul —
is not offered either: the board pays when you accept and you apply the effect
afterwards, so taking the unit away first would remove the thing the rest of
the clause is about.

Conditions work the other way round. The ones it can follow gate the offer: a
named crest in the crest zone, a named vanguard of at least a grade, a
Generation Break, a Limit Break, a drop or damage zone or hand that deep, how
many rear-guards are standing, the opponent's vanguard's grade, whether the
unit is hollowed, whether its controller went second. The ones it cannot are
passed over rather than assumed false, so an offer can appear on a board that
does not quite meet the clause. Declining costs a tap, which is the right price
for reaching several thousand more cards.

The **costs** it can pay are the ones the board can actually spend: a
counter-blast, a soul-blast, energy, a discard however the card words it, the
top few cards of the deck into the drop, a G zone card turned face up, and
resting the unit. Two costs written in one bracket (*"[Counter-Blast 1 &
Soul-Blast 1]"*) are both paid. Where a discard is the cost, which card to
throw away is asked rather than chosen for you.

An offer left unanswered when the turn ends was declined by not being
answered, so nothing lingers into a turn it does not belong to.

Lines that are not an ability it failed to follow are not counted as one: a
reminder in brackets, `[CONT]:Sentinel` — the board plays the perfect guard off
the card type — and the stride cost, which the board's own stride pays. A
`[CONT]` ability is not offered at all: it is simply true while the unit stands
there, so there is no moment to raise and nothing to accept. Those stay yours
to keep track of.

**The ceiling is vocabulary, not design.** The reader knows about twenty-five
ways of writing a timing, and the card pool uses hundreds — *"when this unit is
put on (GC)"*, *"when your vanguard attacks"*, *"at the beginning of your
battle phase"*. Each one taught is more of the pool offered with no new
interface at all, and `tool/ability_coverage.dart` ranks what is left by what
it would buy:

```bash
dart run tool/ability_coverage.dart DZ-SS03        # a set
dart run tool/ability_coverage.dart --name Harri   # a card name
```


### Energy

A deck carrying a ride deck crest gets its energy charged automatically,
because the crest does it on its own every turn and having to remember it by
hand is how a playtest drifts out of sync with a real game. The rules come off
the card rather than out of a guess:

```
[AUTO]Ride Deck: When you ride, put this card into the crest zone,
                 and if you went second, [Energy-Charge 3].
[CONT]: You may have up to ten energy.
[AUTO]: At the beginning of your ride phase, [Energy-Charge 3].
```

Which settles the first turn — whichever player that turns out to be — and it
settles it by timing rather than by a special case. The charge happens at the *beginning* of the ride phase, and the
crest does not reach the crest zone until you actually ride — during that same
phase, after the moment has passed. So whoever goes first charges nothing on
turn one. Whoever goes second charges nothing at the beginning of theirs
either, but is paid three when the crest lands, which is what the "if you went
second" clause is for. From each player's second turn onwards both charge three
a turn, and both stop at ten.

The number is read off the crest's own text, so a crest printing a different
one is followed rather than overruled; three is the default where the database
never carried the text. Spending energy stays yours, since every ability that
costs it is prose — the crest tile on the board has blast buttons for it.

**Ten is not always ten.** Cards raise the ceiling — DZ-BT15/001 Wirbel Kenig
reads *"The maximum energy you may have in the [CONT] ability of the 'Energy
Generator' in your crest zone gets +5"*, which is a deck played to fifteen —
so the cap is a number each player carries rather than a constant. The crest
sheet sets it: **Cap 15**, **Cap 10**, and ±1 for a card that says something
else. A raised cap is a lasting thing and stays until you change it back;
lowering it below the energy already held spills the difference, since a cap
is a maximum and not a promise.

### The battle, as its zones

Between the two boards sit the two zones a fight is actually read from.

The **guardian circle** holds the cards thrown in front of an attack, as the
cards they are rather than as a shield total: what was spent, whether a
perfect guard was among them, and what it adds up to. It appears with the
attack and clears when the battle ends, the guardians going to the drop the
way they do in the game.

The **trigger zone** holds everything the battle turned face up, drive checks
and damage checks together, in the order they were checked and marked for
which was which and whose it was — your drive and their damage come off the
same attack.

**Tap a checked trigger to say who gets what.** The board hands a trigger to
the unit that is fighting, which is right nearly every time — but the game
does not make that decision for you, and the split is often the point: the
critical on the vanguard and the ten thousand power on a rear-guard about to
swing. The sheet lists your units under *Power* and again under *Critical*,
and picking one takes what was given off the unit that had it and hands it
over. It can be moved again, so a first guess costs nothing. It stays up after the attack resolves, deliberately: the damage
is checked *during* the resolve, and clearing it then would take the card away
before it could be read. The next attack clears it.

### The zones

The zones beside the field are where the game actually happens once abilities
come into it, so they are on the board and tappable rather than left as numbers:

- **Damage** is laid out as the cards it is. A counter-blast turns them face
  down, a counter-charge turns them back, and a spent card still counts towards
  the six that ends the game.
- **Soul** takes a soul-blast per card and a soul-charge off the top of the deck.
- **Deck** opens on what can be done to it without looking at it: **draw a
  card**, shuffle, **look at the top cards**, or — deliberately, one tap
  further in — look through the whole thing for an ability that searches,
  which reshuffles afterwards. Drawing is the common thing and reading the
  whole deck is the rare one, so laying the deck out is never the price of
  taking the top card off it.

  **Looking at the top** is its own thing, because *"look at the top five
  cards of your deck, choose one, put it into your hand"* is one of the
  commonest abilities in the game and it is emphatically not a search. The
  sheet shows three, five or seven — switchable without reopening — in order,
  top card first, and each one can go **to hand, to the drop, to the soul or
  to the bottom**, which between them are where those abilities send what they
  find. The five you are shown are the five you chose to look at: taking one
  out leaves four to choose from rather than turning over a replacement, since
  "look at the top five and choose one" is a look at five cards and not a
  draw. What you leave stays exactly where it was, in the order it was in;
  the shuffle at the end is a button rather than something that happens to
  you, since some of these cards shuffle and others put the rest back in
  order.
- **Drop** hands a card back where something returns one, and sends one under
  the deck for the costs that ask for that. It is also where cards **work from
  the drop zone**, which a couple of hundred of them do: a unit carrying
  *"[ACT](Drop):[COST][Remove this card], …"*, or an order played a second
  time from there. **Activate from drop** (**Play from drop**, on an order)
  uses the card and removes it from the game rather than returning it to the
  drop, so it can never be used again — which is what those cards say. Beside
  it, **Remove** takes a card out of the game without using it, for the costs
  that name other cards: *"remove two cards with the same card name as this
  card from drop"* is two Removes and one Activate. Which cards can do any of
  this is on the card, so the board offers it and you read the text.
- **Tickets** is where the cards that are in no deck come from: *"put a
  Persona Shield ticket into your hand"* makes a card out of nothing, so there
  is nowhere on the board to take one from and this is that nowhere. The
  cards come from the database rather than from a list in the app — a ticket
  says what it is on its own face, *"(This card is a ticket card, and cannot
  be put in a deck)"* — so a set that prints another is picked up without the
  app being taught about it. Today that is `DZ-BT15/T01` **Persona Shield**,
  a grade 0 blitz order with no shield of its own, which gives the unit being
  attacked +10000. The pile counts the tickets in your hand.

  The same line is what keeps one out of a deck: a ticket is filed under a
  real card type, so only its text gives it away, and a deck holding one is
  an illegal deck.
- **Removed** only appears once something is out of the game — an over trigger
  that resolved, a card used or spent from the drop. It opens read-only: the
  cards are there to be read, and nothing comes back from it.

Cards go **under the deck** as well as to the drop zone, since a good many
costs are paid that way and where a card ends up decides what can fetch it
back later. A card in hand, in the drop zone or in the soul can be put under
the deck from its own sheet, and a rear-guard goes there straight off the
field, next to the retire it is not.

A rear-guard also goes **into the soul** from its own sheet, which is what a
good many of them pay to do — and it is not a retire: a card in the soul is
there for a soul-blast to spend later, where a card in the drop is not. The
vanguard is never offered it, since the soul is the pile sitting under that
very card.

Calling is not tied to your hand, and not tied to the main phase. Plenty of
abilities call a unit out of the deck, the drop or the soul, and plenty of them
fire mid-battle, so each of those piles offers a **Call** beside its own action
for any unit the vanguard's grade allows, and a circle takes it in the battle
phase as readily as in the main one. A call out of the deck shuffles it
afterwards, the way looking through it always does.
- **Crest** is a zone, not a slot: a player holds more than one at once. A
  **ride deck crest** — the Energy Generator — comes with the deck and puts
  itself in on the first ride. A **stride deck's crest** — `DZ-SS03/T01EN`
  Nightrose, `DZ-SS02/T01EN` Harri and the rest — is not in the deck at all:
  an ability puts it into play, so the crest zone offers them and you play the
  right one when that ability fires. It lands **beside** whatever is already
  there; the Energy Generator does not have to come out for it, because in the
  game it does not. Each can be taken back out on its own.

  What each charges is read off its own card and added up: a stride crest
  charges nothing — it is permission to stride, not an energy engine — while
  the Energy Generator charges its three every ride phase and pays the three
  it owes whoever went second.
- **G zone** appears only for a deck that has one. With a grade 3 vanguard and
  grade 3 worth of cards in hand to discard, a G unit strides on top of the
  vanguard: it triple drives, the unit underneath stays as the heart, and both
  go back where they came from when the turn ends. You pick the G unit and the
  cards that pay for it, and striding again over a stride is allowed — the unit
  standing there goes back to the G zone face up over the same heart.

  G zone cards are **face up or face down**, because that is a resource. A G
  unit returns face up when its stride ends, which is where a Generation Break
  comes from, and any card can be turned up or down by hand for the abilities
  that count them or pay by flipping them. The pile on the board reads `G ↑2`
  when two are face up, so the number an ability is asking about is visible
  without opening anything.

### What it will not do for you

It will not carry your cards' abilities out. It raises them at the moment they
fire and pays what they cost — see
[Abilities the board offers you](#abilities-the-board-offers-you) — and what the
clause then does is yours.

Abilities are English prose in the card database — "[AUTO]:When this unit is
placed on (VC), [COST][Counter-Blast 1], choose one of your opponent's
rear-guards, and retire it" — and there is no encoding of them for a program to
follow. Rather than pretend otherwise, the board runs everything around them and
leaves the effect to you: tap any unit to read its text and apply what it says,
with controls there for power, critical, drive, standing and resting, retiring,
drawing, energy and damage, and every zone above open for the costs.
Power is typed in rather than picked from a list: cards give 2000 and 4000 as
readily as 5000, so the unit sheet has a field — opening on 5000, the commonest
— with buttons to add or take away exactly that much, and a Clear that puts the
unit back to its printed power. Power, critical and drive all wear off at end
of turn the way the game says they do — a unit carrying more than its one critical, or reduced below it, says
so on the board, and the drive check button names how many checks are left.

**Drive checks are flipped one at a time.** A twin drive is two moments at a
table, not a pair of cards that appear together: what the first turns up — the
power a critical trigger hands the attack, a heal, a stand — is read and
applied before the second is flipped. So the button checks once and then says
how many are still owed, on either player's attacks, and the trigger zone fills
a card at a time.

Drive is offered on the vanguard alone, since nothing else drive checks, and
it is cleared each turn like the rest. That is the safer way round for a
continuous drive+1, which has to be re-applied: forgetting to add it shows up
as a missing check, where forgetting to take a temporary one away would
quietly hand out cards.

It is a patient paper table, not a rules engine: it keeps the board, the zones
and the checks straight, and tells you when an ability is due.

That still answers the questions a deck list cannot. Does it ride through grade
3 reliably? Does the mulligan leave a workable hand? Are sixteen triggers enough
to keep up in the damage race? How much shield is left in hand by turn four?

## Checks

```bash
flutter analyze                    # static analysis
flutter test                       # rules, store and widget tests
dart format --set-exit-if-changed lib test
```

CI runs all three before it builds the APK, so a red run means a build that
never happened. The release workflow runs them again before it publishes
anything, on both platforms.

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
  playtest/
    playtest_state.dart          the board: sides, circles, units, the attack
    playtest_engine.dart         the rules, and everything they can adjudicate
    ability_reader.dart          the printed abilities it can and cannot time
    playtest_controller.dart     what the screen asks the game to do
  screens/                       deck list, deck, add cards, card editor,
                                 breakdown, trigger icons, deck settings,
                                 settings
  widgets/                       card rows, images, charts, chips, sheets
  utils/deck_text.dart           plain text export
  games/card_catalog.dart        loading and searching the bundled database
tool/
  build_catalog.dart             regenerates the card database
  scrape_cardlist.py             reads new sets from the official card list
  make_icon.py                   draws the icons, Android and Windows alike
  package_windows.ps1            zips a Windows build into something runnable
android/                         the Android wrapper
windows/                         the Windows wrapper, and nothing else
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
  playtest_engine_test.dart      the rules, one at a time
  ability_reader_test.dart       what it reads, what it refuses, over the
                                 whole card database
  playtest_prompts_test.dart     the abilities it offers, and the strip
  ability_deck.dart              decks built around one ability, for those two
  playtest_flow_test.dart        the board, driven end to end
  playtest_layout_test.dart      the board at four screen sizes
  desktop_layout_test.dart       and what a desktop window does to it
  settings_screen_test.dart      the build it says it is
```

## Adding another platform

Android and Windows are built from this repository today. iOS, macOS and Linux
are each one command — `flutter create --platforms ios .` and so on — and no
Dart code changes, because nothing in the app is specific to a platform: the
only `dart:io` in it is the socket layer two-player mode runs over, which every
one of them has. What each needs is its own folder, its own icon, and its own
job in CI, since a binary for a platform can only be built on it.
