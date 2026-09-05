import 'dart:math';

import '../games/game_definition.dart';
import '../games/vanguard/vanguard_data.dart';
import '../models/card_definition.dart';
import '../models/deck.dart';
import '../store/deck_store.dart';
import 'ability_reader.dart';
import 'playtest_state.dart';

/// The rules of a game of Vanguard, as far as they can be played without
/// understanding what any individual card does.
///
/// The structure is all here and is enforced: riding in grade order, who may
/// attack whom, how many drive checks a vanguard makes, what each trigger is
/// worth, whether an attack got through, when the sixth damage ends it. What
/// is deliberately absent is card abilities. They are English prose in the
/// card database -- "[AUTO]:When this unit is placed on (VC), [COST][Counter-
/// Blast 1], choose one of your opponent's rear-guards, and retire it" -- and
/// nothing here can execute that. So the engine runs the game around them and
/// the player reads the text and applies it by hand, which is also how a
/// paper playtest against a patient opponent goes.
class PlaytestEngine {
  PlaytestEngine(this.state, {Random? random}) : _random = random ?? Random();

  final PlaytestState state;
  final Random _random;

  /// Every card ever dealt gets a number, so two copies of one card are
  /// separate pieces on the board.
  static int _nextInstanceId = 1;

  /// What a trigger gives the unit it is placed on.
  ///
  /// Ten thousand, not the five thousand the game started with: the V-series
  /// rules revision doubled it, and every format the app supports -- Standard,
  /// V Premium and Premium -- is played under those rules, whatever an old
  /// card's own printed text says.
  static const int triggerPower = 10000;

  /// What an over trigger gives, which is its own number and always was.
  static const int overTriggerPower = 100000;

  // ---------------------------------------------------------------- setting up

  /// Builds a game from two decks in the library.
  ///
  /// [yourDeck] and [opponentDeck] may be the same deck: a mirror match is the
  /// usual way to find out whether a deck simply works.
  static PlaytestEngine start({
    required DeckStore store,
    required Deck yourDeck,
    required Deck opponentDeck,
    TurnOrder turnOrder = TurnOrder.youFirst,
    Random? random,
  }) {
    final rng = random ?? Random();
    final state = PlaytestState(
      you: PlaytestSide(name: 'You', isCpu: false),
      opponent: PlaytestSide(name: 'CPU', isCpu: true),
    );
    final engine = PlaytestEngine(state, random: rng);

    engine._deal(state.you, store.viewOf(yourDeck).items);
    engine._deal(state.opponent, store.viewOf(opponentDeck).items);

    // Who goes first, which the crest's energy rule cares about: the player
    // going second is paid three to make up for it.
    final youFirst = switch (turnOrder) {
      TurnOrder.youFirst => true,
      TurnOrder.cpuFirst => false,
      TurnOrder.random => rng.nextBool(),
    };
    state.you.goesFirst = youFirst;
    state.opponent.goesFirst = !youFirst;

    // The first vanguard is the ride deck's grade 0, and it starts on the
    // field rather than in the ride deck.
    engine._standUpFirstVanguard(state.you);
    engine._standUpFirstVanguard(state.opponent);

    for (var i = 0; i < 5; i += 1) {
      engine._draw(state.you);
      engine._draw(state.opponent);
    }

    // The CPU decides its opening at once; yours waits for you.
    engine._cpuMulligan(state.opponent);

    state.note(
      youFirst
          ? 'You go first, so you charge no energy on turn one.'
          : 'The CPU goes first. You are paid three energy for going second.',
    );
    state.note('Game on. Choose which cards to put back.');
    return engine;
  }

  void _deal(PlaytestSide side, List<DeckItem> items) {
    for (final item in items) {
      for (var i = 0; i < item.entry.quantity; i += 1) {
        final card = GameCard(_nextInstanceId++, item.card);
        switch (item.entry.zoneId) {
          case zoneRide:
            side.rideDeck.add(card);
          case zoneG:
            // The G zone sits beside the board rather than in the deck: it is
            // strided from, never drawn, and shuffling it in would corrupt
            // every draw.
            side.gZone.add(card);
          default:
            side.deck.add(card);
        }
      }
    }
    side.deck.shuffle(_random);
    side.rideDeck.sort((a, b) => a.grade.compareTo(b.grade));
  }

  void _standUpFirstVanguard(PlaytestSide side) {
    final crestIndex = side.rideDeck.indexWhere(
      (c) => c.cardType == 'ride-deck-crest',
    );
    if (crestIndex >= 0) side.rideCrest = side.rideDeck.removeAt(crestIndex);

    final firstIndex = side.rideDeck.indexWhere((c) => c.grade == 0);
    if (firstIndex < 0) return;
    final first = side.rideDeck.removeAt(firstIndex);
    side.field[Circle.vanguard] = FieldUnit(first);
  }

  // ------------------------------------------------------------------ mulligan

  /// Puts [chosen] back, shuffles, and draws that many again.
  void mulligan(PlaytestSide side, List<GameCard> chosen) {
    for (final card in chosen) {
      side.hand.remove(card);
      side.deck.add(card);
    }
    side.deck.shuffle(_random);
    for (var i = 0; i < chosen.length; i += 1) {
      _draw(side);
    }
    if (chosen.isEmpty) {
      state.note('${side.name} kept the opening hand.', by: side);
    } else {
      state.note('${side.name} put ${chosen.length} back.', by: side);
    }
  }

  /// The CPU keeps its grade curve and pitches the rest.
  void _cpuMulligan(PlaytestSide side) {
    // A hand wants a grade 1 and a grade 2 to ride into; triggers and
    // anything grade 3 or higher can wait.
    final keep = <GameCard>[];
    final back = <GameCard>[];
    var ones = 0;
    var twos = 0;
    for (final card in side.hand) {
      final wanted = switch (card.grade) {
        1 => ones++ < 2,
        2 => twos++ < 2,
        0 => card.trigger != null,
        _ => false,
      };
      (wanted ? keep : back).add(card);
    }
    mulligan(side, back);
  }

  /// Called once you have taken your own mulligan, to begin turn one.
  void beginPlay() {
    state.phase = PlaytestPhase.stand;
    state.turn = 0;
    state.yourTurn = state.you.goesFirst;
    _beginTurn();
  }

