import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/exercise_repository.dart';
import '../../data/repositories/program_repository.dart';
import '../../domain/models/exercise.dart';
import '../../domain/models/program.dart';
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

    return Scaffold(
      appBar: AppBar(title: Text(detail.valueOrNull?.program.name ?? 'Programma')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fout: $e')),
        data: (view) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final dayView in view.days) ...[
              _DayCard(
                dayView: dayView,
                isStrength: view.program.discipline == Discipline.strength,
                onStart: view.program.discipline == Discipline.strength
                    ? () async {
                        await ref
                            .read(activeWorkoutProvider.notifier)
                            .startFromDay(dayView.day);
                        if (context.mounted) context.push('/workout/active');
                      }
                    : null,
              ),
              const SizedBox(height: 12),
            ],
            if (view.program.discipline == Discipline.rowing)
              Text(
                'De live roeisessie met Bluetooth-koppeling komt in een volgende versie. '
                'Dit programma staat al klaar.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dayView.day.label, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            if (isStrength)
              ...dayView.exercises.map(
                (row) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text(row.exercise.name)),
                      Text(
                        '${row.prescription.targetSets} × ${row.prescription.targetReps}'
                        '${row.prescription.targetWeight != null ? ' @ ${row.prescription.targetWeight!.toStringAsFixed(1)} kg' : ''}',
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
              const SizedBox(height: 12),
              FilledButton(onPressed: onStart, child: const Text('Start deze dag')),
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
