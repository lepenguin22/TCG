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
    _listening = transport.messages.listen(_receive);
  }

  final PlaytestTransport transport;

  /// Which game's cards these are, for turning a face back into a card the
  /// rest of the app understands.
  final String gameId;

  late final StreamSubscription<Map<String, Object?>> _listening;

  /// The last board the host sent, or nothing before the first one arrives.
  PlaytestSnapshot? snapshot;

  /// Why the last request was turned down, if it was. Cleared by the next
  /// snapshot, since a board that moved is an answer in itself.
  String? refusal;

  /// Whether anything has arrived yet.
  bool get connected => snapshot != null;

  /// Asks the host to do something.
  void ask(PlaytestIntent intent) {
    transport.send({'type': 'intent', 'intent': intent.toJson()});
  }

  /// A card by instance id, as far as this device is allowed to know it.
  /// Null means a card lying face down, which is a perfectly good answer.
  GameCard? cardOf(int instanceId) =>
      snapshot?.faces[instanceId]?.toGameCard(gameId);

  void _receive(Map<String, Object?> message) {
    switch (message['type']) {
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
    unawaited(_listening.cancel());
    super.dispose();
  }
}
