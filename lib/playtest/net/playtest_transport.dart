import 'dart:async';

/// The pipe between two devices playing one game.
///
/// Deliberately the smallest thing that could carry a game: JSON in, JSON
/// out, and a way to hang up. A socket, a Bluetooth link or a relay server
/// are all this interface with something different behind it, and none of
/// them exist yet -- [LoopbackTransport] is the one that does, and it is
/// enough to play a whole game inside a test.
abstract class PlaytestTransport {
  /// What the other end has sent. A broadcast stream: the host listens for
  /// intents and the board listens for snapshots, and both may want the same
  /// message.
  Stream<Map<String, Object?>> get messages;

  /// Sends a message to the other end. Silently does nothing once closed --
  /// a hung-up connection is a fact about the world, not a programming error.
  void send(Map<String, Object?> message);

  bool get isOpen;

  Future<void> close();
}

/// Two ends of a pipe with no wire in between, for tests and for a game
/// played on one device.
///
/// Messages are delivered asynchronously, exactly as a real connection would:
/// code that only works because the other end answered instantly would be
/// code that breaks the moment it meets a socket.
class LoopbackTransport implements PlaytestTransport {
  LoopbackTransport._();

  /// Two ends, each sending to the other.
  static (LoopbackTransport, LoopbackTransport) pair() {
    final first = LoopbackTransport._();
    final second = LoopbackTransport._();
    first._other = second;
    second._other = first;
    return (first, second);
  }

  final StreamController<Map<String, Object?>> _incoming =
      StreamController<Map<String, Object?>>.broadcast();
  late final LoopbackTransport _other;
  bool _open = true;

  /// Every message this end has sent, in order. For a test that wants to
  /// read the conversation rather than its result.
  final List<Map<String, Object?>> sent = [];

  @override
  Stream<Map<String, Object?>> get messages => _incoming.stream;

  @override
  bool get isOpen => _open;

  @override
  void send(Map<String, Object?> message) {
    if (!_open || !_other._open) return;
    sent.add(message);
    _other._incoming.add(message);
  }

  @override
  Future<void> close() async {
    if (!_open) return;
    _open = false;
    await _incoming.close();
  }
}
