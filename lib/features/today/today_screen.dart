import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/home_shell.dart';
import '../../app/theme.dart';
import '../../data/repositories/exercise_repository.dart';
import '../../data/repositories/program_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/workout_session_repository.dart';
import '../../data/repositories/rowing_repository.dart';
import '../../domain/models/exercise.dart';
import '../../domain/models/program.dart';
import '../../domain/models/rowing_plan.dart';
import '../../domain/progression.dart';
import '../../domain/rowing_format.dart';
import '../../domain/rowing_ftp.dart';
import '../../ui/async_view.dart';
import '../../ui/spacing.dart';
import '../rowing/ble/connect_sheet.dart';
import '../rowing/log_rowing_sheet.dart';
import '../rowing/state/active_rowing_provider.dart';
import '../rowing/widgets/interval_profile.dart';
import '../rowing/widgets/target_pace.dart';
import '../strength/state/active_workout_provider.dart';

/// "3 blokken" / "1 blok".
String _blocks(int n) => n == 1 ? '1 blok' : '$n blokken';

/// Summary of a strength program day: the exercise rows plus the totals the
/// hero card's metric strip shows.
typedef DayPreview = ({
  List<(String name, String scheme)> rows,
  int exercises,
  int sets,
  int minutes,
});

/// (rows, totals) for a strength program day.
final _dayPreviewProvider =
    FutureProvider.family<DayPreview, int>((ref, dayId) async {
  final pes = await ref.watch(programRepositoryProvider).exercisesForDay(dayId);
  final names = await ref
      .watch(exerciseRepositoryProvider)
      .byIds(pes.map((e) => e.exerciseId));
  final rows = [
    for (final pe in pes)
      (
        names[pe.exerciseId]?.name ?? 'Oefening',
        '${pe.targetSets} × ${names[pe.exerciseId]?.formatReps(pe.targetReps) ?? pe.targetReps}'
      )
  ];
  final sets = pes.fold(0, (s, pe) => s + pe.targetSets);
  return (
    rows: rows,
    exercises: pes.length,
    sets: sets,
    minutes: (sets * 3.5).round(),
  );
});

/// (minutes, work-block count, segments) for a rowing program day.
final _rowDayInfoProvider = FutureProvider.family<
    (int minutes, int blocks, List<ProgramRowSegment> segs), int>((ref, dayId) async {
  final segs = await ref.watch(programRepositoryProvider).rowSegmentsForDay(dayId);
  const framing = {'Warming-up', 'Uitroeien'};
  final seconds = segs.fold(0, (s, seg) => s + seg.durationSeconds);
  final blocks = segs
      .where((s) => !s.isRest && !framing.contains(s.intensityLabel))
      .length;
  return ((seconds / 60).round(), blocks, segs);
});

/// Finished sessions of [discipline] in the current ISO week.
final _thisWeekCountProvider =
    FutureProvider.family<int, Discipline>((ref, discipline) async {
  final sessions = await ref.watch(recentSessionsProvider.future);
  final now = DateTime.now();
  final monday = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: now.weekday - 1));
  return sessions
      .where((s) =>
          s.session.discipline == discipline &&
          s.session.isFinished &&
          !s.session.startedAt.isBefore(monday))
      .length;
});

/// The days of the current ISO week that already carry a finished session of
/// [discipline] — used to fill the week strip.
final _trainedDaysProvider =
    FutureProvider.family<Set<int>, Discipline>((ref, discipline) async {
  final sessions = await ref.watch(recentSessionsProvider.future);
  final now = DateTime.now();
  final monday = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: now.weekday - 1));
  return {
    for (final s in sessions)
      if (s.session.discipline == discipline &&
          s.session.isFinished &&
          !s.session.startedAt.isBefore(monday))
        s.session.startedAt.weekday,
  };
});

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key, required this.discipline});

  final Discipline discipline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isRowing = discipline == Discipline.rowing;
    return Scaffold(
      appBar: AppBar(
        leading: const DisciplineSwitchButton(),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(isRowing ? 'Roeien' : 'Krachttraining'),
            Text(
              DateFormat('EEEE d MMMM', 'nl').format(DateTime.now()).toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: isRowing ? const _RowingToday() : const _StrengthToday(),
    );
  }
}

