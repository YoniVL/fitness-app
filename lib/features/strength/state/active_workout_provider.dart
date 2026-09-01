import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/exercise_repository.dart';
import '../../../data/repositories/program_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../data/repositories/workout_session_repository.dart';
import '../../../domain/models/exercise.dart';
import '../../../domain/models/program.dart';
import '../../../domain/models/strength_set.dart';
import '../../../domain/models/workout_session.dart';
import 'rest_timer_notifier.dart';

/// One exercise inside the active session: its (possibly overridden) targets and
/// the sets logged so far. Targets are a per-session copy — editing them never
/// touches the template.
class ExerciseBlock {
  const ExerciseBlock({
    required this.exercise,
    required this.targetSets,
    required this.targetReps,
    this.targetWeight,
    required this.restSeconds,
    this.sets = const [],
  });

  final Exercise exercise;
  final int targetSets;
  final int targetReps;
  final double? targetWeight;
  final int restSeconds;
  final List<StrengthSet> sets;

  int get completedSets => sets.length;
  bool get isComplete => completedSets >= targetSets;

  double get volume =>
      sets.where((s) => !s.isWarmup).fold(0, (sum, s) => sum + s.volume);

  /// Suggested reps/weight for the next set: mirror the last logged set,
  /// otherwise fall back to the target.
  int get suggestedReps => sets.isNotEmpty ? sets.last.reps : targetReps;
  double get suggestedWeight =>
      sets.isNotEmpty ? sets.last.weight : (targetWeight ?? 0);

  ExerciseBlock copyWith({
    int? targetSets,
    int? targetReps,
    Object? targetWeight = _sentinel,
    int? restSeconds,
    List<StrengthSet>? sets,
  }) =>
      ExerciseBlock(
        exercise: exercise,
        targetSets: targetSets ?? this.targetSets,
        targetReps: targetReps ?? this.targetReps,
        targetWeight: identical(targetWeight, _sentinel)
            ? this.targetWeight
            : targetWeight as double?,
        restSeconds: restSeconds ?? this.restSeconds,
        sets: sets ?? this.sets,
      );

  static const _sentinel = Object();
}

class ActiveWorkoutState {
  const ActiveWorkoutState({required this.session, required this.blocks});

  final WorkoutSession session;
  final List<ExerciseBlock> blocks;

  double get totalVolume => blocks.fold(0, (sum, b) => sum + b.volume);
  int get totalSets => blocks.fold(0, (sum, b) => sum + b.completedSets);
  bool get hasAnySet => totalSets > 0;

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

  @override
  Future<ActiveWorkoutState?> build() async {
    final existing = await _sessions.activeSession();
    if (existing == null || existing.discipline != Discipline.strength) {
      return null;
    }
    return _rehydrate(existing);
  }

  Future<ActiveWorkoutState> _rehydrate(WorkoutSession session) async {
    final sets = await _sessions.setsForSession(session.id);
    final byExercise = <int, List<StrengthSet>>{};
    for (final s in sets) {
      byExercise.putIfAbsent(s.exerciseId, () => []).add(s);
    }

    // Prescribed targets, if the session was started from a program day.
    final targets = <int, ProgramExercise>{};
    var restDefault = await ref.read(settingsRepositoryProvider).getInt(
          SettingsKeys.defaultRestSeconds,
          120,
        );
    if (session.programDayId != null) {
      for (final pe in await _programs.exercisesForDay(session.programDayId!)) {
        targets[pe.exerciseId] = pe;
      }
    }

    final exerciseIds = {...byExercise.keys, ...targets.keys};
    final exercises = await _exercises.byIds(exerciseIds);

    final blocks = <ExerciseBlock>[];
    for (final id in exerciseIds) {
      final ex = exercises[id];
      if (ex == null) continue;
      final logged = byExercise[id] ?? const <StrengthSet>[];
      final t = targets[id];
      blocks.add(ExerciseBlock(
        exercise: ex,
        targetSets: t?.targetSets ?? (logged.isEmpty ? 3 : logged.length),
        targetReps: t?.targetReps ?? (logged.isNotEmpty ? logged.last.reps : 10),
        targetWeight: t?.targetWeight ?? (logged.isNotEmpty ? logged.last.weight : null),
        restSeconds: t?.restSeconds ?? restDefault,
        sets: logged,
      ));
    }
    return ActiveWorkoutState(session: session, blocks: blocks);
  }

  bool get hasActiveSession => state.valueOrNull != null;

  // --- Starting -------------------------------------------------------

  Future<void> startEmpty() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final session = await _sessions.startSession(discipline: Discipline.strength);
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
      final exercises = await _exercises.byIds(prescribed.map((e) => e.exerciseId));
      final blocks = <ExerciseBlock>[];
      for (final pe in prescribed) {
        final ex = exercises[pe.exerciseId];
        if (ex == null) continue;
        blocks.add(ExerciseBlock(
          exercise: ex,
          targetSets: pe.targetSets,
          targetReps: pe.targetReps,
          targetWeight: pe.targetWeight,
          restSeconds: pe.restSeconds,
        ));
      }
      return ActiveWorkoutState(session: session, blocks: blocks);
    });
  }

  // --- Editing -------------------------------------------------------

  Future<void> addExercise(int exerciseId) async {
    final current = state.valueOrNull;
    if (current == null) return;
    if (current.blocks.any((b) => b.exercise.id == exerciseId)) return;
    final ex = await _exercises.byId(exerciseId);
    if (ex == null) return;
    final restDefault = await ref
        .read(settingsRepositoryProvider)
        .getInt(SettingsKeys.defaultRestSeconds, 120);
    final last = await _sessions.lastPerformance(exerciseId);
    final block = ExerciseBlock(
      exercise: ex,
      targetSets: last.isNotEmpty ? last.length : 3,
      targetReps: last.isNotEmpty ? last.first.reps : 10,
      targetWeight: last.isNotEmpty ? last.first.weight : null,
      restSeconds: restDefault,
    );
    state = AsyncData(current.copyWith(blocks: [...current.blocks, block]));
  }

  void updateBlockTargets(
    int blockIndex, {
    int? targetSets,
    int? targetReps,
    double? targetWeight,
    int? restSeconds,
  }) {
    final current = state.valueOrNull;
    if (current == null) return;
    final blocks = [...current.blocks];
    blocks[blockIndex] = blocks[blockIndex].copyWith(
      targetSets: targetSets,
      targetReps: targetReps,
      targetWeight: targetWeight,
      restSeconds: restSeconds,
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

  // --- Logging sets --------------------------------------------------

  Future<void> logSet(
    int blockIndex, {
    required int reps,
    required double weight,
    bool isWarmup = false,
  }) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final block = current.blocks[blockIndex];

    final id = await _sessions.addSet(
      sessionId: current.session.id,
      exerciseId: block.exercise.id,
      reps: reps,
      weight: weight,
      isWarmup: isWarmup,
    );
    final newSet = StrengthSet(
      id: id,
      sessionId: current.session.id,
      exerciseId: block.exercise.id,
      setIndex: block.completedSets + 1,
      reps: reps,
      weight: weight,
      isWarmup: isWarmup,
      completedAt: DateTime.now(),
    );
    final blocks = [...current.blocks];
    blocks[blockIndex] = block.copyWith(sets: [...block.sets, newSet]);
    state = AsyncData(current.copyWith(blocks: blocks));

    if (!isWarmup) {
      ref.read(restTimerProvider.notifier).start(block.restSeconds, forSetId: id);
    }
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

  // --- Finishing ----------------------------------------------------

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
