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
any other deck in the library to test a matchup against, choose **who plays
the other side** — the CPU, or you — and who takes the first turn. Turn order
is not a formality: whoever goes second is paid three energy by the crest to
make up for being a turn behind on the board, so a deck is worth trying from
both sides. Choosing the roll re-rolls it on every restart rather than fixing
it once.

### Playing both sides

The CPU only plays the abilities the reader can follow, which for a deck built
on the ones it cannot is not a test at all — the deck comes out as a set of
vanilla bodies and the game it really plays never happens. So the other side
can be yours as well.

Pick **You, both sides** and there is no CPU in the game: it is one board with
two hands on it, both of them yours. Both openings are mulliganed, one after
the other. The turn passes from one player to the other and stops there, and
every control on the board goes on working for whoever's turn it is — the ride
sheet rides their deck, a card called comes out of their hand, the abilities
applied by hand are applied to their units. When an attack is declared the
board asks the *defender* to guard it, with the defender's own cards, before
handing it back to the attacker to drive and resolve.

The sides are called **Player 1** and **Player 2** rather than You and the
CPU, and the board says which of them it is talking to at every step: the
title bar names whose turn it is, the hand strip names whose hand it is
showing, and the control bar prefixes what it is waiting for with the name of
the player it wants it from. Player 1's board stays at the bottom throughout,
the way it would if you were sitting on one side of a table and reaching
across.

Nothing about the rules changes: the turn one attack ban, the energy for going
second, boosting, triggers, the sixth damage. What changes is that nothing at
all happens unless you do it, which is what testing a deck whose abilities no
program can read actually requires.

The board runs the game the way it sits on a table: your opponent's six circles
across the top, yours below, your hand along the bottom, and a control bar that
only ever offers the move the rules are waiting for. It plays out an opening
mulligan, the ride deck climbed a grade at a time — each of those rides paid
for with a card discarded from hand, which the board asks you to pick and an
empty hand cannot afford — calling to the front and back
rows, boosting from behind, attacks that only the front row can make or receive,
drive checks sized to the vanguard's grade, damage checks, guarding with shields
and perfect guards, and the sixth damage that ends it. Triggers resolve
properly, and for **+10000 power** — the number the V-series rules revision
moved them to, which every format the app supports is played under, whatever
an old printing's own text says. Critical adds that power and a critical, draw
draws, front spreads it across the front row rather than onto one unit, heal
heals when you are not ahead on damage, stand stands a unit. An over trigger is
its own number, +100000, and the rest of what it does is the card's text. It is
also **removed from the game** as it resolves: from a drive check it does not
join the hand, and from a damage check it is not taken as damage, so a deck
that over-triggers into its sixth damage does not lose to it. What was removed
sits on its own pile in the zone rail, readable but out of play for good. Both
players draw on their own first turn; nobody skips it. Nobody attacks on turn
one either: whoever goes first is a turn ahead on the board, so they do not
swing, and the control bar says so rather than leaving a tap unanswered.

### Lock

A locked card is turned face down on its circle, and the board treats it as
what it is: **not a unit**. It cannot attack, boost, be attacked or be chosen,
a front trigger passes it by, it does not move or swap up its column, and
nothing can be called over it — the circle is held shut, which is the whole
point of locking one.

Lock is on any rear-guard's sheet, on your board and the CPU's, since the card
being locked is usually the opponent's. It shows face down on the circle, art
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
why rather than leaving a tap unanswered. The CPU plays by the same rule, and
now fills its back row with units that can actually push — being able to boost
comes before power there.

Plenty of cards hand the keyword out all the same — *"this unit gets 'Boost'
until end of turn"* — so any grade 2 or greater rear-guard's sheet offers
**Give [Boost]**, on your board and the CPU's. A unit carrying it is marked
**⇧** beside its power and boosts like any grade 1 until the end of the turn,
when it wears off with everything else a turn hands out. **Take [Boost] back**
undoes it. Where the card's text is one the reader follows, the CPU gives
itself the keyword without being asked.

### What the CPU can read

A CPU that ignored every ability played a deck of vanilla bodies, which is not
what a deck does. So the board reads the printed English of the shapes that are
unambiguous, and refuses the rest:

```
[AUTO](VC):When this unit attacks a vanguard, this unit gets [Power]+5000
                                              until end of that battle.   ✓ played
[CONT](RC):During your turn, this unit gets [Power]+3000.                 ✓ played
[AUTO]:When rode upon, draw a card.                                       ✓ played
[AUTO](VC):When placed, [COST][Counter-Blast 1], draw a card.             ✓ played

[AUTO](VC)[Limit-Break 4]:When this unit attacks, this unit gets
                          [Power]+10000/[Critical]+1.                     ✓ played
[AUTO](RC):When this unit attacks, [COST][retire this unit], draw a card. ✓ played
[CONT](VC):If your opponent's vanguard is grade 3 or greater, ...         ✓ played

[AUTO](VC):When this unit attacks, choose one of your rear-guards, and
           it gets [Power]+5000.                                          ✗ refused
[ACT](VC):[COST][Counter-Blast 1], search your deck for a card...         ✗ refused
[AUTO]:When this unit is put on (GC), one of your units cannot be hit.    ✗ refused
```