// --- Shared building blocks ---------------------------------------

/// A short all-caps micro-label — accent by default, muted when [muted].
class _Kicker extends StatelessWidget {
  const _Kicker(this.text, {this.muted = false});
  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: muted ? p.mute : p.accent,
            letterSpacing: 1.3,
            fontSize: 10,
          ),
    );
  }
}

/// One cell of a hero card's metric strip: a big tabular number with an
/// optional trailing unit, over an all-caps caption.
class _Metric extends StatelessWidget {
  const _Metric(this.value, this.caption, {this.unit, this.showRight = true});
  final String value;
  final String caption;
  final String? unit;
  final bool showRight;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        border: Border(
          right: showRight ? BorderSide(color: p.line) : BorderSide.none,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              text: value,
              style: AppTheme.numeric(size: 30, color: p.ink),
              children: [
                if (unit != null)
                  TextSpan(
                    text: unit,
                    style: AppTheme.numeric(size: 14, color: p.mute)
                        .copyWith(letterSpacing: 0),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(caption.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 9, letterSpacing: 1.1, color: p.mute)),
        ],
      ),
    );
  }
}

/// A full-width action button with the label flush left and a trailing icon —
/// the Modernist primary-button shape.
class _WideButton extends StatelessWidget {
  const _WideButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.filled = true,
    this.accentBorder = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool filled;
  final bool accentBorder;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final child = Row(
      children: [
        Expanded(child: Text(label.toUpperCase())),
        Icon(icon, size: 18),
      ],
    );
    if (filled) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(onPressed: onPressed, child: child),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: accentBorder
            ? OutlinedButton.styleFrom(
                side: BorderSide(color: p.accent, width: 2))
            : null,
        child: child,
      ),
    );
  }
}

/// The numbered "01 · name · 4 × 5" list inside a hero card.
class _ExerciseList extends StatelessWidget {
  const _ExerciseList(this.rows);
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: i == rows.length - 1
                    ? BorderSide.none
                    : BorderSide(color: p.line),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: Text((i + 1).toString().padLeft(2, '0'),
                      style: AppTheme.numeric(size: 11, color: p.mute)
                          .copyWith(letterSpacing: 0)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(rows[i].$1,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
                Text(rows[i].$2,
                    style: AppTheme.numeric(size: 12, color: p.mute)
                        .copyWith(letterSpacing: 0)),
              ],
            ),
          ),
      ],
    );
  }
}

// --- Strength -------------------------------------------------------

class _StrengthToday extends ConsumerWidget {
  const _StrengthToday();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeWorkoutProvider);
    final program = ref.watch(activeProgramProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await ref.read(activeWorkoutProvider.notifier).startEmpty();
          if (context.mounted) context.push('/workout/active');
        },
        tooltip: 'Losse training',
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(activeProgramProvider);
          ref.invalidate(activeWorkoutProvider);
          ref.invalidate(recentSessionsProvider);
        },
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const _WeekStrip(discipline: Discipline.strength),
            Padding(
              padding: Insets.screenList,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  active.viewOrNothing((s) => s == null || s.blocks.isEmpty
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ResumeCard(setCount: s.totalSets),
                        )),
                  program.view(
                    (p) => p == null
                        ? const _NoProgramCard()
                        : _ProgramDayCard(active: p),
                    loading: () => const LoadingBox(),
                    error: (e) => const ErrorBox(
                        message: 'Kon programma niet laden'),
                  ),
                  Gap.l,
                  const _WeekStats(discipline: Discipline.strength),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Rowing --------------------------------------------------------

