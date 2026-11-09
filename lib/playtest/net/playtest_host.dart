import 'dart:async';
import 'dart:math';

import '../../models/card_definition.dart';
import '../order_tokens.dart';
import '../playtest_engine.dart';
import '../playtest_state.dart';
import 'playtest_intent.dart';
import 'playtest_transport.dart';
import 'playtest_wire.dart';

/// The device running the game, with the players' devices attached to it.
///
/// One device holds the board and the rules; the others ask it for things.
/// That asymmetry is the point rather than a shortcut: a player's device
/// never holds the other player's hand, so there is nothing on it to read,
/// and the two boards cannot drift apart because there is only one board.
///
/// Nothing here knows how the messages travel. It is handed a
/// [PlaytestTransport] per seat and that is all it wants to know.
class PlaytestHost {
  PlaytestHost(this.engine);

  final PlaytestEngine engine;

  PlaytestState get state => engine.state;

  final Map<String, PlaytestTransport> _seats = {};
  final Map<String, StreamSubscription<Map<String, Object?>>> _listening = {};

  /// What a player shows to be let back into their seat.
  ///
  /// A phone that drops off the Wi-Fi mid-turn has to be able to knock again,
  /// and the door cannot tell one knock from another. The token is handed out
  /// when a seat is first taken and asked for on every later attempt, so the
  /// seat goes back to the player who left it rather than to whoever dials
  /// next.
  final Map<String, String> _tokens = {};
  static final Random _tokenSource = Random.secure();

  /// The order zone tokens and markers the card database has, by card
  /// number, for a player who asks for one. The host makes it from its own
  /// copy of the card, so nothing of what one says comes over the wire.
  Map<String, CardDefinition> madeCards = const {};

  /// Told when a seat is taken or lost, for a screen that says so.
  void Function(PlaytestSide side, bool connected)? onSeatChanged;

  String tokenFor(PlaytestSide side) => _tokens[side.name] ?? '';

  /// Whether somebody is sitting in [side]'s seat right now.
  bool seated(PlaytestSide side) => _seats[side.name]?.isOpen ?? false;

  /// Which opening hands are settled, and what each player put back.
  final Map<String, List<int>> _mulliganPicks = {};
  final Set<String> _mulliganDone = {};

  /// Refused requests, for a test or a log to read. A refusal is the normal
  /// answer to a message that arrived at the wrong moment, not a failure.
  final List<String> refusals = [];

  /// Seats a player at [side], talking over [transport].
  ///
  /// Seating somebody again replaces whoever was there, which is what a
  /// player coming back after a dropped connection is: the same seat, a new
  /// pipe. The board they get is the board as it stands, so a game carries on
  /// from where it was rather than from where they left.
  String seat(PlaytestSide side, PlaytestTransport transport) {
    unawaited(_listening.remove(side.name)?.cancel());
    final previous = _seats[side.name];
    if (previous != null && previous != transport) {
      unawaited(previous.close());
    }

    _seats[side.name] = transport;
    _listening[side.name] = transport.messages.listen(
      (message) => _receive(side, message),
      // The pipe closing is how a player leaving announces itself: nothing
      // is sent to say so.
      onDone: () => _left(side, transport),
      onError: (Object _) => _left(side, transport),
    );
    _mulliganPicks.putIfAbsent(side.name, () => []);
    final token = _tokens.putIfAbsent(
      side.name,
      () => List.generate(
        6,
        (_) => _tokenSource.nextInt(36).toRadixString(36),
      ).join(),
    );
    transport.send({'type': 'welcome', 'seat': side.name, 'token': token});
    sendTo(side);
    onSeatChanged?.call(side, true);
    return token;
  }

  /// Whether [token] is the one this seat was given.
  bool holdsSeat(PlaytestSide side, String? token) =>
      token != null && token.isNotEmpty && _tokens[side.name] == token;