A clause is played only when **every** part of it — the timing, each item of
the cost, and each effect — is one of the known forms. Half an ability is never
guessed at, so the CPU cannot invent power it does not have.

The reach is still small, and worth stating rather than implying: **849 cards
of the 15,170 that carry ability text**, about one in eighteen. It covers
on-attack and on-boost pumps, continuous bonuses, the draw on being ridden
over, placement abilities, the charges, the **hollow** keyword, a card
discarded to pay for a stride, and the timings a card pays out on rather than
fires on — **when its attack hits**, **at the end of the battle it attacked or
boosted**, **when your G unit strides**, and **at the end of your turn**.

The **costs** it can pay are the ones the board can actually spend: a
counter-blast, a soul-blast, energy, a discard however the card words it, the
top few cards of the deck into the drop, a G zone card turned face up, resting
the unit, and the two that spend the unit itself — retiring it or putting it
into the soul. Two costs written in one bracket (*"[Counter-Blast 1 &
Soul-Blast 1]"*) are both paid. A cost whose number it cannot read is a
refusal, never a free ability.

It also reads the **conditions the board can answer** — a named crest in the
crest zone, a named vanguard of at least a grade, a Generation Break, a Limit
Break, a drop zone or damage zone or hand that deep, how many rear-guards are
standing, the opponent's vanguard's grade, whether the unit is hollowed,
whether its controller went second — and power written as *"+5000 for each
face up card in your G zone"*, which is multiplied rather than added once. A
condition it cannot answer is still a refusal, never an assumption that it
holds.

Two rules keep the widening honest. A clause that retires the unit and then
gives that same unit power is refused rather than half-played, since the unit
is gone by the time the bonus lands. And an ability that hands you a crest —
*"you get a "Nightrose" crest"* — is not played at all unless the library
actually holds that crest, so nothing is paid for a cost that cannot finish.

What it still refuses: anything that chooses a target, searches a deck, calls
a unit, retires somebody else's, or asks the board something it cannot count.

A worked example, and the reason the reader grew: the Stride Deckset
-Nightrose- (`DZ-SS03`). Nothing in it could be played at all — 0 of its 36
clauses — because every card asks a question: is its crest out, is this unit
hollowed, how deep is the drop, how many G zone cards are face up. Teaching
the reader those questions, the **hollow** keyword and the crest's own
*"+5000 for each face up card"* took it to 11 of 36, including the crest that
the whole deck is built on. `tool/ability_coverage.dart` is what measures
that, deck by deck:

```bash
dart run tool/ability_coverage.dart DZ-SS03        # a set
dart run tool/ability_coverage.dart --name Harri   # a card name
```

It prints every clause marked played or not read, then ranks **the phrase
that stopped each unread one** — the reader's own answer, not a guess from
keywords — so the next pattern written is the one that buys the most. That
ranking is what took the reader from 577 cards to 849: the top of it was not
this deck's text at all but the shapes every deck shares, and teaching those
five or six forms lifted every set at once.

Lines that are not an ability it failed to follow are not counted as one: a
reminder in brackets, `[CONT]:Sentinel` — the board plays the perfect guard
off the card type — and the stride cost, which the board's own stride pays.

What it refuses is not swallowed. When the CPU rides or calls a unit whose text
it cannot follow, it says so in the log — "Blaster Blade has 2 abilities the
board cannot play. Read the card if it matters." — so a test that depends on
that card is a test you know to run by hand rather than one that quietly did
not happen. Every hand-applied control works on the CPU's units too, so you can
play its ability for it where the game you are testing turns on it.

Your own abilities stay yours. The reader is deliberately not pointed at your
side of the board: applying a cost you chose is part of playing the deck, and
a program guessing at it would take the test away from you.

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
is a maximum and not a promise. The reader follows that printed wording too,
so the CPU plays to fifteen without being told.

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
same attack. It stays up after the attack resolves, deliberately: the damage
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
  card**, shuffle, or — deliberately, one tap further in — look through the
  whole thing for an ability that searches, which reshuffles afterwards.
  Drawing is the common thing and looking is the rare one, so reading the deck
  is never the price of taking the top card off it.
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

It will not play your cards' abilities, and the CPU plays only the few it can
actually read — which is the reason **You, both sides** exists: play the other
side yourself and every ability on both boards gets played, because you are
the one playing them.

