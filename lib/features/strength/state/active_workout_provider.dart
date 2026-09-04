import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/exercise_repository.dart';
import '../../../data/repositories/program_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../data/repositories/workout_session_repository.dart';
import '../../../domain/models/exercise.dart';
import '../../../domain/models/program.dart';
import '../../../domain/models/strength_set.dart';
import '../../../domain/models/workout_session.dart';
import '../../../domain/progression.dart';
import '../../../domain/taxonomy.dart';
import 'rest_timer_notifier.dart';

/// One exercise inside the active session: its (possibly overridden) targets and
/// the sets logged so far. Targets are a per-session copy — editing them never
/// touches the template.
class ExerciseBlock {
  const ExerciseBlock({
    required this.exercise,
    required this.targetSets,
    required this.targetReps,
    required this.restBetweenSets,
    required this.restAfterExercise,
    int? baseTargetSets,
    int? baseTargetReps,
    this.sets = const [],
  })  : baseTargetSets = baseTargetSets ?? targetSets,
        baseTargetReps = baseTargetReps ?? targetReps;

  final Exercise exercise;
  final int targetSets;
  final int targetReps;

  /// The program's written targets, before auto-progression. Equal to
  /// [targetSets] / [targetReps] for a freestyle exercise.
  final int baseTargetSets;
  final int baseTargetReps;

  final int restBetweenSets;
  final int restAfterExercise;
  final List<StrengthSet> sets;

  int get completedSets => sets.length;
  bool get isComplete => completedSets >= targetSets;

  bool get isProgressed =>
      targetSets > baseTargetSets || targetReps > baseTargetReps;

  /// Whether a couple of warm-up sets are worth suggesting: a compound lift at a
  /// real working-rep range.
  bool get suggestsWarmup =>
      (exercise.pattern?.isCompound ?? false) && targetReps >= 5;

  /// Suggested reps for the next set: mirror the last logged set, else the
  /// target.
  int get suggestedReps => sets.isNotEmpty ? sets.last.reps : targetReps;

  ExerciseBlock copyWith({
    int? targetSets,
    int? targetReps,
    int? restBetweenSets,
    int? restAfterExercise,
    List<StrengthSet>? sets,
  }) =>
      ExerciseBlock(
        exercise: exercise,
        targetSets: targetSets ?? this.targetSets,
        targetReps: targetReps ?? this.targetReps,
        baseTargetSets: baseTargetSets,
        baseTargetReps: baseTargetReps,
        restBetweenSets: restBetweenSets ?? this.restBetweenSets,
        restAfterExercise: restAfterExercise ?? this.restAfterExercise,
        sets: sets ?? this.sets,
      );
}

class ActiveWorkoutState {
  const ActiveWorkoutState({required this.session, required this.blocks});

  final WorkoutSession session;
  final List<ExerciseBlock> blocks;

  int get totalSets => blocks.fold(0, (sum, b) => sum + b.completedSets);
  bool get hasAnySet => totalSets > 0;
  bool get allComplete =>
      blocks.isNotEmpty && blocks.every((b) => b.isComplete);

  /// Index of the exercise the user should be doing now (first not complete),
  /// or -1 when everything is done.
  int get currentBlockIndex => blocks.indexWhere((b) => !b.isComplete);

  ActiveWorkoutState copyWith({List<ExerciseBlock>? blocks}) =>
      ActiveWorkoutState(session: session, blocks: blocks ?? this.blocks);
}

/// Owns the in-progress strength session. Every logged set is written to the DB
/// immediately, so an app kill costs nothing; [build] rehydrates an unfinished
/// session on next launch.
class ActiveWorkoutController extends AsyncNotifier<ActiveWorkoutState?> {
  WorkoutSessionRepository get _sessions =>
      ref.read(workoutSessionRepositoryProvider);
  ExerciseRepository get _exercises => ref.read(exerciseRepositoryProvider);
  ProgramRepository get _programs => ref.read(programRepositoryProvider);
  SettingsRepository get _settings => ref.read(settingsRepositoryProvider);

  @override
  Future<ActiveWorkoutState?> build() async {
    final existing = await _sessions.activeSession();
    if (existing == null || existing.discipline != Discipline.strength) {
      return null;
    }
    return _rehydrate(existing);
  }

  Future<({int between, int after})> _defaultRests() async => (
        between: await _settings.restBetweenSets(),
        after: await _settings.restAfterExercise(),
      );

  /// The active program's round for [programDayId] — 1 for a day that isn't the
  /// active program's current day (redoing an old day gives no progression).
  Future<int> _roundFor(int? programDayId) async {
    if (programDayId == null) return 1;
    final active = await _programs.activeProgram();
    if (active == null || active.currentDay.id != programDayId) return 1;
    return active.round;
  }