  // --------------------------------------------------------------------- turns

  void _beginTurn() {
    state.turn += 1;
    state.ridden = false;
    final side = state.active;

    for (final unit in side.units) {
      unit.rested = false;
    }
    state.phase = PlaytestPhase.draw;
    state.note('--- Turn ${state.turn}: ${side.name} ---', by: side);

    // Both players draw on every turn of their own, the first turn included.
    // There is no skipped draw for whoever goes first.
    _draw(side);
    if (_checkForEnd()) return;
    state.phase = PlaytestPhase.ride;

    // "[AUTO]:At the beginning of your ride phase, [Energy-Charge 3]." Only
    // once the crest is in the crest zone, which it is not on turn one --
    // it arrives during the ride, after this moment has passed. That is why
    // whoever goes first starts a turn behind on energy.
    if (side.crestInPlay) {
      _chargeEnergy(side, crestCharge(side));
    }
  }

  /// Puts a crest into the crest zone by hand.
  ///
  /// A Divinez deck brings its crest in its ride deck and the first ride puts
  /// it there on its own. Every other deck brings none -- a stride deck least
  /// of all -- so a playtest that wants one has to say which, and this is
  /// where it says it. What happens afterwards is the same either way: the
  /// crest charges on its own from the next ride phase, and pays the three
  /// its text owes whoever went second, since that is what the card says.
  void playCrest(PlaytestSide side, CardDefinition card) {
    _enterCrestZone(side, GameCard(_nextInstanceId++, card));
  }

  /// Takes the crest back out of the crest zone.
  ///
  /// The energy it charged stays: it was spent or it was not, and taking the
  /// card away does not unspend it.
  void removeCrest(PlaytestSide side, GameCard crest) {
    if (!side.crestZone.remove(crest)) return;
    state.note(
      '${side.name} takes ${crest.name} out of the crest zone.',
      by: side,
    );
  }

  /// How much energy this side's crest charges each turn.
  ///
  /// Read off the crest where its text says, so a crest printing a different
  /// number is followed rather than overruled. Three is the Energy Generator's
  /// number and the default for a crest whose text the database never carried.
  int crestCharge(PlaytestSide side) =>
      side.crestZone.fold(0, (sum, crest) => sum + chargeOf(crest));

  /// What one crest charges every ride phase, off its own text.
  ///
  /// A crest whose text says nothing about energy charges none: a stride
  /// deck's crest is permission to stride, not an energy engine. The three is
  /// only for a crest with no text at all, which is the Energy Generator as
  /// the database once carried it -- blank, and charging three in every game
  /// that has ever been played with it.
  int chargeOf(GameCard crest) {
    final match = RegExp(
      r'Energy-Charge\s+(\d+)',
      caseSensitive: false,
    ).firstMatch(crest.effect);
    final printed = int.tryParse(match?.group(1) ?? '');
    if (printed != null) return printed;
    return crest.effect.trim().isEmpty ? 3 : 0;
  }

  /// Adds energy, up to the ten the crest allows.
  void _chargeEnergy(PlaytestSide side, int amount) {
    if (amount <= 0) return;
    final before = side.energy;
    side.energy = (side.energy + amount).clamp(0, PlaytestSide.energyCap);
    final gained = side.energy - before;
    state.note(
      gained == amount
          ? '${side.name} energy-charges $amount (${side.energy}).'
          : '${side.name} energy-charges $gained to the cap of '
                '${PlaytestSide.energyCap}.',
      by: side,
    );
  }

  /// Moves the game on to whatever comes after [state.phase].
  void advancePhase() {
    switch (state.phase) {
      case PlaytestPhase.ride:
        state.phase = PlaytestPhase.main;
      case PlaytestPhase.main:
        state.phase = PlaytestPhase.battle;
      case PlaytestPhase.battle:
        state.phase = PlaytestPhase.end;
      case PlaytestPhase.end:
        endTurn();
      default:
        break;
    }
  }

  void endTurn() {
    final side = state.active;
    // A hollowed unit was borrowed for the turn, and the turn is over.
    for (final entry in side.occupied.toList()) {
      if (entry.value.hollowed) {
        state.note(
          '${side.name}: ${entry.value.card.name} was hollowed, '
          'and is retired.',
          by: side,
        );
        retire(side, entry.key);
      }
    }
    // A stride lasts one turn, so the G unit goes back before anything else.
    endStride(side);
    // Locked cards come back face up at the end of their owner's turn, which
    // is the turn after the one they were locked on: a lock costs the player
    // their use of that unit for exactly one turn of their own.
    unlockAll(side);
    for (final unit in side.units) {
      unit.clearTurnEffects();
    }
    for (final unit in state.inactive.units) {
      unit.clearTurnEffects();
    }
    state.attack = null;
    state.yourTurn = !state.yourTurn;
    _beginTurn();
  }

  bool _checkForEnd() {
    final winner = state.winner;
    if (winner == null) return false;
    state.phase = PlaytestPhase.over;
    state.note('${winner.name} wins.');
    return true;
  }

  // --------------------------------------------------------------------- cards

  GameCard? _draw(PlaytestSide side) {
    if (side.deck.isEmpty) return null;
    final card = side.deck.removeLast();
    side.hand.add(card);
    return card;
  }

  /// Draws for the player, as an ability that says to.
  void drawCard(PlaytestSide side) {
    final card = _draw(side);
    state.note(
      card == null
          ? '${side.name} has nothing left to draw.'
          : '${side.name} draws a card.',
      by: side,
    );
    _checkForEnd();
  }

  // ---------------------------------------------------------------------- ride

  /// Which ride deck card may be ridden right now.
  ///
  /// The ride deck is climbed a grade at a time, so this is the one card whose
  /// grade is exactly one above the vanguard's.
  GameCard? rideDeckOption(PlaytestSide side) {
    final current = side.vanguard?.card.grade ?? -1;
    for (final card in side.rideDeck) {
      if (card.grade == current + 1) return card;
    }
    return null;
  }

  /// Cards in hand that may be ridden: the same grade as the vanguard, or one
  /// above it.
  List<GameCard> handRideOptions(PlaytestSide side) {
    final current = side.vanguard?.card.grade ?? -1;
    return side.hand
        .where(
          (c) => c.isUnit && (c.grade == current || c.grade == current + 1),
        )
        .toList();
  }