  void _left(PlaytestSide side, PlaytestTransport transport) {
    // Only if they are still the one sitting there: a player who reconnected
    // already has a new pipe, and the old one closing is the tail end of the
    // old connection rather than news.
    if (_seats[side.name] != transport) return;
    onSeatChanged?.call(side, false);
  }

  Future<void> close() async {
    for (final subscription in _listening.values) {
      await subscription.cancel();
    }
    _listening.clear();
    for (final transport in _seats.values) {
      await transport.close();
    }
    _seats.clear();
  }

  /// Sends every seated player the board as they may see it.
  void broadcast() {
    for (final side in [state.you, state.opponent]) {
      sendTo(side);
    }
  }

  void sendTo(PlaytestSide side) {
    final transport = _seats[side.name];
    if (transport == null || !transport.isOpen) return;
    transport.send({
      'type': 'snapshot',
      'snapshot': snapshotFor(state, side).toJson(),
    });
  }

  void _receive(PlaytestSide side, Map<String, Object?> message) {
    if (message['type'] != 'intent') return;
    final body = message['intent'];
    if (body is! Map) return _refuse(side, 'an intent with no body');
    final intent = PlaytestIntent.fromJson(body.cast<String, Object?>());
    if (intent == null) {
      return _refuse(side, 'an intent this build does not know');
    }
    apply(side, intent);
  }