class _RowingToday extends ConsumerWidget {
  const _RowingToday();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rowingProgram = ref.watch(activeRowingProgramProvider);
    final activeRowing = ref.watch(activeRowingProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(activeRowingProgramProvider);
        ref.invalidate(activeRowingProvider);
        ref.invalidate(recentSessionsProvider);
      },
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const _WeekStrip(discipline: Discipline.rowing),
          Padding(
            padding: Insets.screenList,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                activeRowing.viewOrNothing((s) => s == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Card(
                          child: ListTile(
                            leading: const Icon(Icons.rowing),
                            title: const Text('Roeisessie bezig'),
                            subtitle:
                                const Text('Hervat waar je gebleven was'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push('/rowing/active'),
                          ),
                        ),
                      )),
                rowingProgram.viewOrNothing((p) => p == null
                    ? const _NoRowingPlanCard()
                    : _RowingDayCard(active: p)),
                Gap.m,
                _FreeRowCard(
                  onStart: () async {
                    await ensureRowerConnected(context, ref);
                    if (!context.mounted) return;
                    await ref.read(activeRowingProvider.notifier).startFree();
                    if (context.mounted) context.push('/rowing/active');
                  },
                  onLog: () => showLogRowingSheet(context, ref),
                ),
                Gap.l,
                const _WeekStats(discipline: Discipline.rowing),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResumeCard extends StatelessWidget {
  const _ResumeCard({required this.setCount});
  final int setCount;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.play_circle_fill),
        title: const Text('Training bezig'),
        subtitle: Text('$setCount set(s) gelogd — hervat waar je gebleven was'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/workout/active'),
      ),
    );
  }
}

class _NoProgramCard extends StatelessWidget {
  const _NoProgramCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Kicker('Vandaag · Kracht'),
            Gap.s,
            Text('Nog geen programma gekozen',
                style: Theme.of(context).textTheme.titleLarge),
            Gap.s,
            const Text(
                'Kies een programma in de bibliotheek of stel er zelf een samen.'),
            Gap.m,
            _WideButton(
              label: 'Naar de bibliotheek',
              icon: Icons.arrow_forward,
              onPressed: () => context.go('/strength/library'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoRowingPlanCard extends StatelessWidget {
  const _NoRowingPlanCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Kicker('Vandaag · Roeien'),
            Gap.s,
            Text('Nog geen roeiplan gekozen',
                style: Theme.of(context).textTheme.titleLarge),
            Gap.s,
            const Text(
                'Kies een plan in de bibliotheek of stel er zelf een samen. '
                'Of start hieronder een losse sessie.'),
            Gap.m,
            _WideButton(
              label: 'Naar de bibliotheek',
              icon: Icons.arrow_forward,
              onPressed: () => context.go('/rowing/library'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The 7-day calendar strip under the app bar — today accent-filled, trained
/// days marked, future days muted. Full-bleed with a 2px bottom rule.
class _WeekStrip extends ConsumerWidget {
  const _WeekStrip({required this.discipline});
  final Discipline discipline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final trained =
        ref.watch(_trainedDaysProvider(discipline)).valueOrNull ?? const {};
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    const abbr = ['MA', 'DI', 'WO', 'DO', 'VR', 'ZA', 'ZO'];

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.rule, width: 2)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: i == now.weekday - 1 ? p.accent : null,
                  border: Border(
                    right: i == 6
                        ? BorderSide.none
                        : BorderSide(color: p.line),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      abbr[i],
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontSize: 10,
                            letterSpacing: 0.6,
                            color: i == now.weekday - 1
                                ? p.accentInk
                                : p.mute,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${monday.add(Duration(days: i)).day}',
                      style: TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: i == now.weekday - 1
                            ? p.accentInk
                            : i > now.weekday - 1
                                ? p.mute
                                : p.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 4,
                      height: 4,
                      color: trained.contains(i + 1)
                          ? (i == now.weekday - 1 ? p.accentInk : p.accent)
                          : Colors.transparent,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The "DEZE WEEK" pair of bordered stat boxes.
class _WeekStats extends ConsumerWidget {
  const _WeekStats({required this.discipline});
  final Discipline discipline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count =
        ref.watch(_thisWeekCountProvider(discipline)).valueOrNull ?? 0;

    final boxes = <Widget>[
      _StatBox(
        value: '$count',
        caption: discipline == Discipline.rowing ? 'Sessies' : 'Trainingen',
      ),
    ];

    if (discipline == Discipline.rowing) {
      final wk = ref.watch(rowingWeeklyDistanceProvider).valueOrNull;
      final km = wk == null || wk.isEmpty ? 0.0 : wk.last.distanceM;
      boxes.add(_StatBox(
        value: km <= 0 ? '0' : distanceLabel(km),
        caption: 'Geroeid',
      ));
    } else {
      final streak = ref.watch(trainingWeekStreakProvider).valueOrNull ?? 0;
      boxes.add(_StatBox(
        value: '$streak',
        caption: streak == 1 ? 'Week op rij' : 'Weken op rij',
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Kicker('Deze week', muted: true),
        Gap.s,
        Row(
          children: [
            Expanded(child: boxes[0]),
            Gap.s,
            Expanded(child: boxes[1]),
          ],
        ),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.value, required this.caption});
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(border: Border.all(color: p.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: AppTheme.numeric(size: 24, color: p.ink)),
          const SizedBox(height: 4),
          Text(caption.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 9, letterSpacing: 1.1, color: p.mute)),
        ],
      ),
    );
  }
}

class _FreeRowCard extends StatelessWidget {
  const _FreeRowCard({required this.onStart, required this.onLog});
  final VoidCallback onStart;
  final VoidCallback onLog;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Kicker('Roeien · Losse sessie'),
            Gap.s,
            Text('Vrije roeisessie',
                style: Theme.of(context).textTheme.titleLarge),
            Gap.m,
            _WideButton(
              label: 'Start roeisessie',
              icon: Icons.north_east,
              filled: false,
              accentBorder: true,
              onPressed: onStart,
            ),
            Gap.s,
            _WideButton(
              label: 'Handmatig loggen',
              icon: Icons.edit_outlined,
              filled: false,
              onPressed: onLog,
            ),
          ],
        ),
      ),
    );
  }
}

