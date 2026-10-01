import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/deck.dart';
import '../playtest/playtest_engine.dart';
import '../playtest/playtest_state.dart';
import '../store/deck_store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'playtest_screen.dart';
import 'two_player_screen.dart';

/// Chooses who the deck is being tested against.
///
/// A mirror match is offered first and by name, because it is the question a
/// deck usually needs answered: does this thing ride, draw and hold up at all.
/// Any other deck in the library is a matchup test.
class PlaytestSetupScreen extends StatefulWidget {
  const PlaytestSetupScreen({super.key, required this.deck});

  final Deck deck;

  @override
  State<PlaytestSetupScreen> createState() => _PlaytestSetupScreenState();
}

/// Who is on the other side of the table.
///
/// One board on this device with both hands yours, or another phone -- which
/// is not a mode of the same game at all, but a different one played against
/// somebody who is not in this app.
enum _Across { bothSides, twoDevices }

class _PlaytestSetupScreenState extends State<PlaytestSetupScreen> {
  TurnOrder _turnOrder = TurnOrder.playerOneFirst;
  _Across _across = _Across.bothSides;

  bool get _bothSides => _across == _Across.bothSides;

  bool get _twoDevices => _across == _Across.twoDevices;

  Deck get deck => widget.deck;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DeckStore>();
    final blocker = playtestBlocker(store.viewOf(deck));

    final others = store.decks
        .where((d) => d.gameId == deck.gameId && d.id != deck.id)
        .where((d) => playtestBlocker(store.viewOf(d)) == null)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Playtest')),
      body: blocker != null
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: EmptyState(
                icon: Icons.videogame_asset_off_outlined,
                title: 'This deck cannot be played yet',
                message: blocker,
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        deck.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _bothSides
                            ? 'This is Player 1\u2019s deck. Pick the deck '
                                  'to play it against; both hands are yours.'
                            : 'You play this deck. The other player brings '
                                  'their own.',
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const SectionHeader(
                  title: 'Where the other side is played',
                  caption:
                      'Both hands on this board, or another person on another '
                      'phone with their own.',
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<_Across>(
                    segments: const [
                      ButtonSegment(
                        value: _Across.bothSides,
                        label: Text('Both sides'),
                        icon: Icon(Icons.groups_outlined, size: 18),
                      ),
                      ButtonSegment(
                        value: _Across.twoDevices,
                        label: Text('Two devices'),
                        icon: Icon(Icons.wifi_tethering, size: 18),
                      ),
                    ],
                    selected: {_across},
                    showSelectedIcon: false,
                    onSelectionChanged: (chosen) =>
                        setState(() => _across = chosen.first),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _twoDevices
                      ? 'Another person on another phone, both on the same '
                            'Wi-Fi. One of you hosts and the other joins; '
                            'each plays their own deck off their own phone, '
                            'and neither holds the other\'s hand.'
                      : 'Nothing moves unless you move it: both openings, '
                            'both boards, both guards. Every ability is '
                            'applied by hand, and the board offers each one '
                            'at the moment it fires.',
                  style: const TextStyle(
                    color: AppColors.textFaint,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
                const SectionHeader(
                  title: 'Turn order',
                  caption:
                      'Going second is paid three energy by the crest, '
                      'so it is worth testing from both sides.',
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<TurnOrder>(
                    segments: [
                      ButtonSegment(
                        value: TurnOrder.playerOneFirst,
                        label: Text('Player 1'),
                      ),
                      const ButtonSegment(
                        value: TurnOrder.playerTwoFirst,
                        label: Text('Player 2'),
                      ),
                      const ButtonSegment(
                        value: TurnOrder.random,
                        label: Text('Random'),
                      ),
                    ],
                    selected: {_turnOrder},
                    showSelectedIcon: false,
                    onSelectionChanged: (chosen) =>
                        setState(() => _turnOrder = chosen.first),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _turnOrder == TurnOrder.random
                      ? 'Rolled again every time you restart the board.'
                      : _turnOrder.label,
                  style: const TextStyle(
                    color: AppColors.textFaint,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
                if (_twoDevices) ...[
                  const SectionHeader(
                    title: 'Host or join',
                    caption:
                        'One phone hosts and shows an address; the other '
                        'types it in. The host runs the game, and plays in '
                        'it the same way the other player does.',
                  ),
                  const SizedBox(height: 8),
                  _OpponentTile(
                    title: 'Host the game',
                    subtitle: 'Wait for the other player to join you.',
                    icon: Icons.wifi_tethering,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TwoPlayerScreen.host(
                          deck: deck,
                          turnOrder: _turnOrder,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _OpponentTile(
                    title: 'Join a game',
                    subtitle: 'Type the address the other phone is showing.',
                    icon: Icons.login,
                    onTap: () => showJoinDialog(context, deck),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'A game across two devices plays the core of the game: '
                    'riding, calling, attacking, guarding, the checks and '
                    'the zones. The hand-applied ability tools -- striding, '
                    'counter-blasts, searching the deck -- are still only on '
                    'the board you play by yourself.',
                    style: TextStyle(color: AppColors.textFaint, fontSize: 12),
                  ),
                ] else ...[
                  SectionHeader(title: 'The other deck'),
                  const SizedBox(height: 8),
                  _OpponentTile(
                    title: 'Mirror match',
                    subtitle: 'The same deck on both sides.',
                    icon: Icons.flip_camera_android_outlined,
                    onTap: () => _start(context, deck, deck),
                  ),
                  for (final other in others) ...[
                    const SizedBox(height: 8),
                    _OpponentTile(
                      title: other.name,
                      subtitle: _describe(store, other),
                      icon: Icons.style_outlined,
                      accent: accentColor(other.accent),
                      onTap: () => _start(context, deck, other),
                    ),
                  ],
                ],
                const SizedBox(height: 24),
                const Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 18,
                            color: AppColors.textMuted,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'What the board does and does not do',
                            style: TextStyle(
                              color: AppColors.text,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 10),
                      Text(
                        'The board runs the rules it can: riding, calling, '
                        'boosting, attacking, drive and damage checks, '
                        'triggers, shields and the damage race.\n\n'
                        'Card abilities are printed English, and only the '
                        'plainest shapes of it can be executed, so most are '
                        'left to be applied by hand. Tap a unit to read its '
                        'text and play it yourself. Every zone an ability '
                        'is paid out of is on the board and tappable — '
                        'counter-blast out of damage, soul-blast out of '
                        'soul, search the deck, take a card back from the '
                        'drop, and stride out of the G zone.\n\n'
                        'Taking both sides yourself is the way to test a '
                        'deck whose abilities the reader cannot follow: '
                        'nothing is skipped, because nothing happens that '
                        'you did not do.',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  static String _describe(DeckStore store, Deck deck) {
    final view = store.viewOf(deck);
    final total = view.items
        .where((i) => i.entry.zoneId != 'gzone')
        .fold(0, (sum, i) => sum + i.entry.quantity);
    return '$total cards · ${view.format.name}';
  }

  void _start(BuildContext context, Deck yours, Deck theirs) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => PlaytestScreen(
          yourDeck: yours,
          opponentDeck: theirs,
          turnOrder: _turnOrder,
        ),
      ),
    );
  }
}

class _OpponentTile extends StatelessWidget {
  const _OpponentTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.accent,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Panel(
      accent: accent,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: accent ?? AppColors.textMuted),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textFaint),
        ],
      ),
    );
  }
}
