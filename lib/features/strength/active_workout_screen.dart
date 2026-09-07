import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/theme.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/workout_session_repository.dart';
import '../../domain/models/exercise.dart';
import '../../ui/async_view.dart';
import '../../ui/confirm_dialog.dart';
import '../../ui/spacing.dart';
import '../exercises/exercise_media.dart';
import '../library/exercise_list_screen.dart';
import 'state/active_workout_provider.dart';
import 'state/rest_timer_notifier.dart';
import 'widgets/number_stepper.dart';
import 'widgets/rest_fullscreen.dart';

String _mmss(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

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
    // Keep the screen on for the whole workout — you shouldn't have to wake the
    // phone between every set. Matches the live rowing screen.
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    _pc.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      WakelockPlus.enable();
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
    return async.view(
      loading: () => const Scaffold(body: LoadingBox(height: 240)),
      error: (e) =>
          const Scaffold(body: Center(child: ErrorBox(message: 'Fout'))),
      (state) {
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

        final prevName =
            _page > 0 ? state.blocks[_page - 1].exercise.name : null;
        final nextName = _page < state.blocks.length - 1
            ? state.blocks[_page + 1].exercise.name
            : null;

        return Scaffold(
          appBar: _appBar(state),
          bottomNavigationBar: _PrevNextBar(
            prevName: prevName,
            nextName: nextName,
            onPrev: _page > 0 ? () => _jumpTo(_page - 1) : null,
            onNext: _page < state.blocks.length - 1
                ? () => _jumpTo(_page + 1)
                : null,
          ),
          body: Column(
            children: [
              _ProgressBar(state: state, current: _page),
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
                    onSwap: () => _swapExercise(i),
                    onEdit: (b) => _editTargets(i, b),
                    onOverview: _showOverview,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  PreferredSizeWidget _appBar(ActiveWorkoutState state) {
    final theme = Theme.of(context);
    return AppBar(
      titleSpacing: 0,
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Sluiten',
        onPressed: () => context.canPop()
            ? context.pop()
            : context.go('/strength/today'),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Training', style: theme.textTheme.titleMedium),
          if (state.blocks.isNotEmpty)
            Text(
              'OEFENING ${_page + 1} VAN ${state.blocks.length}',
              style: theme.textTheme.labelSmall
                  ?.copyWith(fontSize: 10, letterSpacing: 1.2),
            ),
        ],
      ),
      actions: [
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
  }

  Future<void> _showOverview() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final blocks =
              ref.watch(activeWorkoutProvider).valueOrNull?.blocks ?? const [];
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.75),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: ReorderableListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      buildDefaultDragHandles: false,
                      itemCount: blocks.length,
                      onReorderItem: (oldIndex, newIndex) {
                        ref
                            .read(activeWorkoutProvider.notifier)
                            .moveBlock(oldIndex, newIndex);
                      },
                      itemBuilder: (context, i) => ListTile(
                        key: ValueKey(blocks[i].exercise.id),
                        leading: Icon(blocks[i].isComplete
                            ? Icons.check_circle
                            : Icons.circle_outlined),
                        title: Text(blocks[i].exercise.name),
                        subtitle: Text(
                            '${blocks[i].completedSets}/${blocks[i].targetSets} sets'),
                        trailing: ReorderableDragStartListener(
                          index: i,
                          child: const Icon(Icons.drag_handle),
                        ),
                        selected: i == _page,
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _jumpTo(i);
                        },
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('Oefening toevoegen'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _addExercise();
                    },
                  ),
                ],
              ),
            ),
          );
        },
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
      context.pushReplacement('/strength/log/session/$id');
    } else {
      context.go('/strength/today');
    }
  }

  Future<void> _discard() async {
    final ok = await confirmDialog(
      context,
      title: 'Training weggooien?',
      message: 'Alle gelogde sets van deze sessie gaan verloren.',
      confirmLabel: 'Weggooien',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(activeWorkoutProvider.notifier).discard();
    if (mounted) context.go('/strength/today');
  }

  Future<void> _swapExercise(int blockIndex) async {
    final state = ref.read(activeWorkoutProvider).valueOrNull;
    if (state == null || blockIndex >= state.blocks.length) return;
    final block = state.blocks[blockIndex];
    if (block.sets.isNotEmpty) {
      final ok = await confirmDialog(
        context,
        title: 'Oefening vervangen?',
        message:
            'De ${block.sets.length} gelogde set(s) van "${block.exercise.name}" gaan verloren.',
        confirmLabel: 'Vervangen',
      );
      if (!ok) return;
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
        .replaceBlock(blockIndex, id);
  }

  Future<void> _editTargets(int blockIndex, ExerciseBlock block) async {
    final sets = ValueNotifier<double>(block.targetSets.toDouble());
    final reps = ValueNotifier<double>(block.targetReps.toDouble());
    final restSet = ValueNotifier<double>(block.restBetweenSets.toDouble());
    final restEx = ValueNotifier<double>(block.restAfterExercise.toDouble());
    final isTime = block.exercise.isTimeBased;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(block.exercise.name),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogRow('Sets', sets, step: 1, min: 1, max: 10),
              _dialogRow(
                block.exercise.repsFieldLabel,
                reps,
                step: isTime ? 5 : 1,
                min: isTime ? 5 : 1,
                max: isTime ? 300 : 50,
              ),
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
            child: const Text('ANNULEREN'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(activeWorkoutProvider.notifier).updateBlockTargets(
                    blockIndex,
                    targetSets: sets.value.round(),
                    targetReps: reps.value.round(),
                    restBetweenSets: restSet.value.round(),
                    restAfterExercise: restEx.value.round(),
                  );
              Navigator.pop(context);
            },
            child: const Text('OPSLAAN'),
          ),
        ],
      ),
    );
  }

  Widget _dialogRow(String label, ValueNotifier<double> notifier,
      {required double step, required double min, required double max}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
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

/// The full-width segmented progress bar — one cell per exercise, accent when
/// that exercise is done, line otherwise.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.state, required this.current});
  final ActiveWorkoutState state;
  final int current;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          for (var i = 0; i < state.blocks.length; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              child: Container(
                height: 4,
                color: state.blocks[i].isComplete
                    ? p.accent
                    : i == current
                        ? p.mute
                        : p.line,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The pinned prev / next exercise bar at the bottom of the pager.
class _PrevNextBar extends StatelessWidget {
  const _PrevNextBar({
    required this.prevName,
    required this.nextName,
    required this.onPrev,
    required this.onNext,
  });
  final String? prevName;
  final String? nextName;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final style = Theme.of(context)
        .textTheme
        .labelMedium
        ?.copyWith(color: p.ink, fontWeight: FontWeight.w700);
    return Container(
      decoration: BoxDecoration(
        color: p.ground,
        border: Border(top: BorderSide(color: p.rule, width: 2)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onPrev,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      border: Border(right: BorderSide(color: p.line)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.chevron_left,
                            size: 18,
                            color: onPrev == null ? p.line : p.mute),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(prevName ?? '',
                              overflow: TextOverflow.ellipsis,
                              style: style?.copyWith(
                                  color: onPrev == null ? p.line : p.ink)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: onNext,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text(nextName ?? '',
                              textAlign: TextAlign.right,
                              overflow: TextOverflow.ellipsis,
                              style: style?.copyWith(
                                  color: onNext == null ? p.line : p.ink)),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.chevron_right,
                            size: 18,
                            color: onNext == null ? p.line : p.mute),
                      ],
                    ),
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

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.onAdd});
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Nog geen oefeningen.'),
              Gap.m,
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('OEFENING TOEVOEGEN'),
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
    final p = context.palette;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          16, 28, 16, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle, size: 48, color: p.accent),
          Gap.m,
          Text('Alle oefeningen klaar', style: theme.textTheme.headlineSmall),
          Gap.xl,
          TextField(
            controller: _note,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Notitie (optioneel)',
              hintText: 'Hoe voelde het? Wat aanpassen volgende keer?',
            ),
          ),
          Gap.l,
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => widget.onFinish(_note.text),
              child: Row(
                children: const [
                  Expanded(child: Text('DAG AFRONDEN')),
                  Icon(Icons.check, size: 18),
                ],
              ),
            ),
          ),
          Gap.s,
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
    required this.onSwap,
    required this.onEdit,
    required this.onOverview,
  });

  final int blockIndex;
  final bool isLast;
  final VoidCallback onNext;
  final VoidCallback onFinish;
  final VoidCallback onSwap;
  final void Function(ExerciseBlock block) onEdit;
  final VoidCallback onOverview;

  @override
  ConsumerState<_ExercisePage> createState() => _ExercisePageState();
}

