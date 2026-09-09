import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../games/game_definition.dart';
import '../games/games.dart';
import '../games/vanguard/vanguard_rules.dart';
import '../models/card_definition.dart';
import '../store/deck_store.dart';
import '../theme.dart';
import '../utils/deck_cost.dart';
import '../utils/deck_text.dart';
import '../widgets/action_sheet.dart';
import '../widgets/card_detail_sheet.dart';
import '../widgets/card_row.dart';
import '../widgets/common.dart';
import '../widgets/issue_list.dart';
import 'add_cards_screen.dart';
import 'card_editor_screen.dart';
import 'deck_settings_screen.dart';
import 'deck_stats_screen.dart';
import 'playtest_setup_screen.dart';
import 'trigger_icons_screen.dart';

class DeckScreen extends StatefulWidget {
  const DeckScreen({super.key, required this.deckId});

  final String deckId;

  @override
  State<DeckScreen> createState() => _DeckScreenState();
}

class _DeckScreenState extends State<DeckScreen> {
  bool _showAllIssues = false;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DeckStore>();
    final deck = store.deckById(widget.deckId);

    if (deck == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Deck')),
        body: EmptyState(
          icon: Icons.help_outline,
          title: 'Deck not found',
          message: 'It may have been deleted.',
          action: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back to decks'),
          ),
        ),
      );
    }

    final game = gameById(deck.gameId);
    final view = store.viewOf(deck);
    final issues = game.validate(view);
    final cost = deckCostOf(view);
    final visibleIssues = _showAllIssues ? issues : issues.take(3).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(deck.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Playtest',
            icon: const Icon(Icons.play_circle_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PlaytestSetupScreen(deck: deck),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Breakdown',
            icon: const Icon(Icons.bar_chart),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => DeckStatsScreen(deckId: deck.id),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Deck actions',
            icon: const Icon(Icons.more_horiz),
            onPressed: () => _openMenu(game, view),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Panel(
            accent: accentColor(deck.accent),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${game.shortName} · ${view.format.name}',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (deck.description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      deck.description,
                      style: const TextStyle(
                        color: AppColors.textFaint,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (final zoneId in view.format.zoneIds)
                      Padding(
                        padding: const EdgeInsets.only(right: 24),
                        child: _ZoneCounter(
                          label: game.zone(zoneId)?.name ?? zoneId,
                          count: view.zoneCount(zoneId),
                          target: view.format.targets[zoneId],
                        ),
                      ),
                  ],
                ),
                // What the deck costs, once anything in it has been priced.
                // Nothing to say about a deck with no prices on it, so it
                // says nothing rather than showing a zero.
                if (!cost.isEmpty) ...[
                  const SizedBox(height: 12),
                  _DeckCostLine(cost: cost),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          IssueList(issues: visibleIssues),
          if (issues.length > 3)
            Center(
              child: TextButton(
                onPressed: () =>
                    setState(() => _showAllIssues = !_showAllIssues),
                child: Text(
                  _showAllIssues
                      ? 'Show fewer'
                      : 'Show all ${issues.length} issues',
                ),
              ),
            ),
          const SizedBox(height: 16),
          for (final zoneId in view.format.zoneIds)
            _ZoneSection(
              game: game,
              view: view,
              zoneId: zoneId,
              onCardTap: (item) => _openCardMenu(game, view, item, zoneId),
              onIncrement: (item) => store.setQuantity(
                deck.id,
                item.card.id,
                zoneId,
                item.entry.quantity + 1,
              ),
              onDecrement: (item) => store.setQuantity(
                deck.id,
                item.card.id,
                zoneId,
                item.entry.quantity - 1,
              ),
              onAdd: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      AddCardsScreen(deckId: deck.id, zoneId: zoneId),
                ),
              ),
            ),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => DeckStatsScreen(deckId: deck.id),
              ),
            ),
            icon: const Icon(Icons.bar_chart),
            label: const Text('Breakdown & curve'),
          ),
        ],
      ),
    );
  }

  Future<void> _openMenu(GameDefinition game, DeckView view) async {
    final store = context.read<DeckStore>();
    final deck = view.deck;
    await showActionSheet(
      context,
      title: deck.name,
      actions: [
        SheetAction(
          label: deck.favorite ? 'Unpin from top' : 'Pin to top',
          icon: deck.favorite ? Icons.star_border : Icons.star,
          onPressed: () => store.toggleFavorite(deck.id),
        ),
        // Only offered where it means something: another game may have no
        // trigger units at all.
        if (view.items.any((item) => isTrigger(item.card)))
          SheetAction(
            label: 'Set trigger icons',
            icon: Icons.bolt_outlined,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => TriggerIconsScreen(deckId: deck.id),
              ),
            ),
          ),
        SheetAction(
          label: 'Copy as text',
          icon: Icons.copy_outlined,
          onPressed: () => _copyAsText(game, view),
        ),
        SheetAction(
          label: 'Duplicate deck',
          icon: Icons.control_point_duplicate_outlined,
          onPressed: () {
            final copy = store.duplicateDeck(deck.id);
            if (copy != null && mounted) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute<void>(
                  builder: (_) => DeckScreen(deckId: copy.id),
                ),
              );
            }
          },
        ),
        SheetAction(
          label: 'Deck settings',
          icon: Icons.tune,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => DeckSettingsScreen(deckId: deck.id),
            ),
          ),
        ),
        SheetAction(
          label: 'Delete deck',
          icon: Icons.delete_outline,
          destructive: true,
          onPressed: _confirmDelete,
        ),
      ],
    );
  }

  Future<void> _copyAsText(GameDefinition game, DeckView view) async {
    await Clipboard.setData(ClipboardData(text: deckToText(game, view)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Decklist copied to the clipboard as text.'),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final store = context.read<DeckStore>();
    final deck = store.deckById(widget.deckId);
    if (deck == null) return;
    final ok = await confirm(
      context,
      title: 'Delete deck?',
      message: '"${deck.name}" will be removed. This cannot be undone.',
    );
    if (!ok || !mounted) return;
    store.deleteDeck(deck.id);
    if (mounted) Navigator.of(context).pop();
  }

  /// The two boxes: what a copy costs and where to buy it.
  ///
  /// Kept on the card rather than on the deck entry, so a card in two decks
  /// is priced once. Nothing checks or fetches these -- they are whatever you
  /// last wrote down.
  Future<void> _editBuying(CardDefinition card) async {
    final store = context.read<DeckStore>();
    final filled = await showDialog<(String, String)>(
      context: context,
      builder: (_) => _BuyingDialog(card: card),
    );
    if (filled == null) return;
    final attributes = Map<String, String>.from(card.attributes);
    for (final entry in {'price': filled.$1, 'store': filled.$2}.entries) {
      final value = entry.value.trim();
      // Cleared rather than left as an empty string, so a card you have not
      // priced has no price rather than a blank one.
      if (value.isEmpty) {
        attributes.remove(entry.key);
      } else {
        attributes[entry.key] = value;
      }
    }
    store.saveCard(
      id: card.id,
      gameId: card.gameId,
      name: card.name,
      attributes: attributes,
    );
  }

  Future<void> _openCardMenu(
    GameDefinition game,
    DeckView view,
    DeckItem item,
    String zoneId,
  ) async {
    final store = context.read<DeckStore>();
    final otherZones = view.format.zoneIds.where((z) => z != zoneId);
    await showActionSheet(
      context,
      title: item.card.name,
      actions: [
        SheetAction(
          label: 'View card',
          icon: Icons.image_outlined,
          onPressed: () => showCardDetail(context, game: game, card: item.card),
        ),
        SheetAction(
          label: 'Edit card details',
          icon: Icons.edit_outlined,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CardEditorScreen(
                gameId: view.deck.gameId,
                cardId: item.card.id,
              ),
            ),
          ),
        ),
        SheetAction(
          label: 'Price and store',
          icon: Icons.sell_outlined,
          onPressed: () => _editBuying(item.card),
        ),
        for (final target in otherZones)
          SheetAction(
            label: 'Move to ${game.zone(target)?.name ?? target}',
            icon: Icons.swap_horiz,
            onPressed: () =>
                store.moveEntry(view.deck.id, item.card.id, zoneId, target),
          ),
        SheetAction(
          label: 'Remove from deck',
          icon: Icons.delete_outline,
          destructive: true,
          onPressed: () =>
              store.setQuantity(view.deck.id, item.card.id, zoneId, 0),
        ),
      ],
    );
  }
}

