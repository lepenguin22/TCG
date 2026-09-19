import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'playtest_transport.dart';

/// A pipe with a real network behind it: one device listening, the other
/// dialling in, both on the same Wi-Fi.
///
/// Messages are JSON, one per line. A line is a whole message, which is the
/// oldest framing there is and the easiest to be sure of: TCP hands over
/// whatever arrived, which may be half a message or three of them, so the
/// remainder is kept until its newline turns up.
class SocketTransport implements PlaytestTransport {
  SocketTransport(this._socket) {
    _socket
      ..setOption(SocketOption.tcpNoDelay, true)
      ..listen(
        _onData,
        onError: (Object error) => _hangUp(),
        onDone: _hangUp,
        cancelOnError: true,
      );
  }

  /// Dials a device that is listening.
  static Future<SocketTransport> connect(
    String host,
    int port, {
    Duration timeout = const Duration(seconds: 10),
  }) async =>
      SocketTransport(await Socket.connect(host, port, timeout: timeout));

  final Socket _socket;
  final StreamController<Map<String, Object?>> _incoming =
      StreamController<Map<String, Object?>>.broadcast();
  final StringBuffer _partial = StringBuffer();
  bool _open = true;

  @override
  Stream<Map<String, Object?>> get messages => _incoming.stream;

  @override
  bool get isOpen => _open;

  @override
  void send(Map<String, Object?> message) {
    if (!_open) return;
    try {
      _socket.write('${jsonEncode(message)}\n');
    } on SocketException {
      // The other phone walked out of range. Nothing to do about it here;
      // the stream closing is what tells the game.
      _hangUp();
    }
  }

  @override
  Future<void> close() async {
    if (!_open) return;
    _open = false;
    await _socket.close().catchError((Object _) => _socket);
    _socket.destroy();
    await _incoming.close();
  }

  void _onData(List<int> bytes) {
    _partial.write(utf8.decode(bytes, allowMalformed: true));
    final text = _partial.toString();
    final lines = text.split('\n');
    // The last piece has no newline yet, so it is the start of the next
    // message rather than a message.
    _partial
      ..clear()
      ..write(lines.removeLast());
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map) _incoming.add(decoded.cast<String, Object?>());
      } on FormatException {
        // A line that is not JSON is not a message. Dropping it keeps a
        // garbled packet from taking the game down with it.
        continue;
      }
    }
  }

  void _hangUp() {
    if (!_open) return;
    _open = false;
    unawaited(_incoming.close());
    _socket.destroy();
  }
}

/// The device that waits to be dialled.
///
/// One game at a time: the first player through the door gets the seat, and
/// the listener closes behind them so a third phone cannot wander in.
class PlaytestServer {
  PlaytestServer._(this._socket);

  /// Starts listening on [port], on every address this device has.
  static Future<PlaytestServer> bind({int port = defaultPort}) async =>
      PlaytestServer._(
        await ServerSocket.bind(InternetAddress.anyIPv4, port, shared: false),
      );

  /// Nothing official, just a number nothing else is likely to want.
  static const defaultPort = 47707;

  final ServerSocket _socket;

  int get port => _socket.port;

  /// The first player to arrive.
  Future<SocketTransport> waitForPlayer() async {
    final connection = await _socket.first;
    await _socket.close();
    return SocketTransport(connection);
  }

  Future<void> close() => _socket.close();

  /// The addresses a player on the same Wi-Fi could dial, best guess first.
  ///
  /// A phone has several: the Wi-Fi one is the one that works, and the rest
  /// are loopback and whatever a VPN left behind. They are all offered rather
  /// than guessed between, since only the person holding the phone knows
  /// which network they are on.
  static Future<List<String>> addresses() async {
    final found = <String>[];
    for (final interface in await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    )) {
      for (final address in interface.addresses) {
        found.add(address.address);
      }
    }
    // A home or phone-hotspot network looks like this, and is what two people
    // at a table are almost certainly on.
    found.sort((a, b) {
      bool private(String ip) =>
          ip.startsWith('192.168.') || ip.startsWith('10.');
      if (private(a) == private(b)) return a.compareTo(b);
      return private(a) ? -1 : 1;
    });
    return found;
  }
}