class _ExercisePageState extends ConsumerState<_ExercisePage> {
  double? _reps;
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
    final p = context.palette;
    final reps = _reps ??= block.suggestedReps.toDouble();
    final suggestWarmup = block.suggestsWarmup &&
        (ref.watch(warmupSuggestionsProvider).valueOrNull ?? false);
    final warmup = _warmup ?? (suggestWarmup && block.completedSets == 0);
    final owned = ref.watch(ownedEquipmentProvider).valueOrNull;
    final missingGear = owned != null && !block.exercise.canPerformWith(owned);
    final isTime = block.exercise.isTimeBased;

    final last = ref.watch(lastPerformanceProvider(block.exercise.id)).valueOrNull;
    final lastReps =
        last?.where((s) => !s.isWarmup).map((s) => s.reps).toList() ?? const [];

    return Column(
      children: [
        // Tag row + title
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (block.exercise.pattern != null)
                    _Tag(block.exercise.pattern!.label, filled: true),
                  for (final g in block.exercise.equipmentTags.take(2))
                    _Tag(g),
                  if (block.isProgressed)
                    _Tag(
                        'schema ${block.baseTargetSets}×${block.exercise.formatReps(block.baseTargetReps)}',
                        accent: true),
                  if (missingGear) _Tag('materiaal ontbreekt', accent: true),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(block.exercise.name,
                        style: theme.textTheme.headlineMedium),
                  ),
                  IconButton(
                    icon: const Icon(Icons.swap_horiz),
                    tooltip: 'Vervangen',
                    onPressed: widget.onSwap,
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit') widget.onEdit(block);
                      if (v == 'remove') {
                        notifier.removeBlock(widget.blockIndex);
                      }
                      if (v == 'overview') widget.onOverview();
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'edit', child: Text('Aanpassen')),
                      PopupMenuItem(
                          value: 'overview', child: Text('Overzicht')),
                      PopupMenuItem(
                          value: 'remove', child: Text('Verwijderen')),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),

