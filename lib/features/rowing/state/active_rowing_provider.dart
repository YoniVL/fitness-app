import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/program_repository.dart';
import '../../../data/repositories/rowing_repository.dart';
import '../../../data/repositories/workout_session_repository.dart';
import '../../../domain/models/program.dart';
import '../../../domain/models/rowing.dart';
import '../../../domain/models/workout_session.dart';
import '../rower_service.dart';

class ActiveRowingState {
  const ActiveRowingState({
    required this.session,
    required this.rowingSessionId,
    required this.segments,
    this.segmentIndex = 0,
    this.elapsed = Duration.zero,
    this.segmentElapsed = Duration.zero,
    this.live,
    this.paused = false,
  });

  final WorkoutSession session;
  final int rowingSessionId;

  /// Program segments, or empty for a free row (one open-ended block).
  final List<ProgramRowSegment> segments;
  final int segmentIndex;
  final Duration elapsed;
  final Duration segmentElapsed;
  final RowerSnapshot? live;
  final bool paused;

  bool get isFreeRow => segments.isEmpty;

  ProgramRowSegment? get currentSegment =>
      segmentIndex >= 0 && segmentIndex < segments.length
          ? segments[segmentIndex]
          : null;

  bool get onLastSegment => segmentIndex >= segments.length - 1;

  Duration? get segmentRemaining {
    final s = currentSegment;
    if (s == null) return null;
    final r = Duration(seconds: s.durationSeconds) - segmentElapsed;
    return r.isNegative ? Duration.zero : r;
  }

  double get plannedTotalSeconds =>
      segments.fold(0, (sum, s) => sum + s.durationSeconds).toDouble();

  ActiveRowingState copyWith({
    int? segmentIndex,
    Duration? elapsed,
    Duration? segmentElapsed,
    RowerSnapshot? live,
    bool? paused,
  }) =>
      ActiveRowingState(
        session: session,
        rowingSessionId: rowingSessionId,
        segments: segments,
        segmentIndex: segmentIndex ?? this.segmentIndex,
        elapsed: elapsed ?? this.elapsed,
        segmentElapsed: segmentElapsed ?? this.segmentElapsed,
        live: live ?? this.live,
        paused: paused ?? this.paused,
      );
}

/// Owns the in-progress rowing session: the segment clock, the live rower
/// snapshot, and periodic sample persistence. Mirrors `ActiveWorkoutController`.
class ActiveRowingController extends AsyncNotifier<ActiveRowingState?> {
  RowingRepository get _rowing => ref.read(rowingRepositoryProvider);
  WorkoutSessionRepository get _sessions =>
      ref.read(workoutSessionRepositoryProvider);
  ProgramRepository get _programs => ref.read(programRepositoryProvider);
  RowerService get _rower => ref.read(rowerServiceProvider);

  Timer? _ticker;
  StreamSubscription<RowerSnapshot>? _sub;
  final List<RowingSample> _pending = [];
  int _lastSampleSecond = -3;

  @override
  Future<ActiveRowingState?> build() async {
    ref.onDispose(() {
      _ticker?.cancel();
      _sub?.cancel();
    });
    final existing = await _sessions.activeSession(discipline: Discipline.rowing);
    if (existing == null) return null;
    return _rehydrate(existing);
  }

  Future<ActiveRowingState> _rehydrate(WorkoutSession session) async {
    final db = await _rowing.rowingDetail(session.id);
    final segments = session.programDayId == null
        ? const <ProgramRowSegment>[]
        : await _programs.rowSegmentsForDay(session.programDayId!);
    final elapsed = DateTime.now().difference(session.startedAt);

    // Walk the segment cursor forward to match the elapsed time.
    var idx = 0;
    var acc = Duration.zero;
    for (var i = 0; i < segments.length; i++) {
      final segDur = Duration(seconds: segments[i].durationSeconds);
      if (acc + segDur > elapsed) {
        idx = i;
        break;
      }
      acc += segDur;
      idx = i;
    }

    final state = ActiveRowingState(
      session: session,
      rowingSessionId: db?.rowing.id ?? 0,
      segments: segments,
      segmentIndex: idx,
      elapsed: elapsed,
      segmentElapsed: elapsed - acc,
    );
    _startEngine();
    return state;
  }

  // --- Starting ----------------------------------------------------

