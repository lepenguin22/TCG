import 'dart:async';
import 'dart:math';

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
    // is -- and so does taking damage from an attack. Everything else waits
    // for your own turn.
    const offTurn = {IntentKind.guard, IntentKind.driveCheck};
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
