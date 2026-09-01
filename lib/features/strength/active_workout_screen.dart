import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/workout_session_repository.dart';
import '../library/exercise_list_screen.dart';
import 'state/active_workout_provider.dart';
import 'widgets/number_stepper.dart';
import 'widgets/rest_timer_bar.dart';

class ActiveWorkoutScreen extends ConsumerWidget {
  const ActiveWorkoutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(activeWorkoutProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Training'),
        actions: [
          if (async.valueOrNull != null)
            TextButton.icon(
              onPressed: () => _finish(context, ref),
              icon: const Icon(Icons.check),
              label: const Text('Klaar'),
            ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'discard') _discard(context, ref);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'discard', child: Text('Training weggooien')),
            ],
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fout: $e')),
        data: (state) {
          if (state == null) {
            return const Center(child: Text('Geen training bezig'));
          }
          if (state.blocks.isEmpty) {
            return const _EmptyHint();
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            itemCount: state.blocks.length,
            itemBuilder: (context, index) => _ExerciseCard(blockIndex: index),
          );
        },
      ),
      bottomNavigationBar: const RestTimerBar(),
      floatingActionButton: async.valueOrNull == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _addExercise(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Oefening'),
            ),
    );
  }

  Future<void> _addExercise(BuildContext context, WidgetRef ref) async {
    final exerciseId = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => const ExerciseListScreen(pickMode: true),
      ),
    );
    if (exerciseId != null) {
      await ref.read(activeWorkoutProvider.notifier).addExercise(exerciseId);
    }
  }

  Future<void> _finish(BuildContext context, WidgetRef ref) async {
    final id = await ref.read(activeWorkoutProvider.notifier).finish();
    ref.invalidate(recentSessionsProvider);
    if (!context.mounted) return;
    if (id != null) {
      context.pushReplacement('/log/session/$id');
    } else {
      context.go('/today');
    }
  }

  Future<void> _discard(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Training weggooien?'),
        content: const Text('Alle gelogde sets van deze sessie gaan verloren.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Weggooien'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(activeWorkoutProvider.notifier).discard();
    if (context.mounted) context.go('/today');
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();
  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Nog geen oefeningen. Tik op "Oefening" om er een toe te voegen.',
            textAlign: TextAlign.center,
          ),
        ),
      );
}

/// Draft reps/weight for the next set of one exercise block.
class _DraftEntry {
  _DraftEntry(this.reps, this.weight);
  double reps;
  double weight;
  bool isWarmup = false;
}

class _ExerciseCard extends ConsumerStatefulWidget {
  const _ExerciseCard({required this.blockIndex});
  final int blockIndex;

  @override
  ConsumerState<_ExerciseCard> createState() => _ExerciseCardState();
}

class _ExerciseCardState extends ConsumerState<_ExerciseCard> {
  _DraftEntry? _draft;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(activeWorkoutProvider).valueOrNull;
    if (state == null || widget.blockIndex >= state.blocks.length) {
      return const SizedBox.shrink();
    }
    final block = state.blocks[widget.blockIndex];
    final notifier = ref.read(activeWorkoutProvider.notifier);
    final theme = Theme.of(context);

    final draft = _draft ??= _DraftEntry(
      block.suggestedReps.toDouble(),
      block.suggestedWeight,
    );

    final targetText = StringBuffer('${block.targetSets} × ${block.targetReps}');
    if (block.targetWeight != null) {
      targetText.write(' @ ${block.targetWeight!.toStringAsFixed(1)} kg');
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(block.exercise.name,
                      style: theme.textTheme.titleMedium),
                ),
                Text(targetText.toString(), style: theme.textTheme.bodySmall),
                IconButton(
                  icon: const Icon(Icons.tune, size: 20),
                  tooltip: 'Doelen aanpassen',
                  onPressed: () => _editTargets(block),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () => notifier.removeBlock(widget.blockIndex),
                ),
              ],
            ),
            if (block.sets.isNotEmpty) const SizedBox(height: 8),
            ...block.sets.asMap().entries.map((e) {
              final s = e.value;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    SizedBox(width: 24, child: Text('${s.setIndex}')),
                    Text('${s.reps} × ${s.weight.toStringAsFixed(1)} kg'),
                    if (s.isWarmup) ...[
                      const SizedBox(width: 6),
                      Text('W', style: theme.textTheme.labelSmall),
                    ],
                    const Spacer(),
                    if (e.key == block.sets.length - 1)
                      IconButton(
                        icon: const Icon(Icons.undo, size: 18),
                        onPressed: () =>
                            notifier.undoLastSet(widget.blockIndex),
                      ),
                  ],
                ),
              );
            }),
            const Divider(),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                NumberStepper(
                  label: 'Reps',
                  value: draft.reps,
                  step: 1,
                  min: 1,
                  onChanged: (v) => draft.reps = v,
                ),
                NumberStepper(
                  label: 'Gewicht (kg)',
                  value: draft.weight,
                  step: 2.5,
                  decimals: 1,
                  onChanged: (v) => draft.weight = v,
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: draft.isWarmup,
                      onChanged: (v) =>
                          setState(() => draft.isWarmup = v ?? false),
                    ),
                    const Text('Opwarming'),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  notifier.logSet(
                    widget.blockIndex,
                    reps: draft.reps.round(),
                    weight: draft.weight,
                    isWarmup: draft.isWarmup,
                  );
                  setState(() => _draft = null);
                },
                child: const Text('Log set'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editTargets(dynamic block) async {
    final sets = ValueNotifier<double>(block.targetSets.toDouble());
    final reps = ValueNotifier<double>(block.targetReps.toDouble());
    final rest = ValueNotifier<double>(block.restSeconds.toDouble());

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(block.exercise.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dialogRow('Sets', sets, step: 1, min: 1),
            _dialogRow('Reps', reps, step: 1, min: 1),
            _dialogRow('Rust (s)', rest, step: 15, min: 0),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(activeWorkoutProvider.notifier).updateBlockTargets(
                    widget.blockIndex,
                    targetSets: sets.value.round(),
                    targetReps: reps.value.round(),
                    restSeconds: rest.value.round(),
                  );
              Navigator.pop(context);
            },
            child: const Text('Opslaan'),
          ),
        ],
      ),
    );
  }

  Widget _dialogRow(String label, ValueNotifier<double> notifier,
      {required double step, required double min}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ValueListenableBuilder<double>(
        valueListenable: notifier,
        builder: (context, value, _) => NumberStepper(
          label: label,
          value: value,
          step: step,
          min: min,
          onChanged: (v) => notifier.value = v,
        ),
      ),
    );
  }
}