  Future<void> startFromDay(ProgramDay day) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final ids = await _rowing.startSession(programDayId: day.id);
      final segments = await _programs.rowSegmentsForDay(day.id);
      final session = WorkoutSession(
        id: ids.sessionId,
        discipline: Discipline.rowing,
        programDayId: day.id,
        startedAt: DateTime.now(),
      );
      _startEngine();
      return ActiveRowingState(
        session: session,
        rowingSessionId: ids.rowingSessionId,
        segments: segments,
      );
    });
  }

  Future<void> startFree() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final ids = await _rowing.startSession();
      final session = WorkoutSession(
        id: ids.sessionId,
        discipline: Discipline.rowing,
        startedAt: DateTime.now(),
      );
      _startEngine();
      return ActiveRowingState(
        session: session,
        rowingSessionId: ids.rowingSessionId,
        segments: const [],
      );
    });
  }

  /// Starts a session from a one-off workout (from the catalogue, not a plan).
  Future<void> startWorkout(List<ProgramRowSegment> segments) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final ids = await _rowing.startSession();
      final session = WorkoutSession(
        id: ids.sessionId,
        discipline: Discipline.rowing,
        startedAt: DateTime.now(),
      );
      _startEngine();
      return ActiveRowingState(
        session: session,
        rowingSessionId: ids.rowingSessionId,
        segments: segments,
      );
    });
  }

  void _startEngine() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _sub?.cancel();
    _sub = _rower.snapshots.listen(_onSnapshot);
    _rower.connect();
  }

  // --- Live loop -------------------------------------------------

  void _onSnapshot(RowerSnapshot snap) {
    final s = state.valueOrNull;
    if (s == null) return;
    state = AsyncData(s.copyWith(live: snap));
  }

  void _tick() {
    final s = state.valueOrNull;
    if (s == null || s.paused) return;

    var elapsed = s.elapsed + const Duration(seconds: 1);
    var segElapsed = s.segmentElapsed + const Duration(seconds: 1);
    var idx = s.segmentIndex;

    final seg = s.currentSegment;
    if (seg != null &&
        segElapsed.inSeconds >= seg.durationSeconds &&
        !s.onLastSegment) {
      idx += 1;
      segElapsed = Duration.zero;
    }

    state = AsyncData(s.copyWith(
      elapsed: elapsed,
      segmentElapsed: segElapsed,
      segmentIndex: idx,
    ));

    _maybeSample(s.live, elapsed);
  }

  void _maybeSample(RowerSnapshot? live, Duration elapsed) {
    if (live == null) return;
    if (elapsed.inSeconds - _lastSampleSecond < 3) return;
    _lastSampleSecond = elapsed.inSeconds;
    _pending.add(RowingSample(
      id: 0,
      rowingSessionId: state.valueOrNull?.rowingSessionId ?? 0,
      tOffsetMs: elapsed.inMilliseconds,
      strokeRate: live.strokeRate,
      strokeCount: live.strokeCount,
      distanceM: live.distanceM,
      paceSec500m: live.paceSec500m,
      powerW: live.powerW,
      energyKcal: live.energyKcal,
      heartRate: live.heartRate,
    ));
    if (_pending.length >= 10) _flush();
  }

  Future<void> _flush() async {
    final s = state.valueOrNull;
    if (s == null || _pending.isEmpty) return;
    final batch = List<RowingSample>.from(_pending);
    _pending.clear();
    await _rowing.addSamples(s.rowingSessionId, batch);
  }

  // --- Controls -------------------------------------------------

  void togglePause() {
    final s = state.valueOrNull;
    if (s == null) return;
    state = AsyncData(s.copyWith(paused: !s.paused));
  }

  Future<int?> finish({String? notes}) async {
    final s = state.valueOrNull;
    if (s == null) return null;
    _ticker?.cancel();
    _sub?.cancel();
    await _flush();

    final live = s.live;
    final samples = await _rowing.rowingDetail(s.session.id);
    final rates = samples?.samples
            .map((x) => x.strokeRate)
            .whereType<double>()
            .toList() ??
        const <double>[];
    final powers =
        samples?.samples.map((x) => x.powerW).whereType<double>().toList() ??
            const <double>[];
    double mean(List<double> xs) =>
        xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;

    await _rowing.finalize(
      s.session.id,
      distanceM: live?.distanceM ?? 0,
      duration: s.elapsed,
      avgStrokeRate: mean(rates),
      avgPower: mean(powers),
      energyKcal: live?.energyKcal ?? 0,
      notes: notes,
    );
    await _rower.disconnect();

    final dayId = s.session.programDayId;
    if (dayId != null) {
      await _programs.advanceRowingIfCurrentDay(dayId);
      ref.invalidate(activeRowingProgramProvider);
    }
    ref.invalidate(recentSessionsProvider);
    for (final p in rowingProgressProviders) {
      ref.invalidate(p);
    }
    state = const AsyncData(null);
    return s.session.id;
  }

  Future<void> discard() async {
    final s = state.valueOrNull;
    if (s == null) return;
    _ticker?.cancel();
    _sub?.cancel();
    _pending.clear();
    await _rowing.discardSession(s.session.id);
    await _rower.disconnect();
    state = const AsyncData(null);
  }
}

final activeRowingProvider =
    AsyncNotifierProvider<ActiveRowingController, ActiveRowingState?>(
  ActiveRowingController.new,
);