  /// Whether the ride deck's next grade can actually be ridden.
  ///
  /// It costs a card out of hand, so an empty hand cannot pay for it however
  /// much the ride deck is holding.
  bool canRideFromDeck(PlaytestSide side) =>
      rideDeckOption(side) != null && side.hand.isNotEmpty;

  bool canRide(PlaytestSide side) =>
      !state.ridden &&
      state.phase == PlaytestPhase.ride &&
      (canRideFromDeck(side) || handRideOptions(side).isNotEmpty);

  /// The card the hand would rather lose to pay for a ride: the worst guard,
  /// and never the perfect guard.
  ///
  /// Only a suggestion. Which card to discard is a real decision, so the
  /// board asks; this is what it opens on, and what the CPU takes.
  GameCard? rideCostSuggestion(PlaytestSide side) {
    final spare = side.hand.where((c) => !c.isSentinel).toList()
      ..sort((a, b) => a.shield.compareTo(b.shield));
    return spare.isNotEmpty ? spare.first : side.hand.firstOrNull;
  }

  /// Rides [card], from the ride deck or from hand. The unit it replaces goes
  /// to the soul, as a ridden-over vanguard always does.
  /// Rides [card], from the ride deck or out of hand.
  ///
  /// A ride out of the ride deck costs a card discarded from hand, which is
  /// what a ride deck is paid for with. [discard] names the card to pay with;
  /// left out, the hand's worst guard pays, and either way the log says which
  /// card it was. With nothing in hand the ride cannot be paid for and does
  /// not happen.
  ///
  /// Riding out of hand costs nothing but the card itself.
  void ride(
    PlaytestSide side,
    GameCard card, {
    required bool fromRideDeck,
    GameCard? discard,
  }) {
    var paid = '';
    if (fromRideDeck) {
      final cost = discard ?? rideCostSuggestion(side);
      if (cost == null || !side.hand.remove(cost)) return;
      side.drop.add(cost);
      paid = ', discarding ${cost.name}';
      side.rideDeck.remove(card);
    } else {
      side.hand.remove(card);
    }
    final previous = side.vanguard;
    if (previous != null) side.soul.add(previous.card);
    side.field[Circle.vanguard] = FieldUnit(card);
    state.ridden = true;
    state.note(
      '${side.name} rides ${card.name} '
      '(grade ${card.grade})${fromRideDeck ? ' from the ride deck' : ''}$paid.',
      by: side,
    );
    _placeCrest(side);
  }

  /// "[AUTO]Ride Deck:When you ride, put this card into the crest zone, and
  /// if you went second, [Energy-Charge 3]."
  ///
  /// The three paid here is what makes up for going second: the player who
  /// went first has already passed the beginning of their ride phase with no
  /// crest in play, so they charge nothing on turn one.
  void _placeCrest(PlaytestSide side) {
    final crest = side.rideCrest;
    if (crest == null) return;
    side.rideCrest = null;
    _enterCrestZone(side, crest);
  }

  /// Puts one crest into the crest zone, however it got there.
  ///
  /// Whatever is already in the zone stays: a deck can hold the Energy
  /// Generator and a stride deck's crest at the same time, and playing the
  /// second must not cost the first.
  void _enterCrestZone(PlaytestSide side, GameCard crest) {
    side.crestZone.add(crest);
    state.note(
      '${side.name} puts ${crest.name} into the crest zone.',
      by: side,
    );
    // "and if you went second, [Energy-Charge 3]" -- the crest's own clause,
    // paid by the crest arriving rather than by the turn.
    if (!side.goesFirst) {
      _chargeEnergy(side, chargeOf(crest));
    }
  }

  // -------------------------------------------------------------------- stride

  /// Whether this side could stride right now.
  ///
  /// Stride is a Premium-era move: with a grade 3 vanguard you put a G unit on
  /// top of it for the turn, paying by discarding cards worth grade 3 or more
  /// between them.
  /// Whether a stride is legal right now.
  ///
  /// Striding again on top of a stride is legal and happens: the G unit
  /// standing there goes back to the G zone face up and the new one takes its
  /// place over the same heart. So being mid-stride is not a reason to
  /// refuse -- the grade of the unit underneath is what matters, and that is
  /// the heart while a stride is up.
  bool canStride(PlaytestSide side) =>
      side.gZone.isNotEmpty &&
      ((side.heart ?? side.vanguard)?.card.grade ?? 0) >= 3 &&
      strideCostAvailable(side);

  /// Whether the hand holds enough grades to pay for a stride.
  bool strideCostAvailable(PlaytestSide side) =>
      side.hand.fold(0, (sum, card) => sum + card.grade) >= 3;

  /// Whether [cost] is a legal stride cost: grade 3 or more between them.
  bool isStrideCost(List<GameCard> cost) =>
      cost.fold(0, (sum, card) => sum + card.grade) >= 3;

  /// Strides [card] over the vanguard, discarding [cost] to pay for it.
  ///
  /// The unit underneath stays put as the heart and comes back when the turn
  /// ends -- a stride is for one turn only.
  void stride(PlaytestSide side, GameCard card, List<GameCard> cost) {
    // Mid-stride the heart is the real vanguard; the unit on the circle is
    // the G unit already standing there, which this stride replaces.
    final heart = side.heart ?? side.vanguard;
    if (heart == null || !isStrideCost(cost)) return;
    if (!side.gZone.contains(card)) return;

    for (final paid in cost) {
      side.hand.remove(paid);
      side.drop.add(paid);
      // "When this card is discarded from hand while paying the cost for
      // [Stride]" -- the cost itself is a timing.
      for (final ability in abilitiesOf(paid).playable) {
        if (ability.timing == AbilityTiming.onDiscardedForStride) {
          playCardAbility(side, paid, ability);
        }
      }
    }

    // A G unit that was already strided goes back where it came from, face
    // up: that is where the face-up G zone a Generation Break counts comes
    // from in the first place.
    final standing = side.field[Circle.vanguard];
    if (side.isStriding && standing != null) {
      side.gZone.add(standing.card);
      side.faceUpG.add(standing.card.instanceId);
    }

    side.gZone.remove(card);
    side.faceUpG.remove(card.instanceId);
    side.heart = heart;
    side.field[Circle.vanguard] = FieldUnit(card);
    state.note(
      '${side.name} strides ${card.name} over ${heart.card.name}, '
      'discarding ${cost.length} to pay for it.',
      by: side,
    );
  }

