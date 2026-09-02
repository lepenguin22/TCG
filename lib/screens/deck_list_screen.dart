import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../games/game_definition.dart';
import '../games/games.dart';
import '../models/deck.dart';
import '../store/deck_store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/option_picker.dart';
import 'deck_screen.dart';
import 'import_decklog_screen.dart';
import 'new_deck_screen.dart';
import 'settings_screen.dart';

class DeckListScreen extends StatefulWidget {
  const DeckListScreen({super.key});

  @override
  State<DeckListScreen> createState() => _DeckListScreenState();
}

class _DeckListScreenState extends State<DeckListScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  String _gameFilter = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DeckStore>();
    final needle = _query.trim().toLowerCase();

    final decks =
        store.decks
            .where((d) => _gameFilter == 'all' || d.gameId == _gameFilter)
            .where(
              (d) =>
                  needle.isEmpty ||
                  d.name.toLowerCase().contains(needle) ||
                  d.description.toLowerCase().contains(needle),
            )
            .toList()
          ..sort((a, b) {
            if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
            return b.updatedAt.compareTo(a.updatedAt);
          });

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Decks'),
        actions: [
          IconButton(
            tooltip: 'Import from Deck Log',
            icon: const Icon(Icons.download_outlined),
            onPressed: _importFromDecklog,
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createDeck,
        icon: const Icon(Icons.add),
        label: const Text('New deck'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          if (store.decks.isNotEmpty) ...[
            TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                hintText: 'Search decks',
                prefixIcon: Icon(Icons.search, color: AppColors.textFaint),
              ),
            ),
            if (games.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OptionChip(
                      label: 'All games',
                      selected: _gameFilter == 'all',
                      onTap: () => setState(() => _gameFilter = 'all'),
                    ),
                    for (final game in games)
                      OptionChip(
                        label: game.shortName,
                        color: game.accent,
                        selected: _gameFilter == game.id,
                        onTap: () => setState(() => _gameFilter = game.id),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
          ],
          if (decks.isEmpty)
            EmptyState(
              icon: Icons.style_outlined,
              title: store.decks.isEmpty ? 'No decks yet' : 'Nothing matches',
              message: store.decks.isEmpty
                  ? 'Build your first Cardfight!! Vanguard list. The app checks it against the format rules as you go.'
                  : 'Try a different search or clear the game filter.',
              action: store.decks.isEmpty
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FilledButton.icon(
                          onPressed: _createDeck,
                          icon: const Icon(Icons.add),
                          label: const Text('Create a deck'),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _importFromDecklog,
                          icon: const Icon(Icons.download_outlined, size: 18),
                          label: const Text('Import from Deck Log'),
                        ),
                      ],
                    )
                  : null,
            )
          else
            for (final deck in decks)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _DeckCard(deck: deck),
              ),
        ],
      ),
    );
  }

  Future<void> _importFromDecklog() async {
    final deckId = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ImportDecklogScreen()),
    );
    if (deckId != null && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => DeckScreen(deckId: deckId)),
      );
    }
  }

  Future<void> _createDeck() async {
    final deckId = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const NewDeckScreen()));
    if (deckId != null && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => DeckScreen(deckId: deckId)),
      );
    }
  }
}

class _DeckCard extends StatelessWidget {
  const _DeckCard({required this.deck});

  final Deck deck;

  @override
  Widget build(BuildContext context) {
    final store = context.read<DeckStore>();
    final game = gameById(deck.gameId);
    final view = store.viewOf(deck);
    final issues = game.validate(view);
    final errors = issues.where((i) => i.level == IssueLevel.error).length;
    final warnings = issues.length - errors;

    final (statusColor, statusLabel) = errors > 0
        ? (AppColors.danger, '$errors rule ${errors == 1 ? 'issue' : 'issues'}')
        : warnings > 0
        ? (AppColors.warning, '$warnings ${warnings == 1 ? 'note' : 'notes'}')
        : (AppColors.success, 'Legal');

    return Panel(
      accent: accentColor(deck.accent),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => DeckScreen(deckId: deck.id)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (deck.favorite)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.star, size: 16, color: AppColors.warning),
                ),
              Expanded(
                child: Text(
                  deck.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${game.shortName} · ${view.format.name}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          if (deck.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                deck.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textFaint,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final zoneId in view.format.zoneIds)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _CountPill(
                    label: game.zone(zoneId)?.shortName ?? zoneId,
                    count: view.zoneCount(zoneId),
                    goal: view.format.targets[zoneId]?.goal,
                  ),
                ),
              const Spacer(),
              Text(
                statusLabel,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.label, required this.count, this.goal});

  final String label;
  final int count;
  final int? goal;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: AppColors.textFaint,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            goal == null ? '$count' : '$count/$goal',
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
