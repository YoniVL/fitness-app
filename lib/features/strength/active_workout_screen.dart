import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../exercises/exercise_media.dart';
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
  final _pc = PageController();
  int _page = 0;
  bool _didInitialJump = false;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _jumpTo(int index, {bool animate = true}) {
    if (!_pc.hasClients) return;
    final clamped = index.clamp(0, 9999);
    if (animate) {
      _pc.animateToPage(clamped,
          duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
    } else {
      _pc.jumpToPage(clamped);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(activeWorkoutProvider);
    final resting = ref.watch(restTimerProvider).active;

    // When the rest ends, move to the exercise the user should do next.
    ref.listen(restTimerProvider, (prev, next) {
      if (prev != null && prev.active && !next.active) {
        final s = ref.read(activeWorkoutProvider).valueOrNull;
        final target = s?.currentBlockIndex ?? -1;
        if (target >= 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _jumpTo(target));
        }
      }
    });

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

    return async.when(
      loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Fout: $e'))),
      data: (state) {
        if (state == null) {
          return const Scaffold(
              body: Center(child: Text('Geen training bezig')));
        }
        if (state.blocks.isEmpty) {
          return Scaffold(
            appBar: _appBar(state),
            body: _EmptyHint(onAdd: _addExercise),
          );
        }

        // Jump to the current exercise once, when resuming a session.
        if (!_didInitialJump) {
          _didInitialJump = true;
          final target = state.currentBlockIndex;
          if (target > 0) {
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _jumpTo(target, animate: false));
          }
        }

        if (state.allComplete) {
          return Scaffold(
            appBar: AppBar(title: const Text('Training')),
            body: _DonePage(onFinish: _finish, onAdd: _addExercise),
          );
        }

        return Scaffold(
          appBar: _appBar(state),
          body: Column(
            children: [
              _ProgressDots(state: state, current: _page),
              Expanded(
                child: PageView.builder(
                  controller: _pc,
                  itemCount: state.blocks.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, i) => _ExercisePage(
                    blockIndex: i,
                    isLast: i == state.blocks.length - 1,
                    onNext: () => _jumpTo(i + 1),
                    onFinish: _finish,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  PreferredSizeWidget _appBar(ActiveWorkoutState state) => AppBar(
        titleSpacing: 0,
        title: Text(state.blocks.isEmpty
            ? 'Training'
            : 'Oefening ${_page + 1}/${state.blocks.length}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.list),
            tooltip: 'Overzicht',
            onPressed: () => _showOverview(state),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'finish') _finish();
              if (v == 'discard') _discard();
            },
            itemBuilder: (context) => [
              if (!state.allComplete)
                const PopupMenuItem(
                    value: 'finish', child: Text('Training afronden')),
              const PopupMenuItem(
                  value: 'discard', child: Text('Training weggooien')),
            ],
          ),
        ],
      );

  Future<void> _showOverview(ActiveWorkoutState state) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < state.blocks.length; i++)
              ListTile(
                leading: Icon(state.blocks[i].isComplete
                    ? Icons.check_circle
                    : Icons.circle_outlined),
                title: Text(state.blocks[i].exercise.name),
                subtitle: Text(
                    '${state.blocks[i].completedSets}/${state.blocks[i].targetSets} sets'),
                selected: i == _page,
                onTap: () {
                  Navigator.pop(context);
                  _jumpTo(i);
                },
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Oefening toevoegen'),
              onTap: () {
                Navigator.pop(context);
                _addExercise();
              },
            ),
          ],
        ),
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
      final s = ref.read(activeWorkoutProvider).valueOrNull;
      if (s != null) _jumpTo(s.blocks.length - 1);
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

class _ProgressDots extends StatelessWidget {
  const _ProgressDots({required this.state, required this.current});
  final ActiveWorkoutState state;
  final int current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < state.blocks.length; i++)
            Container(
              width: i == current ? 22 : 8,
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: state.blocks[i].isComplete
                    ? scheme.primary
                    : i == current
                        ? scheme.primary.withValues(alpha: 0.5)
                        : scheme.onSurface.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.onAdd});
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Nog geen oefeningen.', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('Oefening toevoegen'),
              ),
            ],
          ),
        ),
      );
}

class _DonePage extends StatelessWidget {
  const _DonePage({required this.onFinish, required this.onAdd});
  final VoidCallback onFinish;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle,
                size: 72, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Alle oefeningen klaar', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
                onPressed: onFinish,
                child: const Text('Dag afronden'),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onAdd,
              child: const Text('Toch nog een oefening'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExercisePage extends ConsumerStatefulWidget {
  const _ExercisePage({
    required this.blockIndex,
    required this.isLast,
    required this.onNext,
    required this.onFinish,
  });

  final int blockIndex;
  final bool isLast;
  final VoidCallback onNext;
  final VoidCallback onFinish;

  @override
  ConsumerState<_ExercisePage> createState() => _ExercisePageState();
}

class _ExercisePageState extends ConsumerState<_ExercisePage> {
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

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 4, 20, 16 + MediaQuery.viewPaddingOf(context).bottom),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(block.exercise.name,
                    style: theme.textTheme.titleLarge),
              ),
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
          if (block.exercise.pattern != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(block.exercise.pattern!.label,
                  style: theme.textTheme.bodySmall),
            ),
          Expanded(
            child: Center(
              child: hasExercisePhoto(block.exercise.name)
                  ? ExerciseDemo(
                      exerciseName: block.exercise.name, maxHeight: 260)
                  : Icon(Icons.fitness_center,
                      size: 64,
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.25)),
            ),
          ),
          // Done sets.
          Wrap(
            spacing: 6,
            runSpacing: 4,
            alignment: WrapAlignment.center,
            children: [
              for (final s in block.sets)
                Chip(
                  label: Text('${s.reps}${s.isWarmup ? ' W' : ''}'),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              if (block.sets.isNotEmpty)
                ActionChip(
                  label: const Text('Wis laatste'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => notifier.undoLastSet(widget.blockIndex),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (!block.isComplete) ...[
            NumberStepper(
              label:
                  'Reps · set ${block.completedSets + 1}/${block.targetSets}',
              value: reps,
              min: 1,
              max: 100,
              onChanged: (v) => setState(() => _reps = v),
            ),
            const SizedBox(height: 4),
            InkWell(
              onTap: () => setState(() => _warmup = !_warmup),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: _warmup,
                    onChanged: (v) => setState(() => _warmup = v ?? false),
                  ),
                  const Text('Opwarmset'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
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
                child: const Text('Klaar'),
              ),
            ),
          ] else
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
                onPressed: widget.isLast ? widget.onFinish : widget.onNext,
                icon: Icon(widget.isLast ? Icons.check_circle : Icons.arrow_forward),
                label: Text(widget.isLast ? 'Dag afronden' : 'Volgende oefening'),
              ),
            ),
        ],
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