  /// Turns a G zone card face up, for the abilities that ask for one, and
  /// face down again for the ones that put it back.
  void flipG(PlaytestSide side, GameCard card, {required bool faceUp}) {
    if (!side.gZone.contains(card)) return;
    final changed = faceUp
        ? side.faceUpG.add(card.instanceId)
        : side.faceUpG.remove(card.instanceId);
    if (!changed) return;
    state.note(
      '${side.name} turns ${card.name} '
      '${faceUp ? 'face up' : 'face down'} in the G zone '
      '(${side.generationBreak} face up).',
      by: side,
    );
  }

  /// Ends a stride, putting the G unit back and the heart back on top.
  void endStride(PlaytestSide side) {
    final heart = side.heart;
    if (heart == null) return;
    final strider = side.field[Circle.vanguard];
    if (strider != null) {
      // Back to the G zone face up, which is what makes a Generation Break
      // turn on after the first stride.
      side.gZone.add(strider.card);
      side.faceUpG.add(strider.card.instanceId);
    }
    side.field[Circle.vanguard] = heart;
    side.heart = null;
    state.note('${side.name}\'s stride ends.', by: side);
  }

  // ----------------------------------------------------------------- the zones

  /// Turns face-up damage face down to pay a counter-blast.
  void counterBlast(PlaytestSide side, int count) {
    var paid = 0;
    for (final card in side.damage) {
      if (paid >= count) break;
      if (side.spentDamage.add(card.instanceId)) paid += 1;
    }
    if (paid > 0) {
      state.note('${side.name} counter-blasts $paid.', by: side);
    }
  }

  /// Turns spent damage back face up.
  void counterCharge(PlaytestSide side, int count) {
    var charged = 0;
    for (final card in side.damage.reversed) {
      if (charged >= count) break;
      if (side.spentDamage.remove(card.instanceId)) charged += 1;
    }
    if (charged > 0) {
      state.note('${side.name} counter-charges $charged.', by: side);
    }
  }

  /// Moves a card out of the soul and into the drop, for a soul-blast.
  void soulBlast(PlaytestSide side, GameCard card) {
    if (!side.soul.remove(card)) return;
    side.drop.add(card);
    state.note('${side.name} soul-blasts ${card.name}.', by: side);
  }

  /// Puts the top of the deck into the soul, for a soul-charge.
  void soulCharge(PlaytestSide side, int count) {
    for (var i = 0; i < count; i += 1) {
      if (side.deck.isEmpty) break;
      side.soul.add(side.deck.removeLast());
    }
    state.note('${side.name} soul-charges $count.', by: side);
    _checkForEnd();
  }

  /// Takes a named card out of the deck, for an ability that searches.
  ///
  /// The deck is shuffled afterwards, as searching it always requires.
  void searchDeck(PlaytestSide side, GameCard card, {bool toHand = true}) {
    if (!side.deck.remove(card)) return;
    (toHand ? side.hand : side.drop).add(card);
    side.deck.shuffle(_random);
    state.note(
      '${side.name} searches out ${card.name} '
      '${toHand ? 'to hand' : 'to the drop zone'}.',
      by: side,
    );
  }

  void shuffleDeck(PlaytestSide side) {
    side.deck.shuffle(_random);
    state.note('${side.name} shuffles.', by: side);
  }

  /// Returns a card from the drop zone to the hand.
  void returnFromDrop(PlaytestSide side, GameCard card) {
    if (!side.drop.remove(card)) return;
    side.hand.add(card);
    state.note('${side.name} takes ${card.name} back from the drop.', by: side);
  }

  /// Puts a card on the bottom of the deck, from wherever it is now.
  ///
  /// Costs ask for this from the hand most often -- "put a card from your
  /// hand on the bottom of your deck" -- but the drop zone and the soul are
  /// asked for it too, so the card comes out of whichever holds it.
  void bottomDeck(PlaytestSide side, GameCard card) {
    final from = _takeFrom(side, card);
    if (from == null) return;
    side.deck.insert(0, card);
    state.note(
      '${side.name} puts ${card.name} under the deck'
      '${from == 'hand' ? '' : ' from the $from'}.',
      by: side,
    );
  }

  /// Puts a unit on the field on the bottom of the deck.
  ///
  /// The other half of the same cost: plenty of cards pay by putting a
  /// rear-guard, or themselves, back into the deck rather than retiring it,
  /// which is a different place for it to end up and worth keeping straight.
  void bottomDeckUnit(PlaytestSide side, Circle circle) {
    final unit = side.field.remove(circle);
    if (unit == null) return;
    side.deck.insert(0, unit.card);
    state.note('${side.name} puts ${unit.card.name} under the deck.', by: side);
  }

  // ---------------------------------------------------------------------- call

  /// Whether [card] may be called to [circle].
  ///
  /// A unit cannot be called above the vanguard's grade, which is what stops a
  /// grade 3 hitting the field on turn one.
  bool canCall(PlaytestSide side, GameCard card, Circle circle) {
    if (circle == Circle.vanguard || !card.isUnit) return false;
    // A locked card holds its circle: it is face down, not a unit that can be
    // retired to make room.
    if (side.field[circle]?.locked ?? false) return false;
    // A G unit is strided, never called: it lives in the G zone and only ever
    // reaches the field on top of the vanguard.
    if (card.cardType == 'g-unit') return false;
    final vanguardGrade = side.vanguard?.card.grade ?? 0;
    return card.grade <= vanguardGrade;
  }

