import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/program_repository.dart';
import '../../../data/repositories/rowing_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../data/repositories/workout_session_repository.dart';
import '../../../domain/models/program.dart';
import '../../../domain/models/rowing.dart';
import '../../../domain/models/workout_session.dart';
import '../../../domain/rowing_format.dart';
import '../../../domain/rowing_ftp.dart';
import '../rower_service.dart';
import '../rowing_cues.dart';

/// Derives session distance and energy.
///
/// This trainer only really reports stroke rate and stroke count — its pace,
/// power and distance are all fixed functions of the stroke rate — so distance
/// is strokes × the user's metres-per-stroke setting. Energy comes from power
/// (meaningful only with a real power meter). Both only advance while the
/// session runs; the caller decides when via [addStrokes] and [tick].
class RowingMeter {
  double _distanceM = 0;
  double _energyKcal = 0;
  int? _lastStrokeCount;

  double get distanceM => _distanceM;
  double get energyKcal => _energyKcal;

  /// Carry a rehydrated session's totals forward after an app restart.
  void seed({required double distanceM, required double energyKcal}) {
    _distanceM = distanceM;
    _energyKcal = energyKcal;
  }

  /// Registers the trainer's running stroke count and returns the strokes since
  /// the previous call. The counter restarts at 0 on a reconnect — then the new
  /// value is the strokes since that reset. The first call only sets the
  /// baseline.
  int observeStrokes(int? count) {
    if (count == null) return 0;
    final last = _lastStrokeCount;
    _lastStrokeCount = count;
    if (last == null) return 0;
    return count >= last ? count - last : count;
  }

  void addStrokes(int strokes, double metersPerStroke) {
    if (strokes > 0 && metersPerStroke > 0) {
      _distanceM += strokes * metersPerStroke;
    }
  }

  /// Advance energy by [seconds]; [powerW] null / ≤ 0 → no energy this step.
  void tick({required double seconds, double? powerW}) {
    if (powerW != null && powerW > 0) {
      // Mechanical watts → metabolic kcal (~4× gross efficiency).
      _energyKcal += powerW * 4.0 / 4184.0 * seconds;
    }
  }
}

/// Why the session clock is stopped.
enum PauseReason {
  none,

