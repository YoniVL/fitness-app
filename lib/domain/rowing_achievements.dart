/// Achievements for the rowing segment.
///
/// The catalogue is data-driven: every metric is a *ladder* of rungs
/// ([_ladder]) plus a handful of one-off badges. Adding a rung is one number in
/// a list; adding a badge is one list entry. The ladders top out at multi-year
/// targets so a normal rower always has a next goal — the evaluation engine
/// ([earnedAchievements]) never changes.
library;

enum AchievementCategory { afstand, tijd, volume, reeks, tempo, ftp, ontdekking }

extension AchievementCategoryLabel on AchievementCategory {
  String get label => switch (this) {
        AchievementCategory.afstand => 'Afstand',
        AchievementCategory.tijd => 'Tijd',
        AchievementCategory.volume => 'Volume',
        AchievementCategory.reeks => 'Reeksen',
        AchievementCategory.tempo => 'Tempo',
        AchievementCategory.ftp => 'FTP',
        AchievementCategory.ontdekking => 'Ontdekkingen',
      };
}

/// Everything the catalogue needs, from one pass over the finished rowing
/// sessions. Built by `RowingRepository.achievementStats` (+ the FTP fields
/// merged in by the provider).
class AchievementStats {
  const AchievementStats({
    this.totalDistanceM = 0,
    this.totalDurationSeconds = 0,
    this.sessionCount = 0,
    this.longestSessionM = 0,
    this.longestSessionSeconds = 0,
    this.bestAvgSplitSeconds,
    this.currentWeekStreak = 0,
    this.longestWeekStreak = 0,
    this.currentDayStreak = 0,
    this.longestDayStreak = 0,
    this.sessionKinds = const {},
    this.monthsSinceFirst = 0,
    this.best2kSeconds,
    this.best5kSeconds,
    this.best500mSeconds,
    this.currentFtpW,
    this.ftpTestCount = 0,
    this.didRampTest = false,
    this.rowedWeekendDay = false,
    this.earliestStartHour,
    this.latestStartHour,
    this.hadComeback = false,
  });

  final double totalDistanceM;
  final int totalDurationSeconds;
  final int sessionCount;
  final double longestSessionM;
  final int longestSessionSeconds;

  /// Fastest full-session average split (s/500 m) over a session of ≥ 1 000 m.
  final double? bestAvgSplitSeconds;

  final int currentWeekStreak;
  final int longestWeekStreak;
  final int currentDayStreak;
  final int longestDayStreak;

  /// Distinct `rowing_sessions.kind` values seen (RowSessionType names, `ftp_*`).
  final Set<String> sessionKinds;

  final int monthsSinceFirst;

  final int? best2kSeconds;
  final int? best5kSeconds;
  final int? best500mSeconds;

  final double? currentFtpW;
  final int ftpTestCount;
  final bool didRampTest;

  final bool rowedWeekendDay;
  final int? earliestStartHour;
  final int? latestStartHour;

  /// Rowed again after a gap of ≥ 30 days.
  final bool hadComeback;

  AchievementStats withFtp({double? currentFtpW, int? ftpTestCount, bool? didRampTest}) =>
      AchievementStats(
        totalDistanceM: totalDistanceM,
        totalDurationSeconds: totalDurationSeconds,
        sessionCount: sessionCount,
        longestSessionM: longestSessionM,
        longestSessionSeconds: longestSessionSeconds,
        bestAvgSplitSeconds: bestAvgSplitSeconds,
        currentWeekStreak: currentWeekStreak,
        longestWeekStreak: longestWeekStreak,
        currentDayStreak: currentDayStreak,
        longestDayStreak: longestDayStreak,
        sessionKinds: sessionKinds,
        monthsSinceFirst: monthsSinceFirst,
        best2kSeconds: best2kSeconds,
        best5kSeconds: best5kSeconds,
        best500mSeconds: best500mSeconds,
        currentFtpW: currentFtpW ?? this.currentFtpW,
        ftpTestCount: ftpTestCount ?? this.ftpTestCount,
        didRampTest: didRampTest ?? this.didRampTest,
        rowedWeekendDay: rowedWeekendDay,
        earliestStartHour: earliestStartHour,
        latestStartHour: latestStartHour,
        hadComeback: hadComeback,
      );
}