  /// Calls [card] to [circle], from wherever it currently is.
  ///
  /// Most calls come out of hand, but plenty of abilities call from the deck,
  /// the drop zone or the soul, so the card is taken from whichever zone
  /// holds it rather than from hand alone. A call out of the deck shuffles
  /// it afterwards, the way looking through it always does.
  ///
  /// A unit already on the circle is retired to make room.
  void call(PlaytestSide side, GameCard card, Circle circle) {
    // Checked before the card is taken out of wherever it is: a call that
    // cannot happen must not cost the card it was going to be made with.
    final existing = side.field[circle];
    if (existing != null && existing.locked) return;

    final from = _takeFrom(side, card, deck: true);
    if (from == null) return;

    if (existing != null) {
      side.drop.add(existing.card);
      state.note(
        '${side.name} moves ${existing.card.name} to the drop zone.',
        by: side,
      );
    }
    side.field[circle] = FieldUnit(card);
    state.note(
      '${side.name} calls ${card.name} to ${circle.label}'
      '${from == 'hand' ? '' : ' from the $from'}.',
      by: side,
    );
    if (from == 'deck') side.deck.shuffle(_random);
  }

  /// Takes [card] out of the zone holding it, naming that zone. Null when the
  /// card is in none of them.
  ///
  /// The deck is only searched where the caller says so: a call may come out
  /// of it, but a card being put under the deck never comes from the deck.
  String? _takeFrom(PlaytestSide side, GameCard card, {bool deck = false}) {
    if (side.hand.remove(card)) return 'hand';
    if (deck && side.deck.remove(card)) return 'deck';
    if (side.drop.remove(card)) return 'drop zone';
    if (side.soul.remove(card)) return 'soul';
    return null;
  }

  /// The circle a rear-guard may move to: the other row of its own column.
  ///
  /// Only the left and right columns can do this. The middle column's front
  /// circle is the vanguard's, and nothing moves onto that, so a unit in the
  /// back centre has nowhere to go.
  Circle? moveTargetOf(Circle circle) => switch (circle) {
    Circle.frontLeft => Circle.backLeft,
    Circle.backLeft => Circle.frontLeft,
    Circle.frontRight => Circle.backRight,
    Circle.backRight => Circle.frontRight,
    _ => null,
  };

  /// Whether the unit on [circle] can move right now.
  ///
  /// Moving is a main phase action, so it cannot be used to shuffle the board
  /// around mid-battle after seeing what an attack ran into.
  bool canMove(PlaytestSide side, Circle circle) {
    if (state.phase != PlaytestPhase.main) return false;
    final unit = side.field[circle];
    if (unit == null || unit.locked) return false;
    final to = moveTargetOf(circle);
    if (to == null) return false;
    // Nor can it swap with a locked card, which does not move either.
    return !(side.field[to]?.locked ?? false);
  }

  /// Moves a rear-guard between the rows of its column, swapping with
  /// whatever is already there.
  ///
  /// The units keep everything about themselves -- a rested unit stays
  /// rested, and the power an ability gave it travels with it. Only where
  /// they stand changes, which is the point: a booster moves up to attack, or
  /// an attacker drops back to boost.
  void moveUnit(PlaytestSide side, Circle from) {
    if (!canMove(side, from)) return;
    final to = moveTargetOf(from);
    if (to == null) return;

    final moving = side.field[from];
    if (moving == null) return;
    final displaced = side.field[to];

    side.field[to] = moving;
    if (displaced == null) {
      side.field.remove(from);
      state.note(
        '${side.name} moves ${moving.card.name} to ${to.label}.',
        by: side,
      );
    } else {
      side.field[from] = displaced;
      state.note(
        '${side.name} swaps ${moving.card.name} and '
        '${displaced.card.name} between ${from.label} and ${to.label}.',
        by: side,
      );
    }
  }

  /// Locks a card: turns it face down on its circle.
  ///
  /// A locked card is not a unit. It cannot attack, boost, be attacked or be
  /// chosen for anything, and nothing can be called over it -- it simply
  /// holds the circle shut, which is the whole point of locking one.
  ///
  /// The vanguard is never locked, so only rear-guards are offered it.
  void lock(PlaytestSide side, Circle circle) {
    if (circle == Circle.vanguard) return;
    final unit = side.field[circle];
    if (unit == null || unit.locked) return;
    unit.locked = true;
    state.note('${side.name} locks ${unit.card.name}.', by: side);
  }

  /// Turns a locked card face up again, for the effect that unlocks early.
  ///
  /// The rule unlocks it on its own at the end of its owner's turn; this is
  /// for the cards that say otherwise.
  void unlock(PlaytestSide side, Circle circle) {
    final unit = side.field[circle];
    if (unit == null || !unit.locked) return;
    unit.locked = false;
    state.note('${side.name} unlocks ${unit.card.name}.', by: side);
  }

  /// Unlocks everything this side has face down.
  ///
  /// The end of its owner's turn does this by the rules; an ability that
  /// unlocks the board calls it directly.
  void unlockAll(PlaytestSide side) {
    for (final entry in side.occupied.toList()) {
      if (entry.value.locked) unlock(side, entry.key);
    }
  }

  /// Sends a unit on the field to the drop zone, as a retire cost or an
  /// opponent's ability says to.
  void retire(PlaytestSide side, Circle circle) {
    final unit = side.field.remove(circle);
    if (unit == null) return;
    side.drop.add(unit.card);
    state.note('${side.name} retires ${unit.card.name}.', by: side);
  }

  /// Plays an order: it does its work as text and goes straight to the drop.
  void playOrder(PlaytestSide side, GameCard card) {
    side.hand.remove(card);
    side.drop.add(card);
    state.note('${side.name} plays ${card.name}.', by: side);
  }

  /// Discards from hand, for a cost the card's text asks for.
  void discard(PlaytestSide side, GameCard card) {
    side.hand.remove(card);
    side.drop.add(card);
    state.note('${side.name} discards ${card.name}.', by: side);
  }

  // -------------------------------------------------------------------- attack

  /// The units that could attack right now: standing, and in the front row.
  /// The back row boosts rather than attacks.
  /// Whether this side may attack at all this turn.
  ///
  /// Whoever goes first does not attack on their first turn: they are a turn
  /// ahead on the board and would be swinging into a vanguard that has had no
  /// turn to answer with. It is the oldest balancing rule in the game.
  bool canAttack(PlaytestSide side) => !(state.turn == 1 && side.goesFirst);

  List<Circle> attackers(PlaytestSide side) => [
    if (canAttack(side))
      for (final entry in side.field.entries)
        if (entry.key.isFrontRow && !entry.value.rested && entry.value.isActive)
          entry.key,
  ];

