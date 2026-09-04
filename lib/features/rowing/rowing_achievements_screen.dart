import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/rowing_achievements.dart';
import '../../domain/rowing_format.dart';
import 'state/rowing_achievements_provider.dart';
import 'widgets/achievement_badge.dart';

class RowingAchievementsScreen extends ConsumerWidget {
  const RowingAchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(rowingAchievementsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Prestaties')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fout: $e')),
        data: (view) => _Body(view: view),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.view});
  final AchievementsView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final earned = view.earnedIds;
    final unlockedCount =
        rowingAchievements.where((a) => earned.contains(a.id)).length;

    final ladderCats = [
      AchievementCategory.afstand,
      AchievementCategory.tijd,
      AchievementCategory.volume,
      AchievementCategory.reeks,
      AchievementCategory.tempo,
      AchievementCategory.ftp,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Text('$unlockedCount van ${rowingAchievements.length} behaald',
            style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('Nieuwe stappen komen vanzelf terwijl je blijft roeien.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        for (final cat in ladderCats) ...[
          Text(cat.label, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final key in ladderKeys.where((k) => _catOf(k) == cat))
            _LadderCard(
              state: ladderState(key, earned),
              stats: view.stats,
              unlockedAt: view.unlockedAt,
            ),
          const SizedBox(height: 12),
        ],
        Text(AchievementCategory.ontdekking.label,
            style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final a in rowingAchievements
            .where((a) => a.category == AchievementCategory.ontdekking))
          _OneOffTile(
            achievement: a,
            unlocked: earned.contains(a.id),
            unlockedAt: view.unlockedAt[a.id],
          ),
      ],
    );
  }

  static AchievementCategory _catOf(String ladderKey) => rowingAchievements
      .firstWhere((a) => a.ladderKey == ladderKey)
      .category;
}

class _LadderCard extends StatelessWidget {
  const _LadderCard(
      {required this.state, required this.stats, required this.unlockedAt});
  final ({RowingAchievement? reached, RowingAchievement? next}) state;
  final AchievementStats stats;
  final Map<String, DateTime> unlockedAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final show = state.next ?? state.reached!;
    final done = state.next == null;
    final frac = done ? 1.0 : achievementFraction(state.next!, stats);
    final when = state.reached == null ? null : unlockedAt[state.reached!.id];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            AchievementBadge(
                achievement: show, unlocked: state.reached != null),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(show.title, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    done
                        ? 'Alles behaald in deze reeks'
                        : state.reached == null
                            ? show.description
                            : _reachedLine(state.reached!, when),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  if (!done) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                          value: frac, minHeight: 5),
                    ),
                    const SizedBox(height: 4),
                    Text(_progressLine(state.next!, stats),
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _reachedLine(RowingAchievement a, DateTime? when) {
    final d = when == null
        ? ''
        : ' · ${DateFormat('d MMM y', 'nl').format(when)}';
    return 'Behaald: ${a.title.toLowerCase()}$d';
  }
}

String _progressLine(RowingAchievement next, AchievementStats s) {
  final p = next.progressFor(s);
  if (next.lowerIsBetter) {
    final now = p.current <= 0 ? '–' : _hms(p.current);
    return 'nu $now · doel ${_hms(p.target)}';
  }
  return '${_fmt(p.current, p.unit)} / ${_fmt(p.target, p.unit)}'
      '${p.unit.isEmpty ? '' : ' ${p.unit}'}';
}

String _fmt(num v, String unit) => switch (unit) {
      'km' || 'u' => v.toStringAsFixed(v < 10 ? 1 : 0),
      _ => v.round().toString(),
    };

String _hms(num seconds) => hmsLabel(Duration(seconds: seconds.round()));

class _OneOffTile extends StatelessWidget {
  const _OneOffTile(
      {required this.achievement,
      required this.unlocked,
      required this.unlockedAt});
  final RowingAchievement achievement;
  final bool unlocked;
  final DateTime? unlockedAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading:
          AchievementBadge(achievement: achievement, unlocked: unlocked),
      title: Text(achievement.title),
      subtitle: Text(
        unlocked && unlockedAt != null
            ? 'Behaald · ${DateFormat('d MMM y', 'nl').format(unlockedAt!)}'
            : achievement.description,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}