        // Demo panel
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          height: 128,
          decoration: BoxDecoration(
            color: p.surface,
            border: Border(
              top: BorderSide(color: p.rule, width: 2),
              bottom: BorderSide(color: p.rule, width: 2),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Center(
            child: hasExercisePhoto(block.exercise.name)
                ? ExerciseDemo(
                    exerciseName: block.exercise.name, maxHeight: 108)
                : Row(
                    children: [
                      Expanded(
                        child: Text('GEEN DEMO BESCHIKBAAR',
                            style: theme.textTheme.labelSmall?.copyWith(
                                fontSize: 10, letterSpacing: 1.2)),
                      ),
                      Icon(Icons.fitness_center, size: 40, color: p.line),
                    ],
                  ),
          ),
        ),

        // Set list
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            children: [
              Row(
                children: [
                  SizedBox(
                      width: 40,
                      child: Text('REEKS', style: _hdr(context))),
                  Expanded(child: Text(block.exercise.repsFieldLabel.toUpperCase(),
                      style: _hdr(context))),
                  SizedBox(
                      width: 34,
                      child: Text('OK',
                          textAlign: TextAlign.right, style: _hdr(context))),
                ],
              ),
              for (var i = 0; i < block.targetSets; i++)
                _SetRow(
                  index: i,
                  state: i < block.completedSets
                      ? _SetRowState.done
                      : i == block.completedSets && !block.isComplete
                          ? _SetRowState.active
                          : _SetRowState.upcoming,
                  doneReps: i < block.sets.length
                      ? block.sets[i].reps
                      : block.targetReps,
                  isWarmupDone:
                      i < block.sets.length && block.sets[i].isWarmup,
                  format: block.exercise.formatReps,
                  activePanel: i == block.completedSets && !block.isComplete
                      ? _ActiveSetPanel(
                          setNumber: i + 1,
                          lastReps: lastReps,
                          format: block.exercise.formatReps,
                          reps: reps,
                          isTime: isTime,
                          warmup: warmup,
                          showWarmup: suggestWarmup || _warmup != null,
                          onReps: (v) => setState(() => _reps = v),
                          onWarmup: (v) => setState(() => _warmup = v),
                        )
                      : null,
                ),
              if (block.sets.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: TextButton.icon(
                    icon: const Icon(Icons.undo, size: 16),
                    label: const Text('Wis laatste set'),
                    onPressed: () => notifier.undoLastSet(widget.blockIndex),
                  ),
                ),
            ],
          ),
        ),

        // Actions
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => ref
                          .read(restTimerProvider.notifier)
                          .start(block.restBetweenSets),
                      child: Row(
                        children: [
                          const Expanded(child: Text('RUSTTIMER')),
                          Text(_mmss(block.restBetweenSets),
                              style: AppTheme.numeric(size: 18, color: p.ink)),
                        ],
                      ),
                    ),
                  ),
                  Gap.s,
                  SizedBox(
                    width: 52,
                    height: 48,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero),
                      onPressed: widget.onOverview,
                      child: const Icon(Icons.list, size: 20),
                    ),
                  ),
                ],
              ),
              Gap.s,
              if (!block.isComplete)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
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
                    child: Row(
                      children: const [
                        Expanded(child: Text('REEKS KLAAR')),
                        Icon(Icons.check, size: 20),
                      ],
                    ),
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: widget.isLast ? widget.onFinish : widget.onNext,
                    child: Row(
                      children: [
                        Expanded(
                            child: Text(widget.isLast
                                ? 'DAG AFRONDEN'
                                : 'VOLGENDE OEFENING')),
                        Icon(
                            widget.isLast
                                ? Icons.check
                                : Icons.arrow_forward,
                            size: 18),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

TextStyle? _hdr(BuildContext context) =>
    Theme.of(context).textTheme.labelSmall?.copyWith(
        fontSize: 9,
        letterSpacing: 1.1,
        color: context.palette.mute);

enum _SetRowState { done, active, upcoming }

class _SetRow extends StatelessWidget {
  const _SetRow({
    required this.index,
    required this.state,
    required this.doneReps,
    required this.isWarmupDone,
    required this.format,
    this.activePanel,
  });

  final int index;
  final _SetRowState state;
  final int doneReps;
  final bool isWarmupDone;
  final String Function(int) format;
  final Widget? activePanel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (state == _SetRowState.active && activePanel != null) return activePanel!;

    final done = state == _SetRowState.done;
    final label = (index + 1).toString().padLeft(2, '0');
    return Opacity(
      opacity: done ? 0.55 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: p.line)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: Text(label,
                  style: AppTheme.numeric(size: 16, color: p.ink)
                      .copyWith(letterSpacing: 0)),
            ),
            Expanded(
              child: Text(
                '${format(doneReps)}${isWarmupDone ? '  W' : ''}',
                style: AppTheme.numeric(size: 20, color: done ? p.ink : p.mute)
                    .copyWith(
                        letterSpacing: 0,
                        fontWeight:
                            done ? FontWeight.w800 : FontWeight.w700),
              ),
            ),
            SizedBox(
              width: 34,
              child: done
                  ? Align(
                      alignment: Alignment.centerRight,
                      child: Icon(Icons.check, size: 18, color: p.accent),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveSetPanel extends StatelessWidget {
  const _ActiveSetPanel({
    required this.setNumber,
    required this.lastReps,
    required this.format,
    required this.reps,
    required this.isTime,
    required this.warmup,
    required this.showWarmup,
    required this.onReps,
    required this.onWarmup,
  });

  final int setNumber;
  final List<int> lastReps;
  final String Function(int) format;
  final double reps;
  final bool isTime;
  final bool warmup;
  final bool showWarmup;
  final ValueChanged<double> onReps;
  final ValueChanged<bool> onWarmup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.accent, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  'REEKS ${setNumber.toString().padLeft(2, '0')} · ACTIEF',
                  style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 10, letterSpacing: 1.3, color: p.accent),
                ),
              ),
              if (lastReps.isNotEmpty)
                Text(
                  'VORIGE: ${lastReps.map(format).join(' · ')}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(fontSize: 10, letterSpacing: 0.6),
                ),
            ],
          ),
          const SizedBox(height: 10),
          NumberStepper(
            label: isTime ? 'Seconden' : 'Reps',
            value: reps,
            step: isTime ? 5 : 1,
            min: isTime ? 5 : 1,
            max: isTime ? 300 : 100,
            onChanged: onReps,
          ),
          if (showWarmup) ...[
            const SizedBox(height: 4),
            InkWell(
              onTap: () => onWarmup(!warmup),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: warmup,
                    onChanged: (v) => onWarmup(v ?? false),
                  ),
                  const Text('Opwarmset'),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// An all-caps micro tag — accent-filled for the movement pattern, outlined
/// for muscles, accent-text for warnings.
class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.filled = false, this.accent = false});
  final String text;
  final bool filled;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: 10,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w700,
          color: filled
              ? p.accentInk
              : accent
                  ? p.accent
                  : p.mute,
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? p.accent : null,
        border: filled ? null : Border.all(color: accent ? p.accent : p.line),
      ),
      child: Text(text.toUpperCase(), style: style),
    );
  }
}
