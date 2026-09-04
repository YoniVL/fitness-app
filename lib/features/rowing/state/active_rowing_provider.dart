import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/program_repository.dart';
import '../../../data/repositories/rowing_repository.dart';
import '../../../data/repositories/workout_session_repository.dart';
import '../../../domain/models/program.dart';
import '../../../domain/models/rowing.dart';
import '../../../domain/models/workout_session.dart';
import '../rower_service.dart';
import '../rowing_cues.dart';

/// Turns a trainer's cumulative counter into a session-relative one.
///
/// Some FTMS rowers report `Total Distance` / `Total Energy` as a lifetime
/// odometer that is already in the tens of kilometres when a session starts, and
/// some reset it to 0 on reconnect. This keeps the value starting at 0 for the
/// session and only moving in physically plausible steps — any backward jump or
/// implausibly large forward jump is absorbed into the baseline instead of shown.
class RowerOdometer {
  RowerOdometer(this.maxStep);

  /// Largest believable increase between two consecutive (~1 s) frames.
  final double maxStep;

  double? _baseline;
  double? _prevRaw;

  double normalise(double raw) {
    // A small first reading is a genuine near-zero start; a large one is the
    // trainer's odometer, so anchor the baseline to it.
    _baseline ??= raw > maxStep ? raw : 0;
    final prev = _prevRaw;
    _prevRaw = raw;
    if (prev != null) {
      final step = raw - prev;
      if (step < 0 || step > maxStep) _baseline = _baseline! + step;
    }
    final out = raw - _baseline!;
    return out < 0 ? 0 : out;
  }
}

/// Why the session clock is stopped.
enum PauseReason {
  none,

  /// The user tapped Pauze.
  user,

  /// No data from the trainer for a while — auto-resumes when it returns.
  idle,

  /// The app went to the background — stays paused until the user resumes.
  background,
}

class ActiveRowingState {
  const ActiveRowingState({
    required this.session,
    required this.rowingSessionId,
    required this.segments,
    this.segmentIndex = 0,
    this.elapsed = Duration.zero,
    this.segmentElapsed = Duration.zero,
    this.live,
    this.pausedReason = PauseReason.none,
  });

  final WorkoutSession session;
  final int rowingSessionId;

  /// Program segments, or empty for a free row (one open-ended block).
  final List<ProgramRowSegment> segments;
  final int segmentIndex;
  final Duration elapsed;
  final Duration segmentElapsed;
  final RowerSnapshot? live;
  final PauseReason pausedReason;

  bool get paused => pausedReason != PauseReason.none;

  bool get isFreeRow => segments.isEmpty;

