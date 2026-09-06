import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/exercise_repository.dart';
import '../../data/repositories/program_repository.dart';
import '../../domain/models/exercise.dart';
import '../../domain/models/program.dart';
import '../../domain/models/rowing_plan.dart';
import '../../ui/async_view.dart';
import '../../ui/confirm_dialog.dart';
import '../../ui/spacing.dart';
import '../rowing/ble/connect_sheet.dart';
import '../rowing/state/active_rowing_provider.dart';
import '../rowing/widgets/interval_profile.dart';
import '../rowing/widgets/week_load_chart.dart';
import '../strength/state/active_workout_provider.dart';

class _DayView {
  _DayView(this.day, this.exercises, this.segments);
  final ProgramDay day;
  final List<({ProgramExercise prescription, Exercise exercise})> exercises;
  final List<ProgramRowSegment> segments;
}

class _ProgramView {
  _ProgramView(this.program, this.days);
  final Program program;
  final List<_DayView> days;
}

final _programDetailProvider =
    FutureProvider.family<_ProgramView, int>((ref, programId) async {
  final programs = ref.read(programRepositoryProvider);
  final exercises = ref.read(exerciseRepositoryProvider);

  final program = await programs.programById(programId);
  if (program == null) throw StateError('Programma $programId niet gevonden');

  final days = await programs.daysForProgram(programId);
  final views = <_DayView>[];
  for (final day in days) {
    final prescribed = await programs.exercisesForDay(day.id);
    final exMap = await exercises.byIds(prescribed.map((e) => e.exerciseId));
    final resolved = <({ProgramExercise prescription, Exercise exercise})>[];
    for (final pe in prescribed) {
      final ex = exMap[pe.exerciseId];
      if (ex != null) resolved.add((prescription: pe, exercise: ex));
    }
    final segments = await programs.rowSegmentsForDay(day.id);
    views.add(_DayView(day, resolved, segments));
  }
  return _ProgramView(program, views);
});

class ProgramDetailScreen extends ConsumerWidget {
  const ProgramDetailScreen({super.key, required this.programId});

  final int programId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(_programDetailProvider(programId));
    final activeProgram = ref.watch(activeProgramProvider).valueOrNull;
    final isActive = activeProgram?.program.id == programId;

