import 'package:flutter/material.dart';

import '../games/game_definition.dart';
import '../models/card_definition.dart';
import '../theme.dart';
import 'card_image.dart';
import 'common.dart';

/// One card in a list: badge, name, generated subtitle, and either a quantity
/// stepper or a trailing widget.
class CardRow extends StatelessWidget {
  const CardRow({
    super.key,
    required this.game,
    required this.card,
    this.quantity,
    this.onTap,
    this.onIncrement,
    this.onDecrement,
    this.trailing,
  });

  final GameDefinition game;
  final CardDefinition card;
  final int? quantity;
  final VoidCallback? onTap;
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final badge = game.badgeOf(card);
    final subtitle = game.describeCard(card);
    final showStepper =
        quantity != null && onIncrement != null && onDecrement != null;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              CardImage(url: card.attribute('imageUrl'), width: 32),
              const SizedBox(width: 10),
              if (badge != null) ...[
                TagBadge(text: badge.text, color: badge.color),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textFaint,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (showStepper) ...[
                const SizedBox(width: 8),
                _Stepper(
                  quantity: quantity!,
                  cardName: card.name,
                  onIncrement: onIncrement!,
                  onDecrement: onDecrement!,
                ),
              ],
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.quantity,
    required this.cardName,
    required this.onIncrement,
    required this.onDecrement,
  });

  final int quantity;
  final String cardName;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepButton(
            icon: Icons.remove,
            tooltip: 'Remove one $cardName',
            onPressed: onDecrement,
          ),
          SizedBox(
            width: 24,
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _StepButton(
            icon: Icons.add,
            tooltip: 'Add one $cardName',
            onPressed: onIncrement,
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 16, color: AppColors.textMuted),
        ),
      ),
    );
  }
}