  /// Session created, waiting for the first strokes before the clock starts.
  notStarted,

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
    this.kind,
    this.segmentIndex = 0,
    this.elapsed = Duration.zero,
    this.segmentElapsed = Duration.zero,
    this.live,
    this.pausedReason = PauseReason.none,
  });

  final WorkoutSession session;
  final int rowingSessionId;

  /// `rowing_sessions.kind` — a `RowSessionType.name`, or `ftp_*` for a test.
  final String? kind;

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

  /// A planned session whose last segment has run its full duration — time to
  /// wrap up and (for an FTP test) show the result. Free rows never complete on
  /// their own.
  bool get plannedSessionComplete =>
      segments.isNotEmpty &&
      pausedReason != PauseReason.notStarted &&
      segmentIndex >= segments.length - 1 &&
      segmentElapsed.inSeconds >= (currentSegment?.durationSeconds ?? 0);

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
        kind: kind,
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
  SettingsRepository get _settings => ref.read(settingsRepositoryProvider);
  RowerService get _rower => ref.read(rowerServiceProvider);

  Timer? _ticker;
  StreamSubscription<RowerSnapshot>? _sub;
  final List<RowingSample> _pending = [];
  int _lastSampleSecond = -3;

  /// When the trainer last sent data (null until the first frame), and when you
  /// last showed signs of rowing (a stroke or a live split). Either going stale
  /// auto-pauses the session — some trainers keep streaming zero-frames when you
  /// stop rowing.
  DateTime? _lastDataAt;
  DateTime? _lastMoveAt;
  static const _idleTimeout = Duration(seconds: 8);
  static const _stallTimeout = Duration(seconds: 10);

  /// Latest raw trainer frame, the session's derived distance/energy, and the
  /// last plausible split (held briefly between frames). Reset per session.
  RowerSnapshot? _lastRaw;
  RowingMeter _meter = RowingMeter();

  /// A personal correction on top of the trainer's own reported split — see
  /// [SettingsRepository.rowingPaceCorrectionPercent]. Fetched once per
  /// session in [_startEngine] since [_onSnapshot] is a synchronous callback.
  double _metersPerStroke = kDefaultMetersPerStroke;

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
      kind: db?.rowing.kind,
      segmentIndex: idx,
      elapsed: elapsed,
      segmentElapsed: elapsed - acc,
      pausedReason: PauseReason.notStarted,
    );
    await _startEngine();
    // Carry the pre-restart distance/energy forward.
    final samples = db?.samples ?? const <RowingSample>[];
    if (samples.isNotEmpty) {
      _meter.seed(
        distanceM: samples.last.distanceM ?? 0,
        energyKcal: samples.last.energyKcal ?? 0,
      );
    }
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
      await _startEngine();
      return ActiveRowingState(
        session: session,
        rowingSessionId: ids.rowingSessionId,
        segments: segments,
        kind: day.rowSessionType,
        pausedReason: PauseReason.notStarted,
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
      await _startEngine();
      return ActiveRowingState(
        session: session,
        rowingSessionId: ids.rowingSessionId,
        segments: const [],
        pausedReason: PauseReason.notStarted,
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
      // Bake the current FTP's pace targets into a catalogue workout (a guided
      // FTP test is all-out — no target cue there).
      final isFtpTest = kind?.startsWith('ftp_') ?? false;
      final segs = isFtpTest
          ? segments
          : withFtpTargets(segments, (await _settings.rowingFtp())?.watts);
      final ids = await _rowing.startSession(
        segmentsJson: encodeRowSegments(segs),
        kind: kind,
      );
      final session = WorkoutSession(
        id: ids.sessionId,
        discipline: Discipline.rowing,
        startedAt: DateTime.now(),
      );
      await _startEngine();
      return ActiveRowingState(
        session: session,
        rowingSessionId: ids.rowingSessionId,
        segments: segs,
        kind: kind,
        pausedReason: PauseReason.notStarted,
      );
    });
  }

  Future<void> _startEngine() async {
    _metersPerStroke = await _settings.rowingMetersPerStroke();
    _lastSampleSecond = -3;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _sub?.cancel();
    _lastRaw = null;
    _lastDataAt = null;
    _lastMoveAt = null;
    _meter = RowingMeter();
    _sub = _rower.snapshots.listen(_onSnapshot);
    _rower.connect();
  }

  /// The live snapshot the UI sees: the trainer's raw stroke/pace/power/HR plus
  /// our own integrated distance and energy.
  RowerSnapshot _merged() {
    final r = _lastRaw;
    return RowerSnapshot(
      strokeRate: r?.strokeRate,
      strokeCount: r?.strokeCount,
      distanceM: _meter.distanceM,
      paceSec500m: r?.paceSec500m,
      powerW: r?.powerW,
      energyKcal: _meter.energyKcal,
      heartRate: r?.heartRate,
      elapsedSeconds: r?.elapsedSeconds,
    );
  }

  // --- Live loop -------------------------------------------------

  void _onSnapshot(RowerSnapshot rawIn) {
    final s = state.valueOrNull;
    if (s == null) return;
    final raw =
        rawIn.withPace(paceFromStrokes(rawIn.strokeRate, _metersPerStroke));
    _lastRaw = raw;
    final now = DateTime.now();
    _lastDataAt = now;

    // Movement = the stroke count going up (a stroke rate that stays non-zero
    // can outlive a stopped rower); fall back to the rate when no count comes.
    final strokes = _meter.observeStrokes(raw.strokeCount);
    final rowing =
        raw.strokeCount != null ? strokes > 0 : (raw.strokeRate ?? 0) >= 1;
    if (rowing) _lastMoveAt = now;
    _lastMoveAt ??= now;

    // The first strokes start the clock; returning data lifts an idle pause.
    var reason = s.pausedReason;
    if (rowing &&
        (reason == PauseReason.notStarted || reason == PauseReason.idle)) {
      reason = PauseReason.none;
    }
    if (reason == PauseReason.none) _meter.addStrokes(strokes, _metersPerStroke);
    state = AsyncData(s.copyWith(live: _merged(), pausedReason: reason));
  }

  void _tick() {
    final s = state.valueOrNull;
    if (s == null) return;

    // The clock stays frozen until the first strokes arrive.
    if (s.pausedReason == PauseReason.notStarted) return;

    // Auto-pause when the trainer goes quiet, or keeps streaming but you've
    // stopped rowing — unless a planned rest is running.
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

    _meter.tick(seconds: 1, powerW: _lastRaw?.powerW);

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

    final merged = _merged();
    state = AsyncData(s.copyWith(
      elapsed: elapsed,
      segmentElapsed: segElapsed,
      segmentIndex: idx,
      live: merged,
    ));

    _maybeSample(merged, elapsed);
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
    // Any tap on a paused session resumes it (also a manual start from the
    // not-started state); otherwise pause it manually.
    state = AsyncData(s.copyWith(
        pausedReason: s.paused ? PauseReason.none : PauseReason.user));
    if (!s.paused) return;
    // Don't instantly re-idle-pause on resume.
    _lastDataAt = DateTime.now();
    _lastMoveAt = DateTime.now();
  }

  Future<int?> finish({String? notes}) async {
    final s = state.valueOrNull;
    if (s == null) return null;
    _ticker?.cancel();
    _sub?.cancel();
    await _flush();

    final detail = await _rowing.rowingDetail(s.session.id);
    final sampleList = detail?.samples ?? const <RowingSample>[];
    List<double> positive(Iterable<double?> xs) =>
        xs.whereType<double>().where((x) => x > 0).toList();
    double mean(List<double> xs) =>
        xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;

    // `_meter` accumulates monotonically (and is seeded from the last sample on
    // a rehydrate), so its totals are the session's final distance/energy.
    await _rowing.finalize(
      s.session.id,
      distanceM: _meter.distanceM,
      duration: s.elapsed,
      avgStrokeRate: mean(positive(sampleList.map((x) => x.strokeRate))),
      avgPower: mean(positive(sampleList.map((x) => x.powerW))),
      energyKcal: _meter.energyKcal,
      notes: notes,
    );
    await _rower.disconnect();

    // Calibrate the trainer's watt↔split drag factor from this session — only
    // with a confirmed real power meter. Otherwise the "power" field is often
    // a small/garbage reading, and fitting k = W·v³ from it silently drags
    // every future target pace off.
    if (await _settings.rowingHasPowerMeter()) {
      final k = calibrateDragK(sampleList);
      if (k != null) {
        await _settings.setRowingDragK(k);
        ref.invalidate(rowingDragKProvider);
      }
    }

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
    ref.invalidate(recentSessionsProvider);
    for (final p in rowingProgressProviders) {
      ref.invalidate(p);
    }
    state = const AsyncData(null);
  }
}

final activeRowingProvider =
    AsyncNotifierProvider<ActiveRowingController, ActiveRowingState?>(
  ActiveRowingController.new,
);
