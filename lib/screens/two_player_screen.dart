import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../games/games.dart';
import '../models/deck.dart';
import '../playtest/net/socket_transport.dart';
import '../playtest/net/two_player_session.dart';
import '../playtest/net/wire_deck.dart';
import '../playtest/playtest_state.dart';
import '../store/deck_store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'remote_board_view.dart';

/// A game played across two devices: this one, and one other.
///
/// Whoever presses Host runs the game; whoever presses Join dials them. Both
/// play the same board, because the host is a guest of its own game.
class TwoPlayerScreen extends StatefulWidget {
  const TwoPlayerScreen.host({super.key, required this.deck, this.turnOrder})
    : address = null;

  const TwoPlayerScreen.join({
    super.key,
    required this.deck,
    required this.address,
  }) : turnOrder = null;

  final Deck deck;

  /// The host to dial, when this device is the one joining.
  final String? address;
  final TurnOrder? turnOrder;

  bool get hosting => address == null;

  @override
  State<TwoPlayerScreen> createState() => _TwoPlayerScreenState();
}

class _TwoPlayerScreenState extends State<TwoPlayerScreen> {
  HostSession? _host;
  GuestSession? _guest;

  @override
  void initState() {
    super.initState();
    // The store is read once, here: the deck goes over the wire as cards and
    // is not looked at again.
    final store = context.read<DeckStore>();
    final deck = WireDeck.of(store.viewOf(widget.deck));
    if (widget.hosting) {
      final session = HostSession(
        gameId: widget.deck.gameId,
        deck: deck,
        crests: store.cards,
        turnOrder: widget.turnOrder ?? TurnOrder.random,
      );
      _host = session..addListener(_refresh);
      session.open();
    } else {
      final session = GuestSession(gameId: widget.deck.gameId, deck: deck);
      _guest = session..addListener(_refresh);
      session.join(widget.address!);
    }
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _host
      ?..removeListener(_refresh)
      ..close();
    _guest
      ?..removeListener(_refresh)
      ..close();
    super.dispose();
  }

  SessionStage get stage => _host?.stage ?? _guest!.stage;

  @override
  Widget build(BuildContext context) {
    final board = _host?.board ?? _guest?.board;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await _confirmLeaving(context, playing: board != null);
        if (leave && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            board?.snapshot == null
                ? (widget.hosting ? 'Hosting a game' : 'Joining a game')
                : 'Turn ${board!.snapshot!.turn} · '
                      '${board.snapshot!.activeName}',
          ),
        ),
        body: SafeArea(
          child: board != null && stage == SessionStage.playing
              ? RemoteBoardView(
                  board: board,
                  onLeave: () => Navigator.of(context).pop(),
                )
              : _lobby(),
        ),
      ),
    );
  }

  Widget _lobby() {
    final failure = _host?.failure ?? _guest?.failure;
    if (failure != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: EmptyState(
          icon: Icons.wifi_off,
          title: widget.hosting
              ? 'Could not open the game'
              : 'Could not reach that device',
          message:
              '$failure\n\nBoth phones have to be on the same Wi-Fi, and the '
              'address has to be the one the host is showing.',
        ),
      );
    }
    if (widget.hosting) {
      final host = _host!;
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          const SectionHeader(
            title: 'Waiting for the other player',
            caption:
                'They open the same deck, tap Two devices, then Join, and '
                'type this in. Both phones need to be on the same Wi-Fi.',
          ),
          const SizedBox(height: 12),
          for (final address in host.addresses)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Panel(
                onTap: () => Clipboard.setData(ClipboardData(text: address)),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        address,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    const Icon(Icons.copy, color: AppColors.textFaint),
                  ],
                ),
              ),
            ),
          if (host.addresses.isEmpty)
            const Text(
              'This device is not on a network any other device could '
              'reach. Join a Wi-Fi network, or turn on a hotspot and have '
              'the other phone join it.',
              style: TextStyle(color: AppColors.textMuted),
            ),
          const SizedBox(height: 8),
          if (host.port != null && host.port != PlaytestServer.defaultPort)
            Text(
              'Port ${host.port}',
              style: const TextStyle(color: AppColors.textFaint, fontSize: 12),
            ),
          const SizedBox(height: 24),
          const Center(child: CircularProgressIndicator()),
        ],
      );
    }
    return const Center(child: CircularProgressIndicator());
  }

  static Future<bool> _confirmLeaving(
    BuildContext context, {
    required bool playing,
  }) async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(playing ? 'Leave the game?' : 'Stop waiting?'),
        content: Text(
          playing
              ? 'The board goes with it, and the other player is dropped.'
              : 'Nobody has joined yet.',
          style: const TextStyle(color: AppColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(playing ? 'Keep playing' : 'Keep waiting'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }
}

/// Asks for the address the host is showing.
Future<void> showJoinDialog(BuildContext context, Deck deck) async {
  final field = TextEditingController();
  final address = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Join a game'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Type the address the other phone is showing.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: field,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Address',
              hintText: '192.168.0.12',
            ),
            onSubmitted: (value) =>
                Navigator.of(dialogContext).pop(value.trim()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(field.text.trim()),
          child: const Text('Join'),
        ),
      ],
    ),
  );
  field.dispose();
  if (address == null || address.isEmpty || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => TwoPlayerScreen.join(deck: deck, address: address),
    ),
  );
}

/// Whether this game can be played across two devices at all. Only the games
/// whose board the app can draw, which today is the one.
bool twoPlayerSupported(String gameId) => gameById(gameId).id == 'vanguard';