/// The price-and-store box, which owns its two fields.
class _BuyingDialog extends StatefulWidget {
  const _BuyingDialog({required this.card});

  final CardDefinition card;

  @override
  State<_BuyingDialog> createState() => _BuyingDialogState();
}

class _BuyingDialogState extends State<_BuyingDialog> {
  late final _price = TextEditingController(
    text: widget.card.attribute('price') ?? '',
  );
  late final _store = TextEditingController(
    text: widget.card.attribute('store') ?? '',
  );

  @override
  void dispose() {
    _price.dispose();
    _store.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).pop((_price.text, _store.text));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(widget.card.name),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _price,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Price',
              hintText: 'What one copy costs',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _store,
            decoration: const InputDecoration(
              labelText: 'Store',
              hintText: 'Where you can buy it',
            ),
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

/// The deck's cost, and how much of the deck that number covers.
class _DeckCostLine extends StatelessWidget {
  const _DeckCostLine({required this.cost});

  final DeckCost cost;

  @override
  Widget build(BuildContext context) {
    // What the total leaves out matters as much as the total: a number that
    // covers half the deck reads as the price of the deck unless it says so.
    final caveats = [
      if (cost.unpriced > 0)
        '${cost.unpriced} ${cost.unpriced == 1 ? 'card' : 'cards'} not priced',
      if (cost.mixedCurrency) 'prices in more than one currency',
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        const Text(
          'COST ',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        Text(
          cost.label,
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (caveats.isNotEmpty)
          Expanded(
            child: Text(
              '  ${caveats.join(', ')}',
              maxLines: 2,
              style: const TextStyle(color: AppColors.textFaint, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _ZoneCounter extends StatelessWidget {
  const _ZoneCounter({required this.label, required this.count, this.target});

  final String label;
  final int count;
  final ZoneTarget? target;

  @override
  Widget build(BuildContext context) {
    final goal = target?.goal;
    final onTrack = goal == null
        ? true
        : target?.exact != null
        ? count == goal
        : count <= goal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '$count',
              style: TextStyle(
                color: onTrack ? AppColors.text : AppColors.warning,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (goal != null)
              Text(
                ' / $goal',
                style: const TextStyle(
                  color: AppColors.textFaint,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
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
    );
  }
}

class _ZoneSection extends StatelessWidget {
  const _ZoneSection({
    required this.game,
    required this.view,
    required this.zoneId,
    required this.onCardTap,
    required this.onIncrement,
    required this.onDecrement,
    required this.onAdd,
  });

  final GameDefinition game;
  final DeckView view;
  final String zoneId;
  final void Function(DeckItem item) onCardTap;
  final void Function(DeckItem item) onIncrement;
  final void Function(DeckItem item) onDecrement;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final zone = game.zone(zoneId);
    final groups = game.groupZone(view, zoneId);
    final count = view.zoneCount(zoneId);
    final goal = view.format.targets[zoneId]?.goal;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            zone?.name ?? zoneId,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$count${goal == null ? '' : ' of $goal'} · ${zone?.description ?? ''}',
            style: const TextStyle(color: AppColors.textFaint, fontSize: 12),
          ),
          const SizedBox(height: 8),
          if (groups.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Text(
                'Nothing here yet.',
                style: TextStyle(
                  color: AppColors.textFaint,
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            for (final group in groups) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        group.title.toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    Text(
                      '${group.count}',
                      style: const TextStyle(
                        color: AppColors.textFaint,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              for (final item in group.rows)
                CardRow(
                  game: game,
                  card: item.card,
                  quantity: item.entry.quantity,
                  footnote: buyingLine(item.card),
                  onTap: () => onCardTap(item),
                  onIncrement: () => onIncrement(item),
                  onDecrement: () => onDecrement(item),
                ),
            ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: Text('Add to ${zone?.shortName ?? 'zone'}'),
          ),
        ],
      ),
    );
  }
}