/// Where an achievement stands: the reached value, the rung's threshold, and a
/// unit for the progress label.
typedef AchievementProgress = ({num current, num target, String unit});

class RowingAchievement {
  const RowingAchievement({
    required this.id,
    required this.category,
    required this.title,
    required this.description,
    required this.progressFor,
    this.lowerIsBetter = false,
  });

  final String id;
  final AchievementCategory category;
  final String title;
  final String description;

  /// True for time targets where a *smaller* number is the achievement
  /// (fastest 2k, fastest 500 m).
  final bool lowerIsBetter;

  final AchievementProgress Function(AchievementStats) progressFor;

  /// The `idPrefix` this achievement's ladder shares, e.g. `afstand.totaal`.
  String get ladderKey => id.contains('.tier.') ? id.split('.tier.').first : id;

  bool unlockedBy(AchievementStats s) {
    final p = progressFor(s);
    if (lowerIsBetter) return p.current > 0 && p.current <= p.target;
    return p.current >= p.target;
  }
}

List<RowingAchievement> _ladder({
  required String idPrefix,
  required AchievementCategory category,
  required String Function(num tier) titleFor,
  required String Function(num tier) descriptionFor,
  required List<num> tiers,
  required num Function(AchievementStats) value,
  required String unit,
  bool lowerIsBetter = false,
}) =>
    [
      for (final t in tiers)
        RowingAchievement(
          id: '$idPrefix.tier.$t',
          category: category,
          title: titleFor(t),
          description: descriptionFor(t),
          lowerIsBetter: lowerIsBetter,
          progressFor: (s) => (current: value(s), target: t, unit: unit),
        ),
    ];

String _hms(num seconds) {
  final s = seconds.round();
  final m = s ~/ 60;
  final r = (s % 60).toString().padLeft(2, '0');
  return '$m:$r';
}

/// Training styles that count toward the "alleskunner" badge — the ones a
/// generated plan actually rotates through.
const _allRoundKinds = <String>{
  'endurance',
  'drempel',
  'intervalKort',
  'intervalLang',
  'piramide',
  'techniek',
};

RowingAchievement _oneOff(
  String id,
  String title,
  String description,
  bool Function(AchievementStats) done,
) =>
    RowingAchievement(
      id: 'ontdekking.$id',
      category: AchievementCategory.ontdekking,
      title: title,
      description: description,
      progressFor: (s) => (current: done(s) ? 1 : 0, target: 1, unit: ''),
    );