  /// What an attack may be aimed at: the vanguard, or a rear-guard standing in
  /// the front row. A unit in the back row cannot be reached.
  List<Circle> targets(PlaytestSide side) => [
    for (final entry in side.field.entries)
      if (entry.key.isFrontRow && entry.value.isActive) entry.key,
  ];

  /// Declares an attack, resting the attacker and any booster behind it.
  PendingAttack declareAttack({
    required Circle from,
    required Circle to,
    bool boost = false,
  }) {
    final side = state.active;
    final foe = state.inactive;
    final attacker = side.field[from]!;
    final target = foe.field[to]!;

    FieldUnit? booster;
    final boosterCircle = from.boostedBy;
    if (boost && boosterCircle != null) {
      final candidate = side.field[boosterCircle];
      if (candidate != null && !candidate.rested && candidate.isActive) {
        booster = candidate;
        candidate.rested = true;
      }
    }
    attacker.rested = true;

    final pending = PendingAttack(
      attacker: attacker,
      attackerCircle: from,
      target: target,
      targetCircle: to,
      booster: booster,
    );
    state.attack = pending;
    // A new battle, so the last one's checks come off the trigger zone.
    state.triggerZone.clear();
    state.note(
      '${side.name} attacks ${target.card.name} with ${attacker.card.name}'
      '${booster == null ? '' : ' boosted by ${booster.card.name}'} '
      '(${pending.attackPower} power).',
      by: side,
    );
    return pending;
  }

  /// Cards the defender could call to guard: they need a shield, or to be a
  /// sentinel.
  List<GameCard> guardOptions(PlaytestSide side) =>
      side.hand.where((c) => c.canGuard).toList();

  void addGuardian(GameCard card) {
    final pending = state.attack;
    if (pending == null) return;
    final defender = state.inactive;
    defender.hand.remove(card);
    pending.guardians.add(card);
    if (card.isSentinel) {
      pending.perfectGuarded = true;
      state.note(
        '${defender.name} guards perfectly with ${card.name}.',
        by: defender,
      );
    } else {
      state.note(
        '${defender.name} guards with ${card.name} (+${card.shield} shield).',
        by: defender,
      );
    }
  }

  /// Runs the drive check, which only a vanguard's attack gets.
  ///
  /// A grade 3 vanguard twin drives and a grade 4 triple drives; everything
  /// below checks once.
  int driveCount(FieldUnit vanguard) {
    final base = switch (vanguard.card.grade) {
      >= 4 => 3,
      3 => 2,
      _ => 1,
    };
    // An ability can add to that, or take it away. Nought is a real answer:
    // a card that stops the vanguard drive checking exists.
    return (base + vanguard.driveBonus).clamp(0, 9);
  }

  /// Flips the drive checks into hand, returning what came off the top so the
  /// screen can show it.
  List<GameCard> driveCheck() {
    final pending = state.attack;
    final side = state.active;
    if (pending == null || !pending.isVanguardAttack) return const [];

    final flipped = <GameCard>[];
    for (var i = 0; i < driveCount(pending.attacker); i += 1) {
      if (side.deck.isEmpty) break;
      final card = side.deck.removeLast();
      // An over trigger is removed from the game as it resolves: it does not
      // reach the hand the rest of a drive check does.
      final over = card.trigger == 'over';
      if (over) {
        side.removed.add(card);
      } else {
        side.hand.add(card);
      }
      flipped.add(card);
      state.triggerZone.add(CheckedCard(card, CheckKind.drive, side.name));
      state.note(
        '${side.name} drive checks ${card.name}'
        '${over ? ', which is removed from the game' : ''}.',
        by: side,
      );
      _applyTrigger(side, card, pending.attacker);
    }
    // Recorded even when nothing was flipped, since a vanguard on no drive
    // has still done its checking and the attack is ready to resolve.
    pending.driveChecked = true;
    _checkForEnd();
    return flipped;
  }

  /// Resolves the attack: a hit on a vanguard is damage, a hit on a rear-guard
  /// retires it.
  void resolveAttack() {
    final pending = state.attack;
    if (pending == null) return;
    final side = state.active;
    final foe = state.inactive;

    for (final card in pending.guardians) {
      foe.drop.add(card);
    }

    if (!pending.connects) {
      state.note(
        'The attack is stopped '
        '(${pending.attackPower} against ${pending.defence}).',
        by: side,
      );
      state.attack = null;
      _endOfBattle();
      return;
    }

    if (pending.hitsVanguard) {
      final hits = pending.attacker.critical;
      state.note(
        '${pending.target.card.name} is hit for $hits damage.',
        by: side,
      );
      for (var i = 0; i < hits; i += 1) {
        _damageCheck(foe);
        if (foe.isDefeated) break;
      }
    } else {
      foe.field.remove(pending.targetCircle);
      foe.drop.add(pending.target.card);
      state.note('${pending.target.card.name} is retired.', by: side);
    }

    state.attack = null;
    _endOfBattle();
    _checkForEnd();
  }

  /// Clears what an ability gave "until end of that battle", which is a
  /// shorter life than the end of turn everything else wears off at.
  void _endOfBattle() {
    for (final unit in [...state.you.units, ...state.opponent.units]) {
      unit.clearBattleEffects();
    }
  }

  void _damageCheck(PlaytestSide side) {
    if (side.deck.isEmpty) {
      state.note('${side.name} has no cards left to check.', by: side);
      return;
    }
    final card = side.deck.removeLast();
    // The same for a damage check, which is a good deal better than a card in
    // hand: the card removed is the damage, so the damage is not taken.
    final over = card.trigger == 'over';
    if (over) {
      side.removed.add(card);
    } else {
      side.damage.add(card);
    }
    state.triggerZone.add(CheckedCard(card, CheckKind.damage, side.name));
    state.note(
      '${side.name} damage checks ${card.name}'
      '${over ? ', which is removed from the game rather than taken as damage' : ' (${side.damageCount} damage)'}.',
      by: side,
    );
    // A trigger found in damage helps the player who took the hit, and its
    // power goes to their vanguard since they are not attacking.
    _applyTrigger(side, card, side.vanguard);
  }