Abilities are English prose in the card database — "[AUTO]:When this unit is
placed on (VC), [COST][Counter-Blast 1], choose one of your opponent's
rear-guards, and retire it" — and there is no encoding of them for a program to
follow. Rather than pretend otherwise, the board runs everything around them and
leaves the abilities to you: tap any unit to read its text and apply what it
says, with controls there for power, critical, drive, standing and resting,
retiring, drawing, energy and damage, and every zone above open for the costs.
Power is typed in rather than picked from a list: cards give 2000 and 4000 as
readily as 5000, so the unit sheet has a field — opening on 5000, the commonest
— with buttons to add or take away exactly that much, and a Clear that puts the
unit back to its printed power. Power, critical and drive all wear off at end
of turn the way the game says they do — a unit carrying more than its one critical, or reduced below it, says
so on the board, and the drive check button names how many checks are coming.

Drive is offered on the vanguard alone, since nothing else drive checks, and
it is cleared each turn like the rest. That is the safer way round for a
continuous drive+1, which has to be re-applied: forgetting to add it shows up
as a missing check, where forgetting to take a temporary one away would
quietly hand out cards. It is a patient
paper opponent, not a rules engine.

That still answers the questions a deck list cannot. Does it ride through grade
3 reliably? Does the mulligan leave a workable hand? Are sixteen triggers enough
to keep up in the damage race? How much shield is left in hand by turn four?

### Watching the CPU play

Its main phase happens one action at a time. It used to run the whole thing on
the tap that ended your turn, which meant looking up from your own board to
find a finished one and no account of how it got there — six cards played, a
ride, and whatever abilities went with them, all in a single frame.

Now the control bar hands over and waits: **Continue** plays the CPU's next
single action and says what it was — the ride, one call, a move up a column,
one ability — so its turn can be read as it happens rather than reconstructed
from the log afterwards. A call and the ability that call sets off are one
action, since that is one decision.

Nothing about what it decides changed, only when you see it: stepping through
to the end leaves exactly the board that playing it out in one go would have,
which is what a test checks.

### How the CPU decides

Everything it does comes from what the engine can see — power, shield,
critical, grade, the damage on each side, the cards in each hand — so its
reasoning can be argued with rather than being buried in a magic number.

- **It only makes attacks that achieve something.** An attack short of its
  target's power is simply waved through, so it is not made. Over a run of
  self-play games the previous version would have thrown 638 such swings; this
  one makes none.
- **It guards by what the trade is worth**, and what that is depends on which
  damage this would be. The first few are not a loss: each is a damage check,
  which is a free look at a trigger, and the counter-blast an ability will
  want later — so it takes them rather than spending a card. By four damage
  the next hit is the one that matters, and it answers. Measured over
  self-play it guards under a third of the answerable attacks while on nought
  to two damage, and over three fifths of them from four.
- **It spends the fewest cards that do the job**, taking the biggest shields
  first. Filling from the smallest up, as it used to, cost 2.19 cards a guard
  against 1.12 now.
- **It keeps the perfect guard** for the hit that would actually end the game,
  rather than spending it on the first big attack.
- **It picks rear-guard targets worth killing** — a real attacker, or the boost
  under one — and otherwise keeps the pressure on the vanguard. A 5000 power
  body is not worth diverting an attack for.
- **It holds cards back**, three or four depending on damage, instead of
  emptying its hand onto the board and then having nothing to guard with.
- **It never calls a grade 0.** A trigger put on a circle is a 5000 power body
  traded for a 15000 shield, and calling them out was most of what made the
  CPU look like it was dumping its hand for nothing: it kept no guard and
  gained almost no board. Over a run of self-play games the previous version
  called 148 of them; this one calls none, and its triggers stay in hand to
  guard with.
- **It moves a stranded rear-guard up** when nothing is in front of it to
  boost, turning a unit that was doing nothing into another attack. It does
  this after calling rather than before, because given a card for that circle
  the better board is the bigger unit in front with this one boosting it.
- **It strides** where the deck has a G zone, paying with the fewest cards and
  never with the perfect guard.
- **It weighs the costs that spend a unit.** Retiring the unit whose ability it
  is, or putting it into the soul, is paid for a card drawn or a crest gained
  and refused for power on somebody else — the body lost is worth more than
  that. Milling is refused outright when the deck is thin enough that decking
  out is the likelier end.

The same policy can be pointed at both seats, so it plays itself and the
results are measured rather than assumed: every game finishes, none stalls, and
the numbers above come out of that run.

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
  playtest/
    playtest_state.dart          the board: sides, circles, units, the attack
    playtest_engine.dart         the rules, and everything they can adjudicate
    ability_reader.dart          the printed abilities it can and cannot read
    playtest_ai.dart             the CPU's decisions, ability play included
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
  playtest_abilities_test.dart   the CPU actually playing them
  playtest_ai_test.dart          the CPU's decisions, measured in self-play
  playtest_flow_test.dart        the board, driven end to end
  playtest_layout_test.dart      the board at four screen sizes
  settings_screen_test.dart      the build it says it is
```

## Adding iOS

The project is Android only right now, since the goal was an APK. Adding iOS is
one command on a Mac — `flutter create --platforms ios .` — and no Dart code
changes, because nothing in the app is Android specific.