final List<RowingAchievement> rowingAchievements = [
  ..._ladder(
    idPrefix: 'afstand.totaal',
    category: AchievementCategory.afstand,
    tiers: const [10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000],
    titleFor: (t) => 'In totaal $t km',
    descriptionFor: (t) => 'Alle roeisessies samen $t km.',
    value: (s) => s.totalDistanceM / 1000,
    unit: 'km',
  ),
  ..._ladder(
    idPrefix: 'afstand.sessie',
    category: AchievementCategory.afstand,
    tiers: const [2, 5, 10, 21.097, 42.195, 50, 100],
    titleFor: (t) => switch (t) {
      21.097 => 'Halve marathon',
      42.195 => 'Marathon',
      _ => '$t km in één keer',
    },
    descriptionFor: (t) => switch (t) {
      21.097 => '21,097 km in één sessie.',
      42.195 => '42,195 km in één sessie.',
      _ => '$t km in één aaneengesloten sessie.',
    },
    value: (s) => s.longestSessionM / 1000,
    unit: 'km',
  ),
  ..._ladder(
    idPrefix: 'tijd.totaal',
    category: AchievementCategory.tijd,
    tiers: const [1, 5, 10, 25, 50, 100, 250, 500, 1000],
    titleFor: (t) => 'In totaal $t uur op de trainer',
    descriptionFor: (t) => 'Alle roeitijd samen $t uur.',
    value: (s) => s.totalDurationSeconds / 3600,
    unit: 'u',
  ),
  ..._ladder(
    idPrefix: 'tijd.sessie',
    category: AchievementCategory.tijd,
    tiers: const [20, 30, 45, 60, 90, 120, 180],
    titleFor: (t) => '$t minuten aaneen',
    descriptionFor: (t) => 'Eén sessie van minstens $t minuten.',
    value: (s) => s.longestSessionSeconds / 60,
    unit: 'min',
  ),
  ..._ladder(
    idPrefix: 'volume.sessies',
    category: AchievementCategory.volume,
    tiers: const [1, 10, 25, 50, 100, 250, 500, 1000, 2500],
    titleFor: (t) => t == 1 ? 'Eerste roeisessie' : '$t roeisessies',
    descriptionFor: (t) =>
        t == 1 ? 'Je eerste sessie gelogd.' : '$t afgeronde roeisessies.',
    value: (s) => s.sessionCount,
    unit: '',
  ),
  ..._ladder(
    idPrefix: 'reeks.weken',
    category: AchievementCategory.reeks,
    tiers: const [2, 4, 8, 12, 26, 52, 104],
    titleFor: (t) => '$t weken op rij',
    descriptionFor: (t) => '$t opeenvolgende weken met een roeisessie.',
    value: (s) => s.longestWeekStreak,
    unit: 'wk',
  ),
  ..._ladder(
    idPrefix: 'reeks.dagen',
    category: AchievementCategory.reeks,
    tiers: const [3, 7, 14, 30, 60, 100, 365],
    titleFor: (t) => '$t dagen op rij',
    descriptionFor: (t) => '$t opeenvolgende dagen geroeid.',
    value: (s) => s.longestDayStreak,
    unit: 'd',
  ),
  ..._ladder(
    idPrefix: 'reeks.maanden',
    category: AchievementCategory.reeks,
    tiers: const [1, 3, 6, 12, 24, 36, 60],
    titleFor: (t) => t == 1 ? 'Een maand onderweg' : '$t maanden onderweg',
    descriptionFor: (t) => 'Je roeit al $t maanden (sinds je eerste sessie).',
    value: (s) => s.monthsSinceFirst,
    unit: 'mnd',
  ),
  ..._ladder(
    idPrefix: 'tempo.2k',
    category: AchievementCategory.tempo,
    tiers: const [480, 465, 450, 435, 420, 405, 390],
    titleFor: (t) => '2 km onder ${_hms(t)}',
    descriptionFor: (t) => 'Een 2 km-test in minder dan ${_hms(t)}.',
    value: (s) => s.best2kSeconds ?? 0,
    unit: 's',
    lowerIsBetter: true,
  ),
  ..._ladder(
    idPrefix: 'tempo.500',
    category: AchievementCategory.tempo,
    tiers: const [110, 105, 100, 95, 90],
    titleFor: (t) => '500 m onder ${_hms(t)}',
    descriptionFor: (t) => 'Een 500 m-test in minder dan ${_hms(t)}.',
    value: (s) => s.best500mSeconds ?? 0,
    unit: 's',
    lowerIsBetter: true,
  ),
  ..._ladder(
    idPrefix: 'ftp.watt',
    category: AchievementCategory.ftp,
    tiers: const [1, 150, 175, 200, 225, 250, 275, 300],
    titleFor: (t) => t == 1 ? 'FTP ingesteld' : 'FTP van $t W',
    descriptionFor: (t) =>
        t == 1 ? 'Je eerste FTP bepaald.' : 'Een FTP van minstens $t watt.',
    value: (s) => s.currentFtpW ?? 0,
    unit: 'W',
  ),
  _oneOff('alleskunner', 'Alleskunner',
      'Elke trainingsvorm minstens één keer gedaan.',
      (s) => _allRoundKinds.every(s.sessionKinds.contains)),
  _oneOff('ftp_test', 'Getest', 'Je eerste FTP-test gedaan.',
      (s) => s.ftpTestCount >= 1),
  _oneOff('ramp', 'Tot het gaatje', 'Een ramptest volgehouden.',
      (s) => s.didRampTest),
  _oneOff('benchmark', 'De klok rond', 'Een getimede test geroeid.',
      (s) => s.best2kSeconds != null || s.best5kSeconds != null || s.best500mSeconds != null),
  _oneOff('weekend', 'Weekendkrijger', 'Op een zaterdag of zondag geroeid.',
      (s) => s.rowedWeekendDay),
  _oneOff('vroege_vogel', 'Vroege vogel', 'Een sessie vóór 7:00 gestart.',
      (s) => (s.earliestStartHour ?? 99) < 7),
  _oneOff('nachtuil', 'Nachtuil', 'Een sessie na 22:00 gestart.',
      (s) => (s.latestStartHour ?? -1) >= 22),
  _oneOff('comeback', 'Terug van weggeweest',
      'Opnieuw geroeid na 30 dagen stilte.', (s) => s.hadComeback),
];

