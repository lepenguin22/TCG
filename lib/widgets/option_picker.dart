import 'package:flutter/material.dart';

import '../games/game_definition.dart';
import '../theme.dart';

/// A wrap of selectable chips, used for every `select` card field, the format
/// picker and the quick filters.
class OptionPicker extends StatelessWidget {
  const OptionPicker({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.allowClear = false,
    this.labelBuilder,
  });

  final List<FieldOption> options;
  final String? value;
  final ValueChanged<String> onChanged;

  /// Tapping the selected chip clears the value.
  final bool allowClear;
  final String Function(FieldOption option)? labelBuilder;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          OptionChip(
            label: labelBuilder?.call(option) ?? option.label,
            color: option.color,
            selected: value == option.value,
            onTap: () => onChanged(
              allowClear && value == option.value ? '' : option.value,
            ),
          ),
      ],
    );
  }
}

class OptionChip extends StatelessWidget {
  const OptionChip({
    super.key,
    required this.label,
    required this.selected,
    this.color,
    this.onTap,
  });

  final String label;
  final bool selected;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? AppColors.accent;
    return Material(
      color: selected ? tint.withValues(alpha: 0.14) : AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? tint : AppColors.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? tint : AppColors.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