    final program = detail.valueOrNull?.program;
    return Scaffold(
      appBar: AppBar(
        title: Text(program?.name ?? 'Programma'),
        actions: [
          if (program != null) ...[
            if (program.discipline == Discipline.strength)
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Aanpassen',
                onPressed: () =>
                    context.push('/strength/library/program/$programId/edit'),
              ),
            if (!program.isTemplate)
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'delete') _confirmDelete(context, ref, program);
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'delete', child: Text('Verwijderen')),
                ],
              ),
          ],
        ],
      ),
      body: detail.view((view) {
          final isStrength =
              view.program.discipline == Discipline.strength;
          if (!isStrength) return _RowingPlanBody(view: view);
          return ListView(
            padding: Insets.screen,
            children: [
              if (isStrength)
                SizedBox(
                  width: double.infinity,
                  child: isActive
                      ? OutlinedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.check),
                          label: const Text('Dit is je actieve programma'),
                        )
                      : FilledButton.icon(
                          onPressed: () async {
                            await ref
                                .read(programRepositoryProvider)
                                .setActiveProgram(programId);
                            ref.invalidate(activeProgramProvider);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Ingesteld als je programma')),
                              );
                            }
                          },
                          icon: const Icon(Icons.event_available),
                          label: const Text('Kies als mijn programma'),
                        ),
                ),
              if (isStrength) Gap.m,
              for (final dayView in view.days) ...[
                _DayCard(
                  dayView: dayView,
                  isStrength: isStrength,
                  onStart: () async {
                    await ref
                        .read(activeWorkoutProvider.notifier)
                        .startFromDay(dayView.day);
                    if (context.mounted) context.push('/workout/active');
                  },
                ),
                Gap.m,
              ],
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e) => Center(child: Text('Fout: $e')),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, Program program) async {
    final ok = await confirmDialog(
      context,
      title: 'Schema verwijderen?',
      message: '"${program.name}" wordt definitief verwijderd.',
      confirmLabel: 'Verwijderen',
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(programRepositoryProvider).deleteProgram(program.id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Verwijderen mislukt: $e')));
      }
      return;
    }
    if (program.discipline == Discipline.strength) {
      ref.invalidate(visibleStrengthProgramsProvider);
      ref.invalidate(activeProgramProvider);
    } else {
      ref.invalidate(rowingProgramsProvider);
      ref.invalidate(activeRowingProgramProvider);
    }
    if (context.mounted) context.pop();
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.dayView,
    required this.isStrength,
    this.onStart,
  });

  final _DayView dayView;
  final bool isStrength;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: Insets.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dayView.day.label, style: theme.textTheme.titleLarge),
            Gap.s,
            if (isStrength)
              ...dayView.exercises.map(
                (row) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text(row.exercise.name)),
                      Text(
                        '${row.prescription.targetSets} × '
                        '${row.exercise.formatReps(row.prescription.targetReps)}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              )
            else
              ...dayView.segments.map(
                (s) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('${s.intensityLabel}'
                            '${s.targetStrokeRate != null ? ' · ${s.targetStrokeRate} spm' : ''}'),
                      ),
                      Text(_fmtDuration(s.durationSeconds),
                          style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
              ),
            if (onStart != null) ...[
              Gap.m,
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onStart,
                  child: const Text('START DEZE DAG LOS'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _fmtDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return s == 0 ? '${m}m' : '${m}m ${s}s';
  }
}

String _segDuration(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  if (m == 0) return '${s}s';
  return s == 0 ? '$m min' : "$m'${s.toString().padLeft(2, '0')}";
}

/// Rowing plan / loose session detail — sessions grouped by week, each an
/// expandable list of its segments.
class _RowingPlanBody extends ConsumerWidget {
  const _RowingPlanBody({required this.view});
  final _ProgramView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final goal = view.program.goal;
    final program = view.program;
    final isPlan = view.days.length > 1;
    final activeRowId =
        ref.watch(activeRowingProgramProvider).valueOrNull?.program.id;
    final isActive = activeRowId == program.id;

    // Group days by the "Wk N" prefix in their label; loose sessions (no
    // prefix) fall under a single implicit group.
    final groups = <String, List<_DayView>>{};
    for (final d in view.days) {
      final parts = d.day.label.split(' · ');
      final key = parts.first.startsWith('Wk ') ? parts.first : '';
      groups.putIfAbsent(key, () => []).add(d);
    }

    return ListView(
      padding: Insets.screen,
      children: [
        if (goal != null || view.program.level != null)
          Wrap(
            spacing: 8,
            children: [
              if (goal != null) Chip(label: Text(goal.label)),
              if (view.program.level != null)
                Chip(label: Text(view.program.level!.label)),
              if (view.program.daysPerWeek != null)
                Chip(label: Text('${view.program.daysPerWeek}×/week')),
            ],
          ),
        if (goal != null) ...[
          Gap.s,
          Text(goal.description, style: theme.textTheme.bodySmall),
        ],
        if (isPlan) ...[
          Gap.m,
          SizedBox(
            width: double.infinity,
            child: isActive
                ? OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.check),
                    label: const Text('Je actieve roeiprogramma'),
                  )
                : FilledButton.icon(
                    onPressed: () async {
                      await ref
                          .read(programRepositoryProvider)
                          .setActiveRowingProgram(program.id);
                      ref.invalidate(activeRowingProgramProvider);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content:
                                  Text('Ingesteld als je roeiprogramma')),
                        );
                      }
                    },
                    icon: const Icon(Icons.event_available),
                    label: const Text('Kies als mijn roeiprogramma'),
                  ),
          ),
        ],
        if (isPlan && groups.length > 1) ...[
          Gap.l,
          Text('Trainingsminuten per week', style: theme.textTheme.labelMedium),
          Gap.s,
          WeekLoadChart(minutesPerWeek: [
            for (final g in groups.values)
              (g
                          .expand((d) => d.segments)
                          .fold(0, (s, seg) => s + seg.durationSeconds) /
                      60)
                  .round(),
          ]),
        ],
        Gap.m,
        for (final entry in groups.entries) ...[
          if (entry.key.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
              child: Text(entry.key.replaceFirst('Wk ', 'Week '),
                  style: theme.textTheme.titleSmall),
            ),
          for (final d in entry.value)
            _RowSessionCard(
              dayView: d,
              onStart: () async {
                await ensureRowerConnected(context, ref);
                if (!context.mounted) return;
                await ref
                    .read(activeRowingProvider.notifier)
                    .startFromDay(d.day);
                if (context.mounted) context.push('/rowing/active');
              },
            ),
        ],
      ],
    );
  }
}

class _RowSessionCard extends StatelessWidget {
  const _RowSessionCard({required this.dayView, this.onStart});
  final _DayView dayView;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final segs = dayView.segments;
    final totalMin =
        (segs.fold(0, (s, seg) => s + seg.durationSeconds) / 60).round();
    const framing = {'Warming-up', 'Uitroeien'};
    final workBlocks =
        segs.where((s) => !s.isRest && !framing.contains(s.intensityLabel)).length;
    // Drop the "Wk N · " prefix from the visible title.
    final parts = dayView.day.label.split(' · ');
    final title = parts.length > 1 ? parts.sublist(1).join(' · ') : parts.first;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text(title),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IntervalProfile(
                  blocks: profileFromSegments(segs), height: 38),
              const SizedBox(height: 6),
              Text(
                  '~$totalMin min · '
                  '$workBlocks ${workBlocks == 1 ? 'blok' : 'blokken'}',
                  style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          for (final seg in segs)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          seg.intensityLabel,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: seg.isRest
                                ? theme.colorScheme.onSurfaceVariant
                                : null,
                          ),
                        ),
                        if (RowDrill.fromKey(seg.drillKey) case final d?)
                          Text(d.tip,
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Gap.s,
                  Text(
                    [
                      _segDuration(seg.durationSeconds),
                      if (seg.targetStrokeRate != null)
                        '${seg.targetStrokeRate} spm',
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          if (onStart != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onStart,
                  child: const Text('START DEZE SESSIE'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