  /// The prescribed targets with auto-progression applied for [round] (a no-op
  /// on round 1 or when the setting is off).
  ({int sets, int reps}) _progressed(
      ProgramExercise pe, int round, bool progression) {
    if (round <= 1 || !progression) {
      return (sets: pe.targetSets, reps: pe.targetReps);
    }
    return progressTargets(
        baseSets: pe.targetSets, baseReps: pe.targetReps, round: round);
  }

  Future<ActiveWorkoutState> _rehydrate(WorkoutSession session) async {
    final sets = await _sessions.setsForSession(session.id);
    final byExercise = <int, List<StrengthSet>>{};
    for (final s in sets) {
      byExercise.putIfAbsent(s.exerciseId, () => []).add(s);
    }

    final targets = <int, ProgramExercise>{};
    final order = <int>[];
    if (session.programDayId != null) {
      for (final pe in await _programs.exercisesForDay(session.programDayId!)) {
        targets[pe.exerciseId] = pe;
        order.add(pe.exerciseId);
      }
    }
    for (final id in byExercise.keys) {
      if (!order.contains(id)) order.add(id);
    }

    final rests = await _defaultRests();
    final exercises = await _exercises.byIds(order);
    final round = await _roundFor(session.programDayId);
    final progression = round > 1 && await _settings.autoProgression();

    final blocks = <ExerciseBlock>[];
    for (final id in order) {
      final ex = exercises[id];
      if (ex == null) continue;
      final logged = byExercise[id] ?? const <StrengthSet>[];
      final t = targets[id];
      final prog =
          t == null ? null : _progressed(t, round, progression);
      blocks.add(ExerciseBlock(
        exercise: ex,
        targetSets: prog?.sets ?? (logged.isEmpty ? 3 : logged.length),
        targetReps:
            prog?.reps ?? (logged.isNotEmpty ? logged.last.reps : 10),
        baseTargetSets: t?.targetSets,
        baseTargetReps: t?.targetReps,
        restBetweenSets: t?.restBetweenSets ?? rests.between,
        restAfterExercise: t?.restAfterExercise ?? rests.after,
        sets: logged,
      ));
    }
    return ActiveWorkoutState(session: session, blocks: blocks);
  }

  // --- Starting -----------------------------------------------------

