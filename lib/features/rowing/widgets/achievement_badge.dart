import 'package:flutter/material.dart';

import '../../../domain/rowing_achievements.dart';

/// Icon for an achievement, by category.
IconData achievementIcon(AchievementCategory c) => switch (c) {
      AchievementCategory.afstand => Icons.route_outlined,
      AchievementCategory.tijd => Icons.timer_outlined,
      AchievementCategory.volume => Icons.repeat_rounded,
      AchievementCategory.reeks => Icons.local_fire_department_outlined,
      AchievementCategory.tempo => Icons.speed_outlined,
      AchievementCategory.ftp => Icons.bolt_outlined,
      AchievementCategory.ontdekking => Icons.explore_outlined,
    };

/// A round badge medallion — filled when [unlocked], greyed otherwise.
class AchievementBadge extends StatelessWidget {
  const AchievementBadge({
    super.key,
    required this.achievement,
    required this.unlocked,
    this.size = 44,
  });

  final RowingAchievement achievement;
  final bool unlocked;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: unlocked
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
      ),
      child: Icon(
        achievementIcon(achievement.category),
        size: size * 0.5,
        color: unlocked
            ? scheme.onPrimaryContainer
            : scheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );
  }
}
