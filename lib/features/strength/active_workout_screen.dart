import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/workout_session_repository.dart';
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

class _ActiveWorkoutScreenState extends ConsumerState<ActiveWorkoutScreen>
    with WidgetsBindingObserver {
  final _pc = PageController();
  int _page = 0;
  bool _didInitialJump = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pc.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(restTimerProvider.notifier).reconcile();
    }
  }

  /// The exercise to show next: your current page, or — if it's finished — the
  /// nearest unfinished one after it. Never earlier.
  int _forwardTarget(ActiveWorkoutState s) {
    var t = _page.clamp(0, s.blocks.length - 1);
    while (t < s.blocks.length - 1 && s.blocks[t].isComplete) {
      t++;
    }
    return t;
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

    // When the rest ends: if the exercise you're on is finished, step forward to
    // the next unfinished one. Never scroll backward — staying put is the least
    // surprising thing.
    ref.listen(restTimerProvider, (prev, next) {
      if (prev == null || !prev.active || next.active) return;
      final s = ref.read(activeWorkoutProvider).valueOrNull;
      if (s == null || s.blocks.isEmpty) return;
      final target = _forwardTarget(s);
      if (target != _page) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _jumpTo(target));
      }
    });

    final state = async.valueOrNull;
    final next = (state == null || state.blocks.isEmpty)
        ? null
        : state.blocks[_forwardTarget(state)];

    // The scaffold (and its pager) stays mounted at all times; the rest view is
    // layered on top so the pager never loses its page.
    return Stack(
      children: [
        _buildScaffold(async),
        if (resting)
          RestFullscreen(
            nextExerciseName: next?.exercise.name,
            nextExerciseId: next?.exercise.id,
            nextSetLabel: next == null
                ? null
                : 'Set ${next.completedSets + 1}/${next.targetSets}',
          ),
      ],
    );
  }

  Widget _buildScaffold(AsyncValue<ActiveWorkoutState?> async) {
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
            body: _DonePage(
              onFinish: (notes) => _finish(notes: notes),
              onAdd: _addExercise,
            ),
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
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.75),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
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
                  ],
                ),
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

  Future<void> _finish({String? notes}) async {
    final trimmed = notes?.trim();
    final id = await ref.read(activeWorkoutProvider.notifier).finish(
          notes: (trimmed == null || trimmed.isEmpty) ? null : trimmed,
        );
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

class _DonePage extends StatefulWidget {
  const _DonePage({required this.onFinish, required this.onAdd});
  final ValueChanged<String?> onFinish;
  final VoidCallback onAdd;

  @override
  State<_DonePage> createState() => _DonePageState();
}

class _DonePageState extends State<_DonePage> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          24, 32, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 72, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text('Alle oefeningen klaar', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 24),
          TextField(
            controller: _note,
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Notitie (optioneel)',
              hintText: 'Hoe voelde het? Wat aanpassen volgende keer?',
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              onPressed: () => widget.onFinish(_note.text),
              child: const Text('Dag afronden'),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: widget.onAdd,
            child: const Text('Toch nog een oefening'),
          ),
        ],
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

  /// null → follow the per-block default (warm-up suggested for the first set of
  /// a compound); a bool means the user chose explicitly.
  bool? _warmup;

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
    final warmup =
        _warmup ?? (block.suggestsWarmup && block.completedSets == 0);

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 4, 20, 16 + MediaQuery.viewPaddingOf(context).bottom),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(block.exercise.name,
                      style: theme.textTheme.titleLarge),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.swap_horiz, size: 20),
                tooltip: 'Vervangen',
                onPressed: () => _swapExercise(),
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
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 10,
              children: [
                if (block.exercise.pattern != null)
                  Text(block.exercise.pattern!.label,
                      style: theme.textTheme.bodySmall),
                _LastTimeLabel(exerciseId: block.exercise.id),
              ],
            ),
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
              ActionChip(
                avatar: const Icon(Icons.timer_outlined, size: 16),
                label: const Text('Pauze'),
                visualDensity: VisualDensity.compact,
                onPressed: () => ref
                    .read(restTimerProvider.notifier)
                    .start(block.restBetweenSets),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!block.isComplete) ...[
            if (block.isProgressed)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '▲ Progressie: schema ${block.baseTargetSets}×${block.baseTargetReps}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
              ),
            if (block.suggestsWarmup && block.sets.isEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Tip: begin met 1–2 opwarmsets',
                    style: theme.textTheme.bodySmall),
              ),
              const SizedBox(height: 8),
            ],
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
              onTap: () => setState(() => _warmup = !warmup),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: warmup,
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
                    isWarmup: warmup,
                  );
                  setState(() {
                    _reps = null;
                    _warmup = null;
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

  Future<void> _swapExercise() async {
    final state = ref.read(activeWorkoutProvider).valueOrNull;
    if (state == null || widget.blockIndex >= state.blocks.length) return;
    final block = state.blocks[widget.blockIndex];
    if (block.sets.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Oefening vervangen?'),
          content: Text(
              'De ${block.sets.length} gelogde set(s) van "${block.exercise.name}" gaan verloren.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuleren'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Vervangen'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    final id = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => const ExerciseListScreen(pickMode: true),
      ),
    );
    if (id == null) return;
    await ref
        .read(activeWorkoutProvider.notifier)
        .replaceBlock(widget.blockIndex, id);
    setState(() {
      _reps = null;
      _warmup = null;
    });
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

/// "Vorige keer: 9 · 8 · 8" — the working sets of the last finished session with
/// this exercise. Renders nothing when there is no history.
class _LastTimeLabel extends ConsumerWidget {
  const _LastTimeLabel({required this.exerciseId});
  final int exerciseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final last = ref.watch(lastPerformanceProvider(exerciseId)).valueOrNull;
    if (last == null) return const SizedBox.shrink();
    final reps = last.where((s) => !s.isWarmup).map((s) => s.reps).toList();
    if (reps.isEmpty) return const SizedBox.shrink();
    return Text('Vorige keer: ${reps.join(' · ')}',
        style: Theme.of(context).textTheme.bodySmall);
  }
}