  Future<void> startEmpty() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final session =
          await _sessions.startSession(discipline: Discipline.strength);
      return ActiveWorkoutState(session: session, blocks: const []);
    });
  }

  Future<void> startFromDay(ProgramDay day) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final session = await _sessions.startSession(
        discipline: Discipline.strength,
        programDayId: day.id,
      );
      final prescribed = await _programs.exercisesForDay(day.id);
      final rests = await _defaultRests();
      final exercises =
          await _exercises.byIds(prescribed.map((e) => e.exerciseId));
      final round = await _roundFor(day.id);
      final progression = round > 1 && await _settings.autoProgression();
      final blocks = <ExerciseBlock>[];
      for (final pe in prescribed) {
        final ex = exercises[pe.exerciseId];
        if (ex == null) continue;
        final prog = _progressed(pe, round, progression);
        blocks.add(ExerciseBlock(
          exercise: ex,
          targetSets: prog.sets,
          targetReps: prog.reps,
          baseTargetSets: pe.targetSets,
          baseTargetReps: pe.targetReps,
          restBetweenSets: pe.restBetweenSets,
          restAfterExercise: pe.restAfterExercise ?? rests.after,
        ));
      }
      return ActiveWorkoutState(session: session, blocks: blocks);
    });
  }

  // --- Editing -----------------------------------------------------

  Future<void> addExercise(int exerciseId) async {
    final current = state.valueOrNull;
    if (current == null) return;
    if (current.blocks.any((b) => b.exercise.id == exerciseId)) return;
    final ex = await _exercises.byId(exerciseId);
    if (ex == null) return;
    final rests = await _defaultRests();
    final last = await _sessions.lastPerformance(exerciseId);
    final block = ExerciseBlock(
      exercise: ex,
      targetSets: last.isNotEmpty ? last.length : 3,
      targetReps: last.isNotEmpty
          ? last.first.reps
          : (ex.isTimeBased ? defaultHoldSeconds : 10),
      restBetweenSets: rests.between,
      restAfterExercise: rests.after,
    );
    state = AsyncData(current.copyWith(blocks: [...current.blocks, block]));
  }

  /// Reorders the in-session exercise list (drag in the overview). The DB order
  /// isn't touched — it only matters for the template.
  void moveBlock(int from, int to) {
    final current = state.valueOrNull;
    if (current == null) return;
    if (from < 0 || from >= current.blocks.length) return;
    final blocks = [...current.blocks];
    final b = blocks.removeAt(from);
    blocks.insert(to.clamp(0, blocks.length), b);
    state = AsyncData(current.copyWith(blocks: blocks));
  }

  void updateBlockTargets(
    int blockIndex, {
    int? targetSets,
    int? targetReps,
    int? restBetweenSets,
    int? restAfterExercise,
  }) {
    final current = state.valueOrNull;
    if (current == null) return;
    final blocks = [...current.blocks];
    blocks[blockIndex] = blocks[blockIndex].copyWith(
      targetSets: targetSets,
      targetReps: targetReps,
      restBetweenSets: restBetweenSets,
      restAfterExercise: restAfterExercise,
    );
    state = AsyncData(current.copyWith(blocks: blocks));
  }

  Future<void> removeBlock(int blockIndex) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final block = current.blocks[blockIndex];
    for (final s in block.sets) {
      await _sessions.deleteSet(s.id);
    }
    final blocks = [...current.blocks]..removeAt(blockIndex);
    state = AsyncData(current.copyWith(blocks: blocks));
  }

  /// Swaps the exercise of [blockIndex] for [newExerciseId], keeping its
  /// position. Any sets already logged for the old exercise are discarded.
  Future<void> replaceBlock(int blockIndex, int newExerciseId) async {
    final current = state.valueOrNull;
    if (current == null) return;
    if (blockIndex < 0 || blockIndex >= current.blocks.length) return;
    final old = current.blocks[blockIndex];
    if (old.exercise.id == newExerciseId) return;
    if (current.blocks
        .any((b) => b != old && b.exercise.id == newExerciseId)) {
      return;
    }
    final ex = await _exercises.byId(newExerciseId);
    if (ex == null) return;
    for (final s in old.sets) {
      await _sessions.deleteSet(s.id);
    }
    final last = await _sessions.lastPerformance(newExerciseId);
    final blocks = [...current.blocks];
    blocks[blockIndex] = ExerciseBlock(
      exercise: ex,
      targetSets: last.isNotEmpty ? last.length : old.targetSets,
      targetReps: last.isNotEmpty ? last.first.reps : old.targetReps,
      restBetweenSets: old.restBetweenSets,
      restAfterExercise: old.restAfterExercise,
    );
    state = AsyncData(current.copyWith(blocks: blocks));
  }

  // --- Logging sets -----------------------------------------------

  Future<void> logSet(
    int blockIndex, {
    required int reps,
    bool isWarmup = false,
  }) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final block = current.blocks[blockIndex];

    final id = await _sessions.addSet(
      sessionId: current.session.id,
      exerciseId: block.exercise.id,
      reps: reps,
      isWarmup: isWarmup,
    );
    final newSet = StrengthSet(
      id: id,
      sessionId: current.session.id,
      exerciseId: block.exercise.id,
      setIndex: block.completedSets + 1,
      reps: reps,
      isWarmup: isWarmup,
      completedAt: DateTime.now(),
    );
    final blocks = [...current.blocks];
    final updatedBlock = block.copyWith(sets: [...block.sets, newSet]);
    blocks[blockIndex] = updatedBlock;
    final next = current.copyWith(blocks: blocks);
    state = AsyncData(next);

    if (isWarmup) return;

    final wasLastSet = updatedBlock.isComplete;
    final everythingDone = next.allComplete;
    if (everythingDone) return; // no timer — surface "Dag afronden"

    final seconds =
        wasLastSet ? block.restAfterExercise : block.restBetweenSets;
    ref.read(restTimerProvider.notifier).start(seconds, forSetId: id);
  }

  Future<void> undoLastSet(int blockIndex) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final block = current.blocks[blockIndex];
    if (block.sets.isEmpty) return;
    final last = block.sets.last;
    await _sessions.deleteSet(last.id);
    final blocks = [...current.blocks];
    blocks[blockIndex] =
        block.copyWith(sets: block.sets.sublist(0, block.sets.length - 1));
    state = AsyncData(current.copyWith(blocks: blocks));
  }

  // --- Finishing --------------------------------------------------

  /// Ends the session. Returns the session id, or null if it was discarded
  /// (no sets logged → the empty session row is deleted).
  Future<int?> finish({String? notes}) async {
    final current = state.valueOrNull;
    if (current == null) return null;
    ref.read(restTimerProvider.notifier).cancel();
    if (!current.hasAnySet) {
      await _sessions.deleteSession(current.session.id);
      state = const AsyncData(null);
      return null;
    }
    await _sessions.finishSession(current.session.id, notes: notes);
    final dayId = current.session.programDayId;
    if (dayId != null) {
      await _programs.advanceIfCurrentDay(dayId);
      ref.invalidate(activeProgramProvider);
    }
    ref.invalidate(recentSessionsProvider);
    state = const AsyncData(null);
    return current.session.id;
  }

  Future<void> discard() async {
    final current = state.valueOrNull;
    if (current == null) return;
    ref.read(restTimerProvider.notifier).cancel();
    await _sessions.deleteSession(current.session.id);
    state = const AsyncData(null);
  }
}

final activeWorkoutProvider =
    AsyncNotifierProvider<ActiveWorkoutController, ActiveWorkoutState?>(
  ActiveWorkoutController.new,
);