/// The ids of every achievement whose threshold [s] meets.
Set<String> earnedAchievements(AchievementStats s) => {
      for (final a in rowingAchievements)
        if (a.unlockedBy(s)) a.id,
    };

/// For a ladder [ladderKey]: the highest rung reached and the next one to chase.
({RowingAchievement? reached, RowingAchievement? next}) ladderState(
  String ladderKey,
  Set<String> earnedIds,
) {
  final rungs =
      rowingAchievements.where((a) => a.ladderKey == ladderKey).toList();
  RowingAchievement? reached;
  RowingAchievement? next;
  for (final r in rungs) {
    if (earnedIds.contains(r.id)) {
      reached = r;
    } else {
      next = r;
      break;
    }
  }
  return (reached: reached, next: next);
}

/// The distinct ladder keys, in catalogue order.
List<String> get ladderKeys {
  final seen = <String>{};
  final out = <String>[];
  for (final a in rowingAchievements) {
    if (a.category == AchievementCategory.ontdekking) continue;
    if (seen.add(a.ladderKey)) out.add(a.ladderKey);
  }
  return out;
}

// --- pure streak helpers (used by RowingRepository.achievementStats) --------

DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime _mondayOf(DateTime d) =>
    _dayOf(d).subtract(Duration(days: d.weekday - 1));

/// Longest run of consecutive calendar days present in [days].
int longestDayStreak(Iterable<DateTime> days) =>
    _longestRun(days.map(_dayOf).toSet(), const Duration(days: 1));

/// Run of consecutive days ending today or yesterday (else 0).
int currentDayStreak(Iterable<DateTime> days, {DateTime? now}) =>
    _currentRun(days.map(_dayOf).toSet(), const Duration(days: 1),
        _dayOf(now ?? DateTime.now()));

/// Longest run of consecutive ISO weeks (Monday-keyed) present in [days].
int longestWeekStreak(Iterable<DateTime> days) =>
    _longestRun(days.map(_mondayOf).toSet(), const Duration(days: 7));

int currentWeekStreak(Iterable<DateTime> days, {DateTime? now}) =>
    _currentRun(days.map(_mondayOf).toSet(), const Duration(days: 7),
        _mondayOf(now ?? DateTime.now()));

int _longestRun(Set<DateTime> points, Duration step) {
  if (points.isEmpty) return 0;
  final sorted = points.toList()..sort();
  var best = 1;
  var run = 1;
  for (var i = 1; i < sorted.length; i++) {
    if (sorted[i].difference(sorted[i - 1]) == step) {
      run++;
      if (run > best) best = run;
    } else {
      run = 1;
    }
  }
  return best;
}

int _currentRun(Set<DateTime> points, Duration step, DateTime anchor) {
  if (points.isEmpty) return 0;
  var cursor = anchor;
  if (!points.contains(cursor)) cursor = cursor.subtract(step);
  var run = 0;
  while (points.contains(cursor)) {
    run++;
    cursor = cursor.subtract(step);
  }
  return run;
}
