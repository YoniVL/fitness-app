import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../data/repositories/workout_session_repository.dart';
import '../../exercises/exercise_media.dart';
import '../../../ui/spacing.dart';
import '../state/rest_timer_notifier.dart';

/// Full-screen rest view shown between sets and after an exercise: big countdown,
/// the same controls, and a demo of the next exercise.
class RestFullscreen extends ConsumerWidget {
  const RestFullscreen({
    super.key,
    this.nextExerciseName,
    this.nextExerciseId,
    this.nextSetLabel,
  });

  final String? nextExerciseName;
  final int? nextExerciseId;
  final String? nextSetLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timer = ref.watch(restTimerProvider);
    final notifier = ref.read(restTimerProvider.notifier);
    final theme = Theme.of(context);
    final p = context.palette;

    final remaining = timer.remainingSeconds.clamp(0, 9999);
    final mmss = '${(remaining ~/ 60).toString().padLeft(2, '0')}:'
        '${(remaining % 60).toString().padLeft(2, '0')}';

    return Scaffold(
      backgroundColor: p.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Gap.m,
              Text('RUST',
                  style: theme.textTheme.labelMedium?.copyWith(
                      letterSpacing: 3, color: p.accent, fontSize: 12)),
              const Spacer(),
              Center(
                child: SizedBox(
                  width: 236,
                  height: 236,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 236,
                        height: 236,
                        child: CircularProgressIndicator(
                          value: (1 - timer.progress).clamp(0.0, 1.0),
                          strokeWidth: 8,
                          backgroundColor: p.line,
                        ),
                      ),
                      Text(mmss, style: AppTheme.numeric(size: 60, color: p.ink)),
                    ],
                  ),
                ),
              ),
              Gap.l,
              if (nextExerciseName != null) ...[
                Text('VOLGENDE',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(fontSize: 10, letterSpacing: 1.2)),
                const SizedBox(height: 2),
                Text(nextExerciseName!, style: theme.textTheme.titleLarge),
                if (nextSetLabel != null)
                  Text(nextSetLabel!.toUpperCase(),
                      style: theme.textTheme.labelSmall
                          ?.copyWith(fontSize: 10, letterSpacing: 1.0)),
                if (nextExerciseId != null)
                  Builder(builder: (context) {
                    final last = ref
                        .watch(lastPerformanceProvider(nextExerciseId!))
                        .valueOrNull;
                    final reps = last
                            ?.where((s) => !s.isWarmup)
                            .map((s) => s.reps)
                            .toList() ??
                        const [];
                    if (reps.isEmpty) return const SizedBox.shrink();
                    return Text('Vorige keer: ${reps.join(' · ')}',
                        style: theme.textTheme.bodySmall);
                  }),
                if (hasExercisePhoto(nextExerciseName)) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child:
                        ExerciseDemo(exerciseName: nextExerciseName, maxHeight: 150),
                  ),
                ],
              ],
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => notifier.addSeconds(-15),
                      child: const Center(child: Text('−15s')),
                    ),
                  ),
                  Gap.s,
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => notifier.addSeconds(15),
                      child: const Center(child: Text('+15s')),
                    ),
                  ),
                ],
              ),
              Gap.s,
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: notifier.skip,
                  child: Row(
                    children: const [
                      Expanded(child: Text('OVERSLAAN')),
                      Icon(Icons.skip_next, size: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
