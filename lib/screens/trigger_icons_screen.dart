import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../games/vanguard/vanguard_data.dart';
import '../games/vanguard/vanguard_rules.dart';
import '../models/card_definition.dart';
import '../store/deck_store.dart';
import '../theme.dart';
import '../widgets/card_image.dart';
import '../widgets/option_picker.dart';

/// Sets the trigger icon on every trigger unit in a deck, in one pass.
///
/// The card database records that a card is a trigger unit but not which
/// trigger it is, so the answer has to come from the user. Asking for it one
/// card at a time through the card editor is fine for a card typed in by hand
/// and tedious for a deck of sixteen that arrived from an import, which is
/// what this is for.
class TriggerIconsScreen extends StatefulWidget {
  const TriggerIconsScreen({super.key, required this.deckId});

  final String deckId;

  @override
  State<TriggerIconsScreen> createState() => _TriggerIconsScreenState();
}

class _TriggerIconsScreenState extends State<TriggerIconsScreen> {
  /// The order rows are shown in, fixed on the way in.
  ///
  /// Unanswered cards come first, because they are the reason for opening the
  /// screen -- but the order is settled once and then left alone. Re-sorting
  /// as answers arrive would move the next row out from under the finger that
  /// just tapped.
  List<String>? _order;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DeckStore>();
    final deck = store.deckById(widget.deckId);
    if (deck == null) {
      return const Scaffold(body: Center(child: Text('Deck not found')));
    }
    final view = store.viewOf(deck);

    // One row per distinct card, however many copies the deck holds.
    final cards = <String, CardDefinition>{};
    for (final item in view.items) {
      if (isTrigger(item.card)) cards[item.card.id] = item.card;
    }

    if (_order == null) {
      final sorted = cards.values.toList()
        ..sort((a, b) {
          final left = a.attribute('trigger') == null ? 0 : 1;
          final right = b.attribute('trigger') == null ? 0 : 1;
          return left != right
              ? left - right
              : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      _order = [for (final card in sorted) card.id];
    }
    final rows = [
      for (final id in _order!)
        if (cards[id] != null) cards[id]!,
    ];
    final remaining = rows
        .where((card) => card.attribute('trigger') == null)
        .length;

    return Scaffold(
      appBar: AppBar(title: const Text('Trigger icons')),
      body: rows.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'This deck has no trigger units yet.',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Text(
                  remaining == 0
                      ? 'Every trigger unit in this deck is set. The heal and '
                            'over limits are being checked.'
                      : 'The card database knows these are trigger units but '
                            'not which trigger, so it cannot check the heal '
                            'and over limits until you say. Answers are '
                            'remembered for these cards in every deck.',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 20),
                for (final card in rows)
                  _TriggerRow(
                    card: card,
                    onChanged: (value) => store.saveCard(
                      id: card.id,
                      gameId: card.gameId,
                      name: card.name,
                      attributes: {...card.attributes, 'trigger': value},
                    ),
                  ),
              ],
            ),
      bottomNavigationBar: rows.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    remaining == 0
                        ? 'Done'
                        : '$remaining still to set — done for now',
                  ),
                ),
              ),
            ),
    );
  }
}

class _TriggerRow extends StatelessWidget {
  const _TriggerRow({required this.card, required this.onChanged});

  final CardDefinition card;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final value = card.attribute('trigger');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value == null
              ? AppColors.warning.withValues(alpha: 0.4)
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CardImage(url: card.attribute('imageUrl'), width: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  card.name,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          OptionPicker(
            options: triggerOptions,
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
