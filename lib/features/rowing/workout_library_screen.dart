import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/home_shell.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/models/program.dart';
import '../../domain/models/rowing_plan.dart';
import '../../domain/rowing_workouts.dart';
import 'ble/connect_sheet.dart';
import 'state/active_rowing_provider.dart';
import 'widgets/interval_profile.dart';

/// The concrete segments for a catalogue workout at [level] (a fixed mid `build`
/// factor — catalogue workouts aren't part of a periodised plan).
List<ProgramRowSegment> workoutSegments(RowWorkout w,
    [ProgramLevel level = ProgramLevel.medium]) {
  final blocks = w.blocks(level, 0.6);
  return [
    for (var i = 0; i < blocks.length; i++)
      ProgramRowSegment(
        id: 0,
        programDayId: 0,
        orderIndex: i,
        durationSeconds: blocks[i].seconds,
        targetStrokeRate: blocks[i].spm,
        intensityLabel: blocks[i].label,
        isRest: blocks[i].isRest,
        drillKey: blocks[i].drillKey,
        zone: blocks[i].intensity.name,
      ),
  ];
}

class WorkoutLibraryScreen extends ConsumerStatefulWidget {
  const WorkoutLibraryScreen({super.key});

  @override
  ConsumerState<WorkoutLibraryScreen> createState() =>
      _WorkoutLibraryScreenState();
}

class _WorkoutLibraryScreenState extends ConsumerState<WorkoutLibraryScreen> {
  RowSessionType? _filter;

  @override
  Widget build(BuildContext context) {
    final level =
        ref.watch(rowingLevelProvider).valueOrNull ?? ProgramLevel.medium;
    final byType = <RowSessionType, List<RowWorkout>>{};
    for (final w in rowWorkouts) {
      byType.putIfAbsent(w.type, () => []).add(w);
    }
    final types = RowSessionType.values
        .where((t) => byType[t]?.isNotEmpty ?? false)
        .toList();
    final shown = _filter == null ? types : [_filter!];

    return Scaffold(
      appBar: AppBar(
        leading: const DisciplineSwitchButton(),
        title: const Text('Workouts'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                Text('Niveau',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(width: 12),
                Expanded(
                  child: SegmentedButton<ProgramLevel>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                        visualDensity: VisualDensity.compact),
                    segments: [
                      for (final l in ProgramLevel.values)
                        ButtonSegment(value: l, label: Text(l.label)),
                    ],
                    selected: {level},
                    onSelectionChanged: (s) async {
                      await ref
                          .read(settingsRepositoryProvider)
                          .setRowingLevel(s.first);
                      ref.invalidate(rowingLevelProvider);
                    },
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('Alles'),
                    selected: _filter == null,
                    onSelected: (_) => setState(() => _filter = null),
                  ),
                ),
                for (final t in types)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(t.label),
                      selected: _filter == t,
                      onSelected: (_) => setState(() => _filter = t),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final type in shown) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(type.label,
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                  for (final w in byType[type]!)
                    _WorkoutRow(workout: w, level: level),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkoutRow extends ConsumerWidget {
  const _WorkoutRow({required this.workout, required this.level});
  final RowWorkout workout;
  final ProgramLevel level;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () async {
        final start = await showModalBottomSheet<bool>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (_) => _WorkoutSheet(workout: workout, level: level),
        );
        if (start != true || !context.mounted) return;
        await ensureRowerConnected(context, ref);
        if (!context.mounted) return;
        await ref.read(activeRowingProvider.notifier).startWorkout(
            workoutSegments(workout, level),
            kind: workout.type.name);
        if (context.mounted) context.push('/rowing/active');
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(workout.name, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 2),
                  Text('~${workout.approxMinutes} min · ${workout.focus}',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  IntervalProfile(
                    blocks: profileFromSegments(workoutSegments(workout, level)),
                    height: 26,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

class _WorkoutSheet extends StatelessWidget {
  const _WorkoutSheet({required this.workout, required this.level});
  final RowWorkout workout;
  final ProgramLevel level;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final segments = workoutSegments(workout, level);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 20 + MediaQuery.viewPaddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(workout.name, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(workout.focus, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          IntervalProfile(
              blocks: profileFromSegments(segments), height: 84),
          const SizedBox(height: 16),
          for (final s in segments)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(s.intensityLabel,
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: s.isRest
                                ? theme.colorScheme.onSurfaceVariant
                                : null)),
                  ),
                  Text(
                    [
                      _fmt(s.durationSeconds),
                      if (s.targetStrokeRate != null) '${s.targetStrokeRate} spm',
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start deze workout'),
              onPressed: () => Navigator.pop(context, true),
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m == 0) return '${s}s';
    return s == 0 ? '$m min' : "$m'${s.toString().padLeft(2, '0')}";
  }
}
