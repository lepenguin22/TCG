import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/deck.dart';
import '../playtest/playtest_engine.dart';
import '../store/deck_store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'playtest_screen.dart';

/// Chooses who the deck is being tested against.
///
/// A mirror match is offered first and by name, because it is the question a
/// deck usually needs answered: does this thing ride, draw and hold up at all.
/// Any other deck in the library is a matchup test.
class PlaytestSetupScreen extends StatelessWidget {
  const PlaytestSetupScreen({super.key, required this.deck});

  final Deck deck;

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
                      const Text(
                        'You play this deck. Pick who to play against.',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const SectionHeader(title: 'Opponent'),
                const SizedBox(height: 8),
                _OpponentTile(
                  title: 'Mirror match',
                  subtitle: 'The CPU plays the same deck.',
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
                            'What the CPU does and does not do',
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
                        'Card abilities are written as text on the card, not '
                        'as anything a program can follow, so neither side '
                        'plays them automatically. Tap a unit to read its '
                        'text and apply it yourself. Every zone an ability '
                        'is paid out of is on the board and tappable — '
                        'counter-blast out of damage, soul-blast out of '
                        'soul, search the deck, take a card back from the '
                        'drop, and stride out of the G zone.',
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

  static void _start(BuildContext context, Deck yours, Deck theirs) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => PlaytestScreen(yourDeck: yours, opponentDeck: theirs),
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