class _RowingDayCard extends ConsumerWidget {
  const _RowingDayCard({required this.active});
  final ActiveProgram active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = context.palette;
    final day = active.currentDay;
    final info = ref.watch(_rowDayInfoProvider(day.id));
    final sessionNr =
        (active.round - 1) * active.dayCount + active.currentDayIndex + 1;
    final planDone = active.round > 1 && active.currentDayIndex == 0;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _Kicker('Vandaag · Roeien')),
                _Kicker('Sessie $sessionNr', muted: true),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(day.label.split(' · ').last,
                      style: theme.textTheme.headlineSmall),
                ),
                if (RowSessionType.fromName(day.rowSessionType) case final t?)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(t.label),
                  ),
              ],
            ),
          ),
          if (planDone)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'Plan afgerond — begin opnieuw of kies een nieuw plan',
                style: theme.textTheme.bodySmall,
              ),
            )
          else
            info.viewOrNothing((i) {
              final ftp = ref.watch(rowingFtpProvider).valueOrNull;
              final dragK =
                  ref.watch(rowingDragKProvider).valueOrNull ?? kGeneric;
              final pace = dayPaceSummary(i.$3, ftp, dragK);
              final stale =
                  rowTargetsStale(active.program.ftpWattsAtGen, ftp?.watts);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: p.rule, width: 2),
                        bottom: BorderSide(color: p.line),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '~${i.$1} MIN · ${_blocks(i.$2).toUpperCase()}',
                            style: theme.textTheme.labelSmall
                                ?.copyWith(fontSize: 10, letterSpacing: 1.0),
                          ),
                        ),
                        if (pace != null)
                          Text(pace.toUpperCase(),
                              style: theme.textTheme.labelSmall?.copyWith(
                                  fontSize: 10, letterSpacing: 0.6)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: IntervalProfile(
                      blocks: profileFromSegments(i.$3),
                      height: 32,
                    ),
                  ),
                  if (stale)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: TextButton(
                        onPressed: () async {
                          final w =
                              ref.read(rowingFtpProvider).valueOrNull?.watts;
                          if (w == null) return;
                          await ref
                              .read(programRepositoryProvider)
                              .rewriteRowTargets(active.program.id, w);
                          ref.invalidate(activeRowingProgramProvider);
                          ref.invalidate(_rowDayInfoProvider(day.id));
                        },
                        child: const Text("Richttempo's bijwerken"),
                      ),
                    ),
                ],
              );
            }),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              children: [
                _WideButton(
                  label: 'Start roeisessie',
                  icon: Icons.play_arrow,
                  onPressed: () async {
                    await ensureRowerConnected(context, ref);
                    if (!context.mounted) return;
                    await ref
                        .read(activeRowingProvider.notifier)
                        .startFromDay(day);
                    if (context.mounted) context.push('/rowing/active');
                  },
                ),
                TextButton(
                  onPressed: () => context.go('/rowing/library'),
                  child: const Text('Ander plan'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgramDayCard extends ConsumerWidget {
  const _ProgramDayCard({required this.active});
  final ActiveProgram active;

  String _roundLabel(WidgetRef ref, int round) {
    final autoOn = ref.watch(autoProgressionProvider).valueOrNull ?? true;
    if (!autoOn) return 'Ronde $round';
    final d = progressTargets(baseSets: 0, baseReps: 0, round: round);
    final parts = [
      if (d.sets > 0) '+${d.sets} set${d.sets > 1 ? 's' : ''}',
      if (d.reps > 0) '+${d.reps} reps',
    ];
    return parts.isEmpty ? 'Ronde $round' : 'Ronde $round · ${parts.join(' · ')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = context.palette;
    final day = active.currentDay;
    final preview = ref.watch(_dayPreviewProvider(day.id));

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _Kicker('Vandaag · Kracht')),
                _Kicker(
                  active.round > 1
                      ? _roundLabel(ref, active.round)
                      : 'Dag ${active.currentDayIndex + 1}/${active.dayCount}',
                  muted: true,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(day.label, style: theme.textTheme.headlineSmall),
          ),
          preview.viewOrNothing((d) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: p.rule, width: 2),
                        bottom: BorderSide(color: p.line),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                            child: _Metric('${d.exercises}', 'Oefeningen')),
                        Expanded(child: _Metric('${d.sets}', 'Reeksen')),
                        Expanded(
                          child: _Metric('${d.minutes}', 'Geschat',
                              unit: 'min', showRight: false),
                        ),
                      ],
                    ),
                  ),
                  _ExerciseList(d.rows),
                ],
              )),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: _WideButton(
                    label: 'Start training',
                    icon: Icons.play_arrow,
                    onPressed: () async {
                      await ref
                          .read(activeWorkoutProvider.notifier)
                          .startFromDay(day);
                      if (context.mounted) context.push('/workout/active');
                    },
                  ),
                ),
                Gap.s,
                OutlinedButton(
                  onPressed: () => _pickDay(context, ref),
                  child: const Text('DAG'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDay(BuildContext context, WidgetRef ref) async {
    final chosen = await showModalBottomSheet<ProgramDay>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < active.days.length; i++)
              ListTile(
                leading: Text('${i + 1}'),
                title: Text(active.days[i].label),
                trailing: i == active.currentDayIndex
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(context, active.days[i]),
              ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    await ref
        .read(programRepositoryProvider)
        .setCursor(active.program.id, chosen.dayIndex);
    ref.invalidate(activeProgramProvider);
    if (context.mounted) {
      await ref.read(activeWorkoutProvider.notifier).startFromDay(chosen);
      if (context.mounted) context.push('/workout/active');
    }
  }
}
