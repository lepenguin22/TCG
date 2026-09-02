import 'package:flutter/material.dart';

import '../games/game_definition.dart';
import '../theme.dart';
import 'option_picker.dart';

/// Asks for one card attribute the catalog could not supply.
///
/// Vanguard's catalog knows a card is a trigger unit but not which trigger it
/// is, so the app asks once, the first time the card is used, and remembers the
/// answer in the card library.
Future<String?> promptForField(
  BuildContext context, {
  required CardField field,
  required String cardName,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cardName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Which ${field.label.toLowerCase()}? The card database does '
                  'not carry this, and the deck rules need it. You are only '
                  'asked once per card.',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                OptionPicker(
                  options: field.options,
                  value: null,
                  onChanged: (value) => Navigator.of(sheetContext).pop(value),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      );
    },
  );
}