  /// Applies a trigger's automatic half: the power, the critical, the heal.
  ///
  /// The draw and stand triggers move cards and units, so they are done here
  /// too. What is left to the player is only ever a choice of which unit
  /// benefits, and the engine takes the sensible default of the unit doing the
  /// fighting.
  void _applyTrigger(PlaytestSide side, GameCard card, FieldUnit? beneficiary) {
    final trigger = card.trigger;
    if (trigger == null) return;

    final target = beneficiary ?? side.vanguard;
    switch (trigger) {
      case 'critical':
        target?.powerBonus += triggerPower;
        target?.criticalBonus += 1;
        state.note(
          'Critical trigger: +$triggerPower power and +1 critical.',
          by: side,
        );
      case 'draw':
        target?.powerBonus += triggerPower;
        _draw(side);
        state.note('Draw trigger: +$triggerPower power and a card.', by: side);
      case 'front':
        // The front trigger spreads its power across the front row instead of
        // giving it all to one unit, which is why it is not the target here.
        for (final entry in side.field.entries) {
          if (entry.key.isFrontRow && entry.value.isActive) {
            entry.value.powerBonus += triggerPower;
          }
        }
        state.note('Front trigger: +$triggerPower to the front row.', by: side);
      case 'heal':
        target?.powerBonus += triggerPower;
        // Heal only works while you are not ahead on damage.
        final foe = side == state.you ? state.opponent : state.you;
        if (side.damageCount >= foe.damageCount && side.damage.isNotEmpty) {
          side.drop.add(side.damage.removeLast());
          state.note(
            'Heal trigger: +$triggerPower power and a damage healed.',
            by: side,
          );
        } else {
          state.note('Heal trigger: +$triggerPower power, no heal.', by: side);
        }
      case 'stand':
        target?.powerBonus += triggerPower;
        final rested = side.units.where((u) => u.rested).toList();
        if (rested.isNotEmpty) rested.first.rested = false;
        state.note(
          'Stand trigger: +$triggerPower power and a unit stands.',
          by: side,
        );
      case 'over':
        target?.powerBonus += overTriggerPower;
        state.note(
          'Over trigger: +$overTriggerPower power. Read the card for the rest.',
          by: side,
        );
      default:
        break;
    }
  }

  // ------------------------------------------------------ abilities off the card

  /// The abilities the reader could make out on this card, cached: the same
  /// card text is read for every copy on the board, every turn.
  ///
  /// Keyed by the text rather than the card, since the text is what is read
  /// -- two cards printing the same ability share the answer, and a card that
  /// is renamed or reprinted does not carry a stale one.
  CardAbilities abilitiesOf(GameCard card) =>
      _abilityCache[card.effect] ??= readAbilities(card.effect);

  static final Map<String, CardAbilities> _abilityCache = {};

  /// Whether the board answers an ability's condition.
  ///
  /// Only the conditions the reader admits to understanding reach here, so a
  /// false answer means the card said something checkable and the board does
  /// not meet it -- never that the condition was too hard to read.
  bool meets(PlaytestSide side, FieldUnit? unit, AbilityCondition condition) {
    if (condition.isAlways) return true;

    final crest = condition.crestNamed;
    if (crest != null &&
        !side.crestZone.any(
          (c) => c.name.toLowerCase().contains(crest.toLowerCase()),
        )) {
      return false;
    }

    final named = condition.vanguardNamed;
    final vanguard = side.vanguard;
    if (named != null) {
      if (vanguard == null) return false;
      if (!vanguard.card.name.toLowerCase().contains(named.toLowerCase())) {
        return false;
      }
    }
    final grade = condition.vanguardGrade;
    if (grade != null && (vanguard?.card.grade ?? -1) < grade) return false;

    if (condition.hollowed && !(unit?.hollowed ?? false)) return false;
    if (condition.wentSecond && side.goesFirst) return false;

    final drop = condition.dropAtLeast;
    if (drop != null && side.drop.length < drop) return false;

    final faceUp = condition.generationBreak;
    if (faceUp != null && side.generationBreak < faceUp) return false;

    return true;
  }

  /// Hollows a unit: it stays and fights, and is retired at the end of turn.
  ///
  /// A choice, not an automatic consequence -- the card says "you may" -- so
  /// it is offered rather than taken, on the board and in the CPU alike.
  void hollow(PlaytestSide side, Circle circle) {
    final unit = side.field[circle];
    if (unit == null || unit.hollowed || unit.locked) return;
    unit.hollowed = true;
    state.note(
      '${side.name} hollows ${unit.card.name} '
      '(retired at end of turn).',
      by: side,
    );
  }

  /// Whether [side] can pay for [ability] right now.
  bool canPayFor(PlaytestSide side, FieldUnit unit, Ability ability) {
    final cost = ability.cost;
    if (cost.counterBlast > side.openDamage) return false;
    if (cost.soulBlast > side.soul.length) return false;
    if (cost.energy > side.energy) return false;
    if (cost.discard > side.hand.length) return false;
    if (cost.restSelf && unit.rested) return false;
    return true;
  }

