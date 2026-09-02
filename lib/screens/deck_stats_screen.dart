import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../games/games.dart';
import '../store/deck_store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/issue_list.dart';
import '../widgets/stat_chart.dart';

class DeckStatsScreen extends StatelessWidget {
  const DeckStatsScreen({super.key, required this.deckId});

  final String deckId;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DeckStore>();
    final deck = store.deckById(deckId);

    if (deck == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Breakdown')),
        body: EmptyState(
          icon: Icons.help_outline,
          title: 'Deck not found',
          message: 'It may have been deleted.',
          action: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back'),
          ),
        ),
      );
    }

    final game = gameById(deck.gameId);
    final view = store.viewOf(deck);

    return Scaffold(
      appBar: AppBar(title: const Text('Breakdown')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Total(label: 'Cards', value: view.totalCount),
              _Total(label: 'Distinct', value: view.distinctCount),
              for (final zoneId in view.format.zoneIds)
                _Total(
                  label: game.zone(zoneId)?.shortName ?? zoneId,
                  value: view.zoneCount(zoneId),
                ),
            ],
          ),
          const SizedBox(height: 16),
          IssueList(issues: game.validate(view)),
          const SizedBox(height: 16),
          for (final group in game.stats(view)) StatChart(group: group),
        ],
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: AppColors.textFaint,
              fontSize: 11,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}
