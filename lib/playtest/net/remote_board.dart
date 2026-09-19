import 'dart:async';

import 'package:flutter/foundation.dart';

import '../playtest_state.dart';
import 'playtest_intent.dart';
import 'playtest_transport.dart';
import 'playtest_wire.dart';

/// The board as a player's own device holds it: the last picture the host
/// sent, and a way to ask for the next move.
///
/// This is all a guest device ever has. There is no engine here and no rules
/// -- it cannot ride a unit any more than it can read the other player's
/// hand, because it holds neither. Asking and being told is the whole of it.
class RemoteBoard extends ChangeNotifier {
  RemoteBoard({required this.transport, required this.gameId}) {
    _listen(transport);
  }

  PlaytestTransport transport;

  /// Which game's cards these are, for turning a face back into a card the
  /// rest of the app understands.
  final String gameId;

  StreamSubscription<Map<String, Object?>>? _listening;

  /// What this device shows to be let back into its seat after the Wi-Fi
  /// drops. Handed over when the seat is first taken.
  String? token;

  /// Whether the pipe to the game is open. The board stays on the screen
  /// while it is not: a game nobody can reach for a moment is still a game,
  /// and blanking it would lose the player their place.
  bool live = true;

  /// Told when the pipe closes, so whoever owns it can dial again.
  VoidCallback? onLost;

  /// The last board the host sent, or nothing before the first one arrives.
  PlaytestSnapshot? snapshot;

  /// Why the last request was turned down, if it was. Cleared by the next
  /// snapshot, since a board that moved is an answer in itself.
  String? refusal;

  /// Whether anything has arrived yet.
  bool get connected => snapshot != null;

  /// Asks the host to do something. Dropped on the floor while the pipe is
  /// down: the board will be told what really happened when it comes back.
  void ask(PlaytestIntent intent) {
    if (!live) return;
    transport.send({'type': 'intent', 'intent': intent.toJson()});
  }

  /// Takes up a new pipe to the same game, after the last one dropped.
  void resumeOn(PlaytestTransport replacement) {
    transport = replacement;
    live = true;
    _listen(replacement);
    replacement.send({'type': 'resume', 'token': token});
    notifyListeners();
  }

  void _listen(PlaytestTransport pipe) {
    unawaited(_listening?.cancel());
    _listening = pipe.messages.listen(
      _receive,
      onDone: _lost,
      onError: (Object _) => _lost(),
    );
  }

  void _lost() {
    if (!live) return;
    live = false;
    notifyListeners();
    onLost?.call();
  }

  /// A card by instance id, as far as this device is allowed to know it.
  /// Null means a card lying face down, which is a perfectly good answer.
  GameCard? cardOf(int instanceId) =>
      snapshot?.faces[instanceId]?.toGameCard(gameId);

  void _receive(Map<String, Object?> message) {
    switch (message['type']) {
      case 'welcome':
        token = message['token'] as String? ?? token;
      case 'snapshot':
        final body = message['snapshot'];
        if (body is! Map) return;
        snapshot = PlaytestSnapshot.fromJson(body.cast<String, Object?>());
        refusal = null;
        notifyListeners();
      case 'refused':
        refusal = message['reason'] as String?;
        notifyListeners();
    }
  }

  @override
  void dispose() {
    onLost = null;
    unawaited(_listening?.cancel());
    super.dispose();
  }
}
