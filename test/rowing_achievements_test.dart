import 'package:fitnesstracker/domain/rowing_achievements.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('catalogue', () {
    test('ladders generate rungs with strictly increasing targets', () {
      for (final key in ladderKeys) {
        final rungs =
            rowingAchievements.where((a) => a.ladderKey == key).toList();
        expect(rungs.length, greaterThan(2), reason: key);
        for (var i = 1; i < rungs.length; i++) {
          final a = rungs[i - 1].progressFor(const AchievementStats()).target;
          final b = rungs[i].progressFor(const AchievementStats()).target;
          // lowerIsBetter ladders get harder as the target shrinks.
          if (rungs[i].lowerIsBetter) {
            expect(b, lessThan(a), reason: '$key rung $i');
          } else {
            expect(b, greaterThan(a), reason: '$key rung $i');
          }
        }
      }
    });

    test('ids are unique', () {
      final ids = rowingAchievements.map((a) => a.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('the top rungs are far out of reach for a fresh tracker', () {
      final earned = earnedAchievements(const AchievementStats());
      expect(earned, isEmpty);
      // A committed year (say 1 200 km, 200 sessions, 40 weeks) still leaves the
      // ceilings unearned — no "everything done" state.
      final heavy = const AchievementStats(
        totalDistanceM: 1200000,
        totalDurationSeconds: 300 * 3600,
        sessionCount: 200,
        longestWeekStreak: 40,
      );
      final e = earnedAchievements(heavy);
      expect(e.contains('afstand.totaal.tier.10000'), isFalse);
      expect(e.contains('volume.sessies.tier.2500'), isFalse);
      expect(e.contains('reeks.weken.tier.104'), isFalse);
    });
  });

  group('earnedAchievements', () {
    test('total distance ladder unlocks up to the reached rung', () {
      final e = earnedAchievements(const AchievementStats(totalDistanceM: 63000));
      expect(e, contains('afstand.totaal.tier.10'));
      expect(e, contains('afstand.totaal.tier.50'));
      expect(e, isNot(contains('afstand.totaal.tier.100')));
    });

    test('lowerIsBetter: no 2k time means nothing unlocked', () {
      final e = earnedAchievements(const AchievementStats());
      expect(e.where((id) => id.startsWith('tempo.2k')), isEmpty);
    });

    test('lowerIsBetter: a fast 2k unlocks the slower thresholds', () {
      final e =
          earnedAchievements(const AchievementStats(best2kSeconds: 452)); // 7:32
      expect(e, contains('tempo.2k.tier.480')); // sub 8:00
      expect(e, contains('tempo.2k.tier.465')); // sub 7:45
      expect(e, isNot(contains('tempo.2k.tier.450'))); // sub 7:30 missed
    });

    test('one-off badges', () {
      expect(
          earnedAchievements(const AchievementStats(rowedWeekendDay: true)),
          contains('ontdekking.weekend'));
      expect(
          earnedAchievements(const AchievementStats(earliestStartHour: 6)),
          contains('ontdekking.vroege_vogel'));
      expect(
          earnedAchievements(const AchievementStats(
              sessionKinds: {
                'endurance',
                'drempel',
                'intervalKort',
                'intervalLang',
                'piramide',
                'techniek'
              })),
          contains('ontdekking.alleskunner'));
    });

    test('first FTP rung unlocks at any watt value', () {
      expect(earnedAchievements(const AchievementStats(currentFtpW: 130)),
          contains('ftp.watt.tier.1'));
      expect(earnedAchievements(const AchievementStats(currentFtpW: 130)),
          isNot(contains('ftp.watt.tier.150')));
    });
  });

  group('ladderState', () {
    test('reports the reached rung and the next one', () {
      final earned = earnedAchievements(const AchievementStats(sessionCount: 30));
      final st = ladderState('volume.sessies', earned);
      expect(st.reached!.id, 'volume.sessies.tier.25');
      expect(st.next!.id, 'volume.sessies.tier.50');
    });

    test('no rung reached yet → reached null, next is the first', () {
      final st = ladderState('volume.sessies', const {});
      expect(st.reached, isNull);
      expect(st.next!.id, 'volume.sessies.tier.1');
    });
  });

  group('streak helpers', () {
    test('longestDayStreak finds the longest consecutive run', () {
      final days = [
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 2),
        DateTime(2026, 1, 3),
        DateTime(2026, 1, 3, 18), // same day, deduped
        DateTime(2026, 1, 6),
        DateTime(2026, 1, 7),
      ];
      expect(longestDayStreak(days), 3);
    });

    test('currentDayStreak counts back from today', () {
      final now = DateTime(2026, 1, 10, 9);
      final days = [
        DateTime(2026, 1, 8),
        DateTime(2026, 1, 9),
        DateTime(2026, 1, 10),
      ];
      expect(currentDayStreak(days, now: now), 3);
      expect(currentDayStreak([DateTime(2026, 1, 5)], now: now), 0);
    });

    test('week streak keys by Monday', () {
      final days = [
        DateTime(2026, 1, 5), // wk A (Mon)
        DateTime(2026, 1, 8), // wk A
        DateTime(2026, 1, 13), // wk B
        DateTime(2026, 1, 27), // wk D (skips C)
      ];
      expect(longestWeekStreak(days), 2);
    });
  });
}