  /// Plays one ability off a card: pays what it costs, does what it says.
  ///
  /// [discardable] is the hand the caller is willing to pay a discard out of,
  /// most valuable last, since which card to throw away is a decision and not
  /// the engine's to make.
  ///
  /// Returns false without touching anything if the cost cannot be met, so a
  /// half-paid ability is never left on the board.
  bool playAbility(
    PlaytestSide side,
    Circle circle,
    Ability ability, {
    List<GameCard> discardable = const [],
  }) {
    final unit = side.field[circle];
    if (unit == null || !canPayFor(side, unit, ability)) return false;
    // What the card asks about the board, before anything is paid for it.
    if (!meets(side, unit, ability.condition)) return false;

    final cost = ability.cost;
    if (cost.discard > 0) {
      final pay = [
        ...discardable.where(side.hand.contains),
        ...side.hand,
      ].take(cost.discard).toList();
      if (pay.length < cost.discard) return false;
      for (final card in pay) {
        discard(side, card);
      }
    }
    if (cost.counterBlast > 0) counterBlast(side, cost.counterBlast);
    if (cost.soulBlast > 0) {
      for (final card in side.soul.take(cost.soulBlast).toList()) {
        soulBlast(side, card);
      }
    }
    if (cost.energy > 0) {
      side.energy = (side.energy - cost.energy).clamp(
        0,
        PlaytestSide.energyCap,
      );
    }
    if (cost.restSelf) unit.rested = true;

    final effect = ability.effect;
    // "for each face up card in your G zone" multiplies what it gives, so a
    // crest that pays 5000 a card pays nothing until a stride has come back.
    final times = effect.perFaceUpG ? side.generationBreak : 1;
    if (effect.selfPower != 0) {
      final power = effect.selfPower * times;
      if (effect.untilEndOfBattle) {
        unit.battleBonus += power;
      } else {
        unit.powerBonus += power;
      }
    }
    if (effect.allPower != 0) {
      for (final other in side.units) {
        other.powerBonus += effect.allPower * times;
      }
    }
    if (effect.frontRowPower != 0) {
      for (final entry in side.field.entries) {
        if (entry.key.isFrontRow && entry.value.isActive) {
          entry.value.powerBonus += effect.frontRowPower * times;
        }
      }
    }
    if (effect.becomeHollowed) hollow(side, circle);
    if (effect.critical != 0) unit.criticalBonus += effect.critical;
    for (var i = 0; i < effect.draw; i += 1) {
      _draw(side);
    }
    if (effect.soulCharge > 0) soulCharge(side, effect.soulCharge);
    if (effect.counterCharge > 0) counterCharge(side, effect.counterCharge);
    if (effect.energyCharge > 0) _chargeEnergy(side, effect.energyCharge);

    unit.usedAbilities.add(ability.text);
    state.note(
      '${side.name} plays ${unit.card.name}: ${ability.text}',
      by: side,
    );
    _checkForEnd();
    return true;
  }

  /// Plays an ability off a card that is not on the field -- one discarded to
  /// pay for a stride, say -- where only the effects that need no unit can
  /// happen.
  bool playCardAbility(PlaytestSide side, GameCard card, Ability ability) {
    if (!meets(side, null, ability.condition)) return false;
    final effect = ability.effect;
    for (var i = 0; i < effect.draw; i += 1) {
      _draw(side);
    }
    if (effect.soulCharge > 0) soulCharge(side, effect.soulCharge);
    if (effect.counterCharge > 0) counterCharge(side, effect.counterCharge);
    if (effect.energyCharge > 0) _chargeEnergy(side, effect.energyCharge);
    state.note('${side.name} plays ${card.name}: ${ability.text}', by: side);
    _checkForEnd();
    return true;
  }

  // ------------------------------------------------------- applied by the user

  /// Gives a unit power, for an ability the player is applying by hand.
  void addPower(PlaytestSide side, Circle circle, int amount) {
    final unit = side.field[circle];
    if (unit == null) return;
    unit.powerBonus += amount;
    state.note(
      '${unit.card.name} gets ${amount >= 0 ? '+' : ''}$amount power.',
      by: side,
    );
  }

  /// Gives a unit critical, for an ability that says to.
  ///
  /// Critical is how many damage a hit on the vanguard deals, so this is the
  /// other half of what an ability does to a unit besides power -- and, like
  /// power, it lasts the turn and goes at the end of it. A unit cannot be put
  /// below nought critical, which is what a card reducing it aims at.
  void addCritical(PlaytestSide side, Circle circle, int amount) {
    final unit = side.field[circle];
    if (unit == null) return;
    final before = unit.critical;
    unit.criticalBonus = (unit.criticalBonus + amount).clamp(-1, 98);
    final gained = unit.critical - before;
    if (gained == 0) return;
    state.note(
      '${unit.card.name} gets ${gained >= 0 ? '+' : ''}$gained critical '
      '(now ${unit.critical}).',
      by: side,
    );
  }

  /// Gives the vanguard another drive check, for an ability that grants one.
  ///
  /// Only the vanguard drive checks, so this does nothing anywhere else. Like
  /// power and critical it lasts the turn: a card that grants drive for the
  /// turn needs nothing further, and one that grants it continuously is
  /// re-applied each turn -- which is the safer way round, because forgetting
  /// to add it shows up as a missing check, where forgetting to take it away
  /// would quietly hand out cards.
  void addDrive(PlaytestSide side, Circle circle, int amount) {
    final unit = side.field[circle];
    if (unit == null) return;
    final before = driveCount(unit);
    unit.driveBonus += amount;
    final now = driveCount(unit);
    if (now == before) {
      unit.driveBonus -= amount;
      return;
    }
    state.note(
      '${unit.card.name} drive checks ${now > before ? 'one more' : 'one '
                'fewer'} (now $now).',
      by: side,
    );
  }

  /// Stands or rests a unit by hand, for the same reason.
  void toggleRest(PlaytestSide side, Circle circle) {
    final unit = side.field[circle];
    if (unit == null) return;
    unit.rested = !unit.rested;
    state.note(
      '${unit.card.name} is ${unit.rested ? 'rested' : 'stood'}.',
      by: side,
    );
  }

  /// Energy spent or gained by an ability the player is applying by hand. The
  /// crest's own charge is automatic; everything else lands here.
  void setEnergy(PlaytestSide side, int value) {
    side.energy = value.clamp(0, PlaytestSide.energyCap);
  }

  /// Deals damage directly, for an ability that says to.
  void dealDamage(PlaytestSide side) {
    _damageCheck(side);
    _checkForEnd();
  }
}

/// Decks that can actually be played out.
///
/// A playtest needs a first vanguard to stand up and cards to draw, so a deck
/// still being built is not one you can take into a game.
String? playtestBlocker(DeckView view) {
  final ride = view.items.where((i) => i.entry.zoneId == zoneRide);
  final main = view.items
      .where((i) => i.entry.zoneId == zoneMain)
      .fold(0, (sum, i) => sum + i.entry.quantity);

  final hasFirstVanguard = ride.any(
    (i) => (i.card.attributes['grade'] ?? '') == '0',
  );
  if (!hasFirstVanguard) {
    return 'This deck has no grade 0 in its ride deck, so there is no unit to '
        'start as the vanguard.';
  }
  if (main < 10) {
    return 'This deck has only $main cards in its main deck. Add more before '
        'playtesting it.';
  }
  return null;
}