  /// Does what [side] asked, if [side] is allowed to ask for it.
  ///
  /// Every card named is looked up in that player's own zones. A message
  /// naming a card in the other player's hand finds nothing, which is the
  /// property that makes a guest's device harmless: it can only ask for
  /// things it could already see.
  void apply(PlaytestSide side, PlaytestIntent intent) {
    if (state.isOver) return _refuse(side, 'the game is over');

    // Guarding happens on the other player's turn -- that is what guarding
    // is -- and so does playing a blitz order, which either player may do
    // during a battle. Everything else waits for your own turn.
    const offTurn = {
      IntentKind.guard,
      IntentKind.driveCheck,
      IntentKind.playBlitz,
      // A card answering an attack out of the drop zone is the same moment
      // as a blitz order, and happens on the attacker's turn as often as not.
      IntentKind.activateFromDrop,
      // A damage check heals the defender, on the attacker's turn.
      IntentKind.chooseHeal,
      // A cost paid on the other player's turn binds as readily as one paid
      // on your own, and only out of your own zones.
      IntentKind.bindCard,
      IntentKind.unbindCard,
    };
    final needsTurn = !offTurn.contains(intent.kind);
    final mulliganing = state.phase == PlaytestPhase.mulligan;
    if (!mulliganing && needsTurn && state.active != side) {
      return _refuse(side, 'it is not ${side.name}\'s turn');
    }

    switch (intent.kind) {
      case IntentKind.togglePick:
        if (!mulliganing) return _refuse(side, 'the openings are settled');
        final card = _inHand(side, intent.card);
        if (card == null) return _refuse(side, 'no such card in hand');
        final picks = _mulliganPicks[side.name]!;
        picks.contains(card.instanceId)
            ? picks.remove(card.instanceId)
            : picks.add(card.instanceId);
      case IntentKind.confirmMulligan:
        if (!mulliganing) return _refuse(side, 'the openings are settled');
        _settleMulligan(side);
      case IntentKind.ride:
        final card =
            _inHand(side, intent.card) ?? _inRideDeck(side, intent.card);
        if (card == null) return _refuse(side, 'no such card to ride');
        engine.ride(side, card, fromRideDeck: side.rideDeck.contains(card));
      case IntentKind.call:
        final card = _inHand(side, intent.card);
        final circle = intent.circle;
        if (card == null || circle == null) {
          return _refuse(side, 'no such card to call');
        }
        if (!engine.canCall(side, card, circle)) {
          return _refuse(side, 'that card cannot be called there');
        }
        engine.call(side, card, circle);
      case IntentKind.playOrder:
        final card = _inHand(side, intent.card);
        if (card == null) return _refuse(side, 'no such order in hand');
        engine.playOrder(side, card);
      case IntentKind.playSetOrder:
        final card = _inHand(side, intent.card);
        if (card == null) return _refuse(side, 'no such card in hand');
        if (!card.isSetOrder) return _refuse(side, 'that is not a set order');
        engine.playSetOrder(side, card);
      case IntentKind.removeOrder:
        // Only out of your own order zone: the other player's set orders are
        // theirs to take away, however much you would like them gone.
        final card = side.orderZone
            .where((c) => c.instanceId == intent.card)
            .firstOrNull;
        if (card == null) {
          return _refuse(side, 'no such card in the order zone');
        }
        engine.removeOrder(side, card, to: intent.exit ?? OrderExit.drop);
      case IntentKind.toAutoMod:
        if (intent.card == null) {
          if (side.deck.isEmpty) return _refuse(side, 'the deck is empty');
          engine.toAutoMod(side, side.deck.last);
        } else {
          // Only out of the asker's own public zones and hand: never the
          // deck by id, whose order is nobody's to know.
          final card = [
            ...side.drop,
            ...side.soul,
            ...side.bind,
            ...side.damage,
            ...side.hand,
          ].where((c) => c.instanceId == intent.card).firstOrNull;
          if (card == null) return _refuse(side, 'no such card to gauge');
          engine.toAutoMod(side, card);
        }
      case IntentKind.fromAutoMod:
        final card = side.autoMod
            .where((c) => c.instanceId == intent.card)
            .firstOrNull;
        if (card == null) return _refuse(side, 'no such AutoMOD gauge');
        engine.fromAutoMod(side, card, to: intent.exit ?? OrderExit.hand);
      case IntentKind.placeMarker:
        final circle = intent.circle;
        if (circle == null || !circle.isRearGuard) {
          return _refuse(side, 'a marker goes on a rear-guard circle');
        }
        final known = madeCards[intent.cardNo ?? ''];
        final name = intent.name?.trim() ?? '';
        final marker = known?.attributes['cardType'] == 'marker'
            ? known
            : (name.isEmpty || name.length > 80)
            ? null
            : namedMarker(
                name,
                side.deck.firstOrNull?.card.gameId ?? 'vanguard',
              );
        if (marker == null) return _refuse(side, 'no such marker');
        engine.placeMarker(side, circle, marker);
      case IntentKind.removeMarker:
        final circle = intent.circle;
        final marker = circle == null
            ? null
            : side
                  .markersOn(circle)
                  .where((c) => c.instanceId == intent.card)
                  .firstOrNull;
        if (marker == null) return _refuse(side, 'no such marker there');
        engine.removeMarker(side, circle!, marker);
      case IntentKind.placeOrderToken:
        final made = madeCards[intent.cardNo ?? ''];
        final known = made?.attributes['cardType'] == 'order-set' ? made : null;
        final name = intent.name?.trim() ?? '';
        if (known == null && (name.isEmpty || name.length > 80)) {
          return _refuse(side, 'no such token');
        }
        engine.placeOrderToken(
          side,
          known ??
              namedToken(
                name,
                side.deck.firstOrNull?.card.gameId ?? 'vanguard',
              ),
        );
      case IntentKind.toggleOrderRest:
        // Your own set orders only, as with taking one off the table.
        final card = side.orderZone
            .where((c) => c.instanceId == intent.card)
            .firstOrNull;
        if (card == null) {
          return _refuse(side, 'no such card in the order zone');
        }
        engine.toggleOrderRest(side, card);
      case IntentKind.bindCard:
        final card = [
          ...side.soul,
          ...side.drop,
        ].where((c) => c.instanceId == intent.card).firstOrNull;
        if (card == null) {
          return _refuse(side, 'no such card in your soul or drop zone');
        }
        engine.bindCard(side, card);
      case IntentKind.unbindCard:
        final card = side.bind
            .where((c) => c.instanceId == intent.card)
            .firstOrNull;
        if (card == null) return _refuse(side, 'no such card in the bind zone');
        engine.unbindCard(side, card, to: intent.exit ?? OrderExit.drop);
      case IntentKind.dLegion:
        // Out of the asker's own drop: an id that is not there finds
        // nothing, and four that are not a legal cost do nothing.
        final ids = intent.cards ?? const <int>[];
        final returned = [
          for (final id in ids)
            ?side.drop.where((c) => c.instanceId == id).firstOrNull,
        ];
        if (returned.length != ids.length) {
          return _refuse(side, 'those cards are not all in your drop');
        }
        if (!engine.canDLegion(side)) {
          return _refuse(side, 'your vanguard cannot D-Legion now');
        }
        if (!engine.isDLegionCost(side, returned)) {
          return _refuse(
            side,
            'D-Legion returns four cards: up to two triggers, no heal or over',
          );
        }
        if (engine.dLegion(side, returned) == null) {
          return _refuse(side, 'there is no D-Legion partner left in the deck');
        }
      case IntentKind.chooseHeal:
        // Only your own heal, out of your own damage zone.
        final check = state.triggerZone
            .where(
              (c) =>
                  c.card.instanceId == intent.amount &&
                  c.sideName == side.name &&
                  c.healed != null,
            )
            .firstOrNull;
        if (check == null) return _refuse(side, 'no heal of yours to change');
        final card = engine
            .healOptions(side, check)
            .where((c) => c.instanceId == intent.card)
            .firstOrNull;
        if (card == null) return _refuse(side, 'that damage cannot be healed');
        engine.changeHeal(side, check, card);
      case IntentKind.playBlitz:
        if (state.attack == null && state.phase != PlaytestPhase.battle) {
          return _refuse(side, 'a blitz order waits for a battle');
        }
        final card = _inHand(side, intent.card);
        if (card == null) return _refuse(side, 'no such card in hand');
        if (!card.isBlitz) return _refuse(side, 'that is not a blitz order');
        // The shield it hands over comes with the request: the card knows
        // what it gives and the board does not.
        engine.playBlitz(
          side,
          card,
          shield: (intent.amount ?? 0).clamp(0, 50000),
        );
      case IntentKind.activateFromDrop:
        if (state.active != side && state.attack == null) {
          return _refuse(side, 'it is not ${side.name}\'s turn');
        }
        final card = side.drop
            .where((c) => c.instanceId == intent.card)
            .firstOrNull;
        if (card == null) {
          return _refuse(side, 'no such card in the drop zone');
        }
        engine.activateFromDrop(side, card);
        // What it gave the battle, if it was played into one.
        if (state.attack != null && (intent.amount ?? 0) > 0) {
          engine.addShield(side, intent.amount!.clamp(0, 50000));
        }
      case IntentKind.discard:
        final card = _inHand(side, intent.card);
        if (card == null) return _refuse(side, 'no such card in hand');
        engine.discard(side, card);
      case IntentKind.handToSoul:
        final card = _inHand(side, intent.card);
        if (card == null) return _refuse(side, 'no such card in hand');
        engine.handToSoul(side, card);
      case IntentKind.bottomDeck:
        final card = _inHand(side, intent.card);
        if (card == null) return _refuse(side, 'no such card in hand');
        engine.bottomDeck(side, card);
      case IntentKind.drawCard:
        engine.drawCard(side);
      case IntentKind.nextPhase:
        engine.advancePhase();
      case IntentKind.attack:
        final from = intent.circle;
        final to = intent.to;
        if (from == null || to == null) return _refuse(side, 'attack where?');
        if (!engine.canAttack(side)) {
          return _refuse(side, 'nobody attacks on the first turn');
        }
        if (!engine.attackers(side).contains(from) ||
            !engine.targets(side).contains(to)) {
          return _refuse(side, 'that attack is not on offer');
        }
        engine.declareAttack(from: from, to: to, boost: intent.amount == 1);
      case IntentKind.guard:
        if (state.attack == null) return _refuse(side, 'nothing to guard');
        if (state.inactive != side) {
          return _refuse(side, 'the attacker does not guard');
        }
        final card = _inHand(side, intent.card);
        if (card == null) return _refuse(side, 'no such card in hand');
        if (!card.canGuard) return _refuse(side, 'that card has no shield');
        engine.addGuardian(card);
      case IntentKind.driveCheck:
        if (state.active != side) {
          return _refuse(side, 'the drive check is the attacker\'s');
        }
        if (engine.drivesLeft() <= 0) return _refuse(side, 'no drive owed');
        engine.driveCheckOne();
      case IntentKind.resolveAttack:
        if (state.attack == null) return _refuse(side, 'nothing to resolve');
        engine.resolveAttack();
      case IntentKind.toggleRest:
        final circle = intent.circle;
        if (circle == null) return _refuse(side, 'which circle?');
        engine.toggleRest(side, circle);
      case IntentKind.retire:
        final circle = intent.circle;
        if (circle == null) return _refuse(side, 'which circle?');
        engine.retire(side, circle);
      case IntentKind.moveUnit:
        final circle = intent.circle;
        if (circle == null) return _refuse(side, 'which circle?');
        if (!engine.canMove(side, circle)) {
          return _refuse(side, 'that unit cannot move');
        }
        engine.moveUnit(side, circle);
      case IntentKind.swapUnits:
        final from = intent.circle;
        final to = intent.to;
        if (from == null || to == null) {
          return _refuse(side, 'swap which two circles?');
        }
        if (!engine.canSwap(side, from, to)) {
          return _refuse(side, 'those two cannot change places');
        }
        engine.swapUnits(side, from, to);
      case IntentKind.unitToSoul:
        final circle = intent.circle;
        if (circle == null) return _refuse(side, 'which circle?');
        engine.unitToSoul(side, circle);
      case IntentKind.setEnergy:
        engine.setEnergy(side, intent.amount ?? side.energy);
      case IntentKind.shuffleDeck:
        engine.shuffleDeck(side);
      case IntentKind.addPower:
        final circle = intent.circle;
        if (circle == null) return _refuse(side, 'which circle?');
        engine.addPower(side, circle, intent.amount ?? 0);
      case IntentKind.addCritical:
        final circle = intent.circle;
        if (circle == null) return _refuse(side, 'which circle?');
        engine.addCritical(side, circle, intent.amount ?? 0);
      case IntentKind.addDrive:
        final circle = intent.circle;
        if (circle == null) return _refuse(side, 'which circle?');
        engine.addDrive(side, circle, intent.amount ?? 0);
    }
    broadcast();
  }

  /// Puts back what this player picked, and starts the game once both have.
  void _settleMulligan(PlaytestSide side) {
    if (_mulliganDone.contains(side.name)) return;
    final picks = _mulliganPicks[side.name]!;
    engine.mulligan(side, [
      for (final card in [...side.hand])
        if (picks.contains(card.instanceId)) card,
    ]);
    _mulliganDone.add(side.name);
    if (_mulliganDone.length == 2) engine.beginPlay();
  }

  GameCard? _inHand(PlaytestSide side, int? instanceId) => instanceId == null
      ? null
      : side.hand.where((c) => c.instanceId == instanceId).firstOrNull;

  GameCard? _inRideDeck(PlaytestSide side, int? instanceId) =>
      instanceId == null
      ? null
      : side.rideDeck.where((c) => c.instanceId == instanceId).firstOrNull;

  void _refuse(PlaytestSide side, String reason) {
    refusals.add('${side.name}: $reason');
    _seats[side.name]?.send({'type': 'refused', 'reason': reason});
  }
}
