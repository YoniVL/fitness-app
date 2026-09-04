import 'package:flutter/material.dart';

import '../../../domain/rowing_achievements.dart';
import '../../../ui/spacing.dart';
import 'achievement_badge.dart';

/// Shows a celebratory bottom sheet for the [newlyUnlocked] achievements.
/// No-op when the list is empty.
Future<void> showAchievementsUnlockedSheet(
  BuildContext context,
  List<RowingAchievement> newlyUnlocked,
) {
  if (newlyUnlocked.isEmpty) return Future.value();
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final theme = Theme.of(context);
      final multiple = newlyUnlocked.length > 1;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                multiple ? 'Nieuwe prestaties!' : 'Nieuwe prestatie!',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              Gap.l,
              for (final a in newlyUnlocked)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      AchievementBadge(achievement: a, unlocked: true),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.title,
                                style: theme.textTheme.titleMedium),
                            Text(a.description,
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color:
                                        theme.colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              Gap.l,
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Top!'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
