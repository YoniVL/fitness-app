import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../library/exercise_list_screen.dart';
import 'state/active_workout_provider.dart';
import 'state/rest_timer_notifier.dart';
import 'widgets/number_stepper.dart';
import 'widgets/rest_fullscreen.dart';

class ActiveWorkoutScreen extends ConsumerStatefulWidget {
  const ActiveWorkoutScreen({super.key});

  @override
  ConsumerState<ActiveWorkoutScreen> createState() =>
      _ActiveWorkoutScreenState();
}

class _ActiveWorkoutScreenState extends ConsumerState<ActiveWorkoutScreen> {
  /// Blocks the user chose to expand manually (besides the current one).
  final Set<int> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(activeWorkoutProvider);
    final resting = ref.watch(restTimerProvider).active;

    if (resting) {
      final state = async.valueOrNull;
      final next = state == null || state.currentBlockIndex < 0
          ? null
          : state.blocks[state.currentBlockIndex];
      return RestFullscreen(
        nextExerciseName: next?.exercise.name,
        nextSetLabel: next == null
            ? null
            : 'Set ${next.completedSets + 1}/${next.targetSets}',
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Training'),
        actions: [
          if (async.valueOrNull != null && !async.valueOrNull!.allComplete)
            TextButton(
              onPressed: () => _finish(),
              child: const Text('Afronden'),
            ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'discard') _discard();
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
          if (state.blocks.isEmpty) return const _EmptyHint();
          final current = state.currentBlockIndex;
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 120),
            children: [
              for (var i = 0; i < state.blocks.length; i++)
                _ExerciseCard(
                  blockIndex: i,
                  expanded: i == current || _expanded.contains(i),
                  isCurrent: i == current,
                  onToggle: () => setState(() {
                    _expanded.contains(i)
                        ? _expanded.remove(i)
                        : _expanded.add(i);
                  }),
                ),
              if (state.allComplete)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: () => _finish(),
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Dag afronden'),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton:
          (async.valueOrNull == null || async.valueOrNull!.allComplete)
              ? null
              : FloatingActionButton.extended(
                  onPressed: _addExercise,
                  icon: const Icon(Icons.add),
                  label: const Text('Oefening'),
                ),
    );
  }

  Future<void> _addExercise() async {
    final id = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => const ExerciseListScreen(pickMode: true),
      ),
    );
    if (id != null) {
      await ref.read(activeWorkoutProvider.notifier).addExercise(id);
    }
  }

  Future<void> _finish() async {
    final id = await ref.read(activeWorkoutProvider.notifier).finish();
    if (!mounted) return;
    if (id != null) {
      context.pushReplacement('/log/session/$id');
    } else {
      context.go('/today');
    }
  }

  Future<void> _discard() async {
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
    if (mounted) context.go('/today');
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

class _ExerciseCard extends ConsumerStatefulWidget {
  const _ExerciseCard({
    required this.blockIndex,
    required this.expanded,
    required this.isCurrent,
    required this.onToggle,
  });

  final int blockIndex;
  final bool expanded;
  final bool isCurrent;
  final VoidCallback onToggle;

  @override
  ConsumerState<_ExerciseCard> createState() => _ExerciseCardState();
}

class _ExerciseCardState extends ConsumerState<_ExerciseCard> {
  double? _reps;
  bool _warmup = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(activeWorkoutProvider).valueOrNull;
    if (state == null || widget.blockIndex >= state.blocks.length) {
      return const SizedBox.shrink();
    }
    final block = state.blocks[widget.blockIndex];
    final notifier = ref.read(activeWorkoutProvider.notifier);
    final theme = Theme.of(context);
    final reps = _reps ??= block.suggestedReps.toDouble();

    if (!widget.expanded) {
      return Card(
        child: ListTile(
          leading: Icon(
            block.isComplete ? Icons.check_circle : Icons.circle_outlined,
            color: block.isComplete ? theme.colorScheme.primary : null,
          ),
          title: Text(block.exercise.name),
          subtitle: Text('${block.completedSets}/${block.targetSets} sets'),
          trailing: const Icon(Icons.expand_more),
          onTap: widget.onToggle,
        ),
      );
    }

    return Card(
      color: widget.isCurrent
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
          : null,
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
                Text('${block.targetSets} × ${block.targetReps}',
                    style: theme.textTheme.bodySmall),
                IconButton(
                  icon: const Icon(Icons.tune, size: 20),
                  tooltip: 'Aanpassen',
                  onPressed: () => _editTargets(block),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () => notifier.removeBlock(widget.blockIndex),
                ),
              ],
            ),
            if (block.sets.isNotEmpty) const SizedBox(height: 4),
            ...block.sets.asMap().entries.map((e) {
              final s = e.value;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    SizedBox(width: 26, child: Text('${s.setIndex}')),
                    Text('${s.reps} reps'),
                    if (s.isWarmup) ...[
                      const SizedBox(width: 6),
                      Text('opwarming', style: theme.textTheme.labelSmall),
                    ],
                    const Spacer(),
                    if (e.key == block.sets.length - 1)
                      IconButton(
                        icon: const Icon(Icons.undo, size: 18),
                        onPressed: () => notifier.undoLastSet(widget.blockIndex),
                      ),
                  ],
                ),
              );
            }),
            if (!block.isComplete) ...[
              const Divider(),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  NumberStepper(
                    label: 'Reps',
                    value: reps,
                    min: 1,
                    max: 100,
                    onChanged: (v) => setState(() => _reps = v),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: _warmup,
                        onChanged: (v) =>
                            setState(() => _warmup = v ?? false),
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
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () {
                    notifier.logSet(
                      widget.blockIndex,
                      reps: reps.round(),
                      isWarmup: _warmup,
                    );
                    setState(() {
                      _reps = null;
                      _warmup = false;
                    });
                  },
                  child: Text(
                    'Klaar — set ${block.completedSets + 1}/${block.targetSets}',
                  ),
                ),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(Icons.check_circle,
                        size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    const Text('Klaar'),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _editTargets(ExerciseBlock block) async {
    final sets = ValueNotifier<double>(block.targetSets.toDouble());
    final reps = ValueNotifier<double>(block.targetReps.toDouble());
    final restSet = ValueNotifier<double>(block.restBetweenSets.toDouble());
    final restEx = ValueNotifier<double>(block.restAfterExercise.toDouble());

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(block.exercise.name),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogRow('Sets', sets, step: 1, min: 1, max: 10),
              _dialogRow('Reps', reps, step: 1, min: 1, max: 50),
              _dialogRow('Rust tussen sets (s)', restSet,
                  step: 15, min: 0, max: 300),
              _dialogRow('Rust na oefening (s)', restEx,
                  step: 15, min: 0, max: 300),
            ],
          ),
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
                    restBetweenSets: restSet.value.round(),
                    restAfterExercise: restEx.value.round(),
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
      {required double step, required double min, required double max}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ValueListenableBuilder<double>(
        valueListenable: notifier,
        builder: (context, value, _) => NumberStepper(
          label: label,
          value: value,
          step: step,
          min: min,
          max: max,
          onChanged: (v) => notifier.value = v,
        ),
      ),
    );
  }
}
