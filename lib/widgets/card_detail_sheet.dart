import 'package:flutter/material.dart';

import '../games/game_definition.dart';
import '../models/card_definition.dart';
import '../theme.dart';
import 'card_image.dart';

/// The full card: its image, what the deck builder knows about it, and its
/// printed abilities.
Future<void> showCardDetail(
  BuildContext context, {
  required GameDefinition game,
  required CardDefinition card,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) => _CardDetail(
        game: game,
        card: card,
        scrollController: scrollController,
        actionLabel: actionLabel,
        onAction: onAction == null
            ? null
            : () {
                Navigator.of(sheetContext).pop();
                onAction();
              },
      ),
    ),
  );
}

class _CardDetail extends StatelessWidget {
  const _CardDetail({
    required this.game,
    required this.card,
    required this.scrollController,
    this.actionLabel,
    this.onAction,
  });

  final GameDefinition game;
  final CardDefinition card;
  final ScrollController scrollController;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final badge = game.badgeOf(card);
    final effect = card.attribute('effect');
    final cardNo = card.attribute('cardNo');

    // Everything except the long text and the things already shown up top.
    final facts = <(String, String)>[];
    for (final field in game.cardFields) {
      if (field.key == 'effect' ||
          field.key == 'imageUrl' ||
          field.key == 'notes') {
        continue;
      }
      if (!field.isVisible(card.attributes)) continue;
      final value = card.attribute(field.key);
      if (value == null) continue;
      final label = field.options.isEmpty
          ? value
          : optionLabel(field.options, value) ?? value;
      facts.add((field.label, label));
    }

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Center(child: CardImage(url: card.attribute('imageUrl'), width: 200)),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                card.name,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
            ),
            if (badge != null)
              Container(
                margin: const EdgeInsets.only(left: 12, top: 2),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: badge.color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: badge.color.withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  badge.text,
                  style: TextStyle(
                    color: badge.color,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
          ],
        ),
        if (cardNo != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              cardNo,
              style: const TextStyle(color: AppColors.textFaint, fontSize: 12),
            ),
          ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (label, value) in facts)
              _Fact(label: label, value: value),
          ],
        ),
        if (effect != null) ...[
          const SizedBox(height: 20),
          const Text(
            'ABILITIES',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: SelectableText(
              effect,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),
        ],
        if (card.attribute('notes') != null) ...[
          const SizedBox(height: 20),
          const Text(
            'YOUR NOTES',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            card.attribute('notes')!,
            style: const TextStyle(
              color: AppColors.textFaint,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.add),
            label: Text(actionLabel!),
          ),
        ],
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: AppColors.textFaint,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