  /// 0..1 position within the planned session, by the segment cursor (not wall
  /// clock) so the profile marker lines up with the current block.
  double get segmentProgressFraction {
    final total = plannedTotalSeconds;
    if (total <= 0) return 0;
    var before = 0;
    for (var i = 0; i < segmentIndex && i < segments.length; i++) {
      before += segments[i].durationSeconds;
    }
    return ((before + segmentElapsed.inSeconds) / total).clamp(0.0, 1.0);
  }

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
    PauseReason? pausedReason,
  }) =>
      ActiveRowingState(
        session: session,
        rowingSessionId: rowingSessionId,
        segments: segments,
        segmentIndex: segmentIndex ?? this.segmentIndex,
        elapsed: elapsed ?? this.elapsed,
        segmentElapsed: segmentElapsed ?? this.segmentElapsed,
        live: live ?? this.live,
        pausedReason: pausedReason ?? this.pausedReason,
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

  /// When the trainer last sent data (null until the first frame), and when the
  /// distance last moved. Either going stale auto-pauses the session — some
  /// trainers keep streaming zero-frames when you stop rowing.
  DateTime? _lastDataAt;
  DateTime? _lastMoveAt;
  double _lastDistance = 0;
  static const _idleTimeout = Duration(seconds: 8);
  static const _stallTimeout = Duration(seconds: 10);

  /// Reset per session — see [RowerOdometer].
  RowerOdometer _distOdo = RowerOdometer(500);
  RowerOdometer _energyOdo = RowerOdometer(20);

  /// The segment index we've already played the pre-switch beep for.
  int _preBeepedFor = -1;

  RowingCues get _cues => ref.read(rowingCuesProvider);

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
    final segments = session.programDayId != null
        ? await _programs.rowSegmentsForDay(session.programDayId!)
        : (db?.rowing.segmentsJson?.isNotEmpty ?? false)
            ? decodeRowSegments(db!.rowing.segmentsJson!)
            : const <ProgramRowSegment>[];
    // Prefer the live-checkpointed elapsed (excludes time away) over wall clock.
    final checkpointMs = db?.rowing.activeElapsedMs ?? 0;
    final elapsed = checkpointMs > 0
        ? Duration(milliseconds: checkpointMs)
        : DateTime.now().difference(session.startedAt);

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
      final ids = await _rowing.startSession(
          programDayId: day.id, kind: day.rowSessionType);
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
  /// The segments are persisted as JSON so the structure survives an app kill.
  Future<void> startWorkout(
    List<ProgramRowSegment> segments, {
    String? kind,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final ids = await _rowing.startSession(
        segmentsJson: encodeRowSegments(segments),
        kind: kind,
      );
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
    _distOdo = RowerOdometer(500);
    _energyOdo = RowerOdometer(20);
    _sub = _rower.snapshots.listen(_onSnapshot);
    _rower.connect();
  }

  /// Rewrites the trainer's cumulative distance/energy to session-relative
  /// values (the FS-057453 reports a lifetime odometer).
  RowerSnapshot _normalise(RowerSnapshot r) {
    if (r.distanceM == null && r.energyKcal == null) return r;
    return RowerSnapshot(
      strokeRate: r.strokeRate,
      strokeCount: r.strokeCount,
      distanceM:
          r.distanceM == null ? null : _distOdo.normalise(r.distanceM!),
      paceSec500m: r.paceSec500m,
      powerW: r.powerW,
      energyKcal:
          r.energyKcal == null ? null : _energyOdo.normalise(r.energyKcal!),
      heartRate: r.heartRate,
      elapsedSeconds: r.elapsedSeconds,
    );
  }

  // --- Live loop -------------------------------------------------

  void _onSnapshot(RowerSnapshot raw) {
    final s = state.valueOrNull;
    if (s == null) return;
    final snap = _normalise(raw);
    final now = DateTime.now();
    _lastDataAt = now;
    final d = snap.distanceM ?? 0;
    final moving = d > _lastDistance + 0.5 || (snap.strokeRate ?? 0) > 1;
    if (moving) {
      _lastMoveAt = now;
      _lastDistance = d;
    }
    _lastMoveAt ??= now;
    // Rowing resumed → lift an idle auto-pause (not a user/background one).
    final reason = (s.pausedReason == PauseReason.idle && moving)
        ? PauseReason.none
        : s.pausedReason;
    state = AsyncData(s.copyWith(live: snap, pausedReason: reason));
  }

  void _tick() {
    final s = state.valueOrNull;
    if (s == null) return;

    // Auto-pause when the trainer goes quiet, or keeps streaming but you've
    // stopped rowing (distance not moving) — unless a planned rest is running.
    final now = DateTime.now();
    final noData =
        _lastDataAt != null && now.difference(_lastDataAt!) > _idleTimeout;
    final stalled = _lastMoveAt != null &&
        now.difference(_lastMoveAt!) > _stallTimeout &&
        !(s.currentSegment?.isRest ?? false);
    if (!s.paused && (noData || stalled)) {
      state = AsyncData(s.copyWith(pausedReason: PauseReason.idle));
      return;
    }
    if (s.paused) return;

    var elapsed = s.elapsed + const Duration(seconds: 1);
    var segElapsed = s.segmentElapsed + const Duration(seconds: 1);
    var idx = s.segmentIndex;

    final seg = s.currentSegment;
    if (seg != null &&
        segElapsed.inSeconds >= seg.durationSeconds &&
        !s.onLastSegment) {
      idx += 1;
      segElapsed = Duration.zero;
      _cues.onSwitch();
    } else if (seg != null &&
        !s.onLastSegment &&
        _preBeepedFor != idx &&
        seg.durationSeconds - segElapsed.inSeconds <= 10) {
      _preBeepedFor = idx;
      _cues.preSwitch();
    }

    state = AsyncData(s.copyWith(
      elapsed: elapsed,
      segmentElapsed: segElapsed,
      segmentIndex: idx,
    ));

    _maybeSample(s.live, elapsed);
    if (elapsed.inSeconds % 10 == 0) {
      _rowing.checkpointElapsed(s.session.id, elapsed);
    }
  }

  /// The app went to the background — pause and stay paused until the user
  /// taps Hervat (per the iteration-5 plan: no background running).
  void markBackgrounded() {
    final s = state.valueOrNull;
    if (s == null || s.paused) return;
    state = AsyncData(s.copyWith(pausedReason: PauseReason.background));
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
    // Any tap on a paused session resumes it; otherwise pause it manually.
    state = AsyncData(s.copyWith(
        pausedReason: s.paused ? PauseReason.none : PauseReason.user));
    if (!s.paused) return;
    _lastDataAt = DateTime.now(); // don't instantly re-idle-pause on resume
  }

  Future<int?> finish({String? notes}) async {
    final s = state.valueOrNull;
    if (s == null) return null;
    _ticker?.cancel();
    _sub?.cancel();
    await _flush();

    final live = s.live;
    final detail = await _rowing.rowingDetail(s.session.id);
    final sampleList = detail?.samples ?? const <RowingSample>[];
    List<double> positive(Iterable<double?> xs) =>
        xs.whereType<double>().where((x) => x > 0).toList();
    final rates = positive(sampleList.map((x) => x.strokeRate));
    final powers = positive(sampleList.map((x) => x.powerW));
    double mean(List<double> xs) =>
        xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;
    double maxOf(Iterable<double?> xs) =>
        positive(xs).fold(0.0, (m, x) => x > m ? x : m);

    // If the trainer dropped out just before finishing, the last live snapshot
    // can read 0 — fall back to the furthest sample.
    final distanceM = [live?.distanceM ?? 0.0, maxOf(sampleList.map((x) => x.distanceM))]
        .reduce((a, b) => a > b ? a : b);
    final energyKcal = [live?.energyKcal ?? 0.0, maxOf(sampleList.map((x) => x.energyKcal))]
        .reduce((a, b) => a > b ? a : b);

    await _rowing.finalize(
      s.session.id,
      distanceM: distanceM,
      duration: s.elapsed,
      avgStrokeRate: mean(rates),
      avgPower: mean(powers),
      energyKcal: energyKcal,
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
