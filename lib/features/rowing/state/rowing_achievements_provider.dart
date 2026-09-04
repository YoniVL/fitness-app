import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/repositories/rowing_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../domain/rowing_achievements.dart';

/// The catalogue plus the user's stats and unlock dates.
typedef AchievementsView = ({
  AchievementStats stats,
  Set<String> earnedIds,
  Map<String, DateTime> unlockedAt,
});

class RowingAchievementsNotifier extends AsyncNotifier<AchievementsView> {
  SettingsRepository get _settings => ref.read(settingsRepositoryProvider);
  RowingRepository get _rowing => ref.read(rowingRepositoryProvider);

  @override
  Future<AchievementsView> build() async {
    final stats = await _fullStats();
    return (
      stats: stats,
      earnedIds: earnedAchievements(stats),
      unlockedAt: await _settings.rowingAchievementsUnlocked(),
    );
  }

  Future<AchievementStats> _fullStats() async {
    final base = await _rowing.achievementStats();
    return base.withFtp(currentFtpW: await _bestFtpWatts(_settings));
  }

  /// Re-evaluates after a session, persists any newly-earned achievements, and
  /// returns them for a celebration. Returns empty on the first-ever run (the
  /// silent history backfill).
  Future<List<RowingAchievement>> evaluateAndDiff() async {
    final stats = await _fullStats();
    final earned = earnedAchievements(stats);
    final stored = await _settings.rowingAchievementsUnlocked();
    final seeded = await _settings.rowingAchievementsSeeded();

    final now = DateTime.now();
    final fresh = <String, DateTime>{
      for (final id in earned)
        if (!stored.containsKey(id)) id: now,
    };
    if (fresh.isNotEmpty) await _settings.unlockRowingAchievements(fresh);
    ref.invalidateSelf();

    if (!seeded) {
      await _settings.markRowingAchievementsSeeded();
      return const [];
    }
    final byId = {for (final a in rowingAchievements) a.id: a};
    return [for (final id in fresh.keys) ?byId[id]];
  }
}

final rowingAchievementsProvider =
    AsyncNotifierProvider<RowingAchievementsNotifier, AchievementsView>(
        RowingAchievementsNotifier.new);

Future<double?> _bestFtpWatts(SettingsRepository settings) async {
  final history = await settings.ftpHistory();
  return history.fold<double?>(
      null, (m, f) => (m == null || f.watts > m) ? f.watts : m);
}

/// One-time silent backfill so `seeded` is set before any screen or
/// session-finish evaluates — then [RowingAchievementsNotifier.evaluateAndDiff]
/// is a pure delta. Safe (and cheap) to call on every launch.
Future<void> maybeBackfillRowingAchievements(AppDatabase db) async {
  final settings = SettingsRepository(db);
  if (await settings.rowingAchievementsSeeded()) return;
  final stats = (await RowingRepository(db).achievementStats())
      .withFtp(currentFtpW: await _bestFtpWatts(settings));
  final now = DateTime.now();
  await settings.unlockRowingAchievements(
      {for (final id in earnedAchievements(stats)) id: now});
  await settings.markRowingAchievementsSeeded();
}
