import 'package:flutter/material.dart';

import '../games/game_definition.dart';
import '../theme.dart';

/// The rules verdict for a deck: either a green "legal" line, or the list of
/// what is wrong with it.
class IssueList extends StatelessWidget {
  const IssueList({super.key, required this.issues});

  final List<ValidationIssue> issues;

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) {
      return _Wrapper(
        tint: AppColors.success,
        child: Row(
          children: const [
            Icon(Icons.check_circle, size: 18, color: AppColors.success),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Deck is legal for this format.',
                style: TextStyle(color: AppColors.success, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    final errors = issues.where((i) => i.level == IssueLevel.error);
    final warnings = issues.where((i) => i.level == IssueLevel.warning);
    final ordered = [...errors, ...warnings];

    return _Wrapper(
      tint: errors.isNotEmpty ? AppColors.danger : AppColors.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final issue in ordered)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    issue.level == IssueLevel.error
                        ? Icons.error
                        : Icons.warning_amber_rounded,
                    size: 16,
                    color: issue.level == IssueLevel.error
                        ? AppColors.danger
                        : AppColors.warning,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      issue.message,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Wrapper extends StatelessWidget {
  const _Wrapper({required this.tint, required this.child});

  final Color tint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tint.withValues(alpha: 0.35)),
      ),
      child: child,
    );
  }
}
