import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/rowing_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../data/repositories/workout_session_repository.dart';
import '../../../domain/models/rowing.dart';
import '../../../domain/rowing_ftp.dart';
import '../rower_service.dart';
import '../rowing_cues.dart';
import 'active_rowing_provider.dart' show RowingMeter;

enum RampPhase { waiting, running, done }

enum RampHold { onPace, close, dropping }

/// How the rower is tracking the current step's target.
RampHold rampHold(double recentAvgWatts, double targetWatts) {
  if (targetWatts <= 0) return RampHold.onPace;
  if (recentAvgWatts >= 0.97 * targetWatts) return RampHold.onPace;
  if (recentAvgWatts >= 0.90 * targetWatts) return RampHold.close;
  return RampHold.dropping;
}

class RampTestState {
  const RampTestState({
    this.phase = RampPhase.waiting,
    this.step = 0,
    this.stepElapsed = Duration.zero,
    this.elapsed = Duration.zero,
    this.targetWatts = 0,
    this.recentAvgWatts = 0,
    this.paceMode = true,
    this.live,
    this.sessionId,
  });

  final RampPhase phase;
  final int step; // 0-based
  final Duration stepElapsed;
  final Duration elapsed;
  final double targetWatts;

  /// Rolling ~10 s average power, for the "holding / dropping" indicator. In
  /// pace mode this is derived from the split (the trainer reports no watts).
  final double recentAvgWatts;

  /// Run and show the test in terms of pace (/500 m) instead of watts. The
  /// default — most rowing trainers have no power meter. Chosen on the start
  /// screen before the test begins.
  final bool paceMode;

  final RowerSnapshot? live;

  /// Set once the finished test is persisted.
  final int? sessionId;

  Duration get stepRemaining =>
      Duration(seconds: RampProtocol.stepSeconds) - stepElapsed;

  /// The current step's target as a split (seconds per 500 m).
  double get targetSplit => splitForWatts(targetWatts, dragK: kGeneric);

  RampTestState copyWith({
    RampPhase? phase,
    int? step,
    Duration? stepElapsed,
    Duration? elapsed,
    double? targetWatts,
    double? recentAvgWatts,
    bool? paceMode,
    RowerSnapshot? live,
    int? sessionId,
  }) =>
      RampTestState(
        phase: phase ?? this.phase,
        step: step ?? this.step,
        stepElapsed: stepElapsed ?? this.stepElapsed,
        elapsed: elapsed ?? this.elapsed,
        targetWatts: targetWatts ?? this.targetWatts,
        recentAvgWatts: recentAvgWatts ?? this.recentAvgWatts,
        paceMode: paceMode ?? this.paceMode,
        live: live ?? this.live,
        sessionId: sessionId ?? this.sessionId,
      );
}

/// Drives a ramp test: a watt target that rises every minute, ending when the
/// rower can no longer hold it (or taps Stop). FTP ≈ 0.75 × best 60-second power.
class RampTestController extends AutoDisposeNotifier<RampTestState> {
  RampProtocol _proto = const RampProtocol();
  final _samples = <RowingSample>[];
  RowingMeter _meter = RowingMeter();
  Timer? _ticker;
  StreamSubscription<RowerSnapshot>? _sub;

  RowerSnapshot? _lastRaw;
  DateTime? _lastDataAt;
  final _recentPower = <({DateTime at, double w})>[];
  DateTime? _belowSince;
  int _lastSampleSecond = -3;

  /// The watts to work with: the trainer's own reading, or — when it has none —
  /// an estimate from the split via the generic drag relation.
  double? _effectivePower(RowerSnapshot? snap) {
    if (snap == null) return null;
    final w = snap.powerW;
    if (w != null && w > 0) return w;
    final p = snap.paceSec500m;
    if (p != null && p > 60 && p < 400) {
      return wattsForSplit(p, dragK: kGeneric);
    }
    return null;
  }

  RowingRepository get _rowing => ref.read(rowingRepositoryProvider);

  static const _noDataTimeout = Duration(seconds: 12);

  @override
  RampTestState build() {
    ref.onDispose(() {
      _ticker?.cancel();
      _sub?.cancel();
    });
    return const RampTestState();
  }

  Future<void> begin() async {
    if (state.phase != RampPhase.waiting || _ticker != null) return;
    final ftp = await ref.read(settingsRepositoryProvider).rowingFtp();
    _proto = RampProtocol.seeded(ftp?.watts);
    _meter = RowingMeter();
    _samples.clear();
    _recentPower.clear();
    _lastRaw = null;
    _lastDataAt = null;
    _belowSince = null;
    _lastSampleSecond = -3;
    state = RampTestState(targetWatts: _proto.targetForStep(0));
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _sub = ref.read(rowerServiceProvider).snapshots.listen(_onSnapshot);
    ref.read(rowerServiceProvider).connect();
  }

  RowerSnapshot _merged() {
    final r = _lastRaw;
    return RowerSnapshot(
      strokeRate: r?.strokeRate,
      strokeCount: r?.strokeCount,
      distanceM: _meter.distanceM,
      paceSec500m: r?.paceSec500m,
      powerW: _effectivePower(r),
      energyKcal: _meter.energyKcal,
      heartRate: r?.heartRate,
      elapsedSeconds: r?.elapsedSeconds,
    );
  }

  void _onSnapshot(RowerSnapshot snap) {
    if (state.phase == RampPhase.done) return;
    _lastRaw = snap;
    final now = DateTime.now();
    _lastDataAt = now;

    final w = _effectivePower(snap);
    if (w != null) {
      _recentPower.add((at: now, w: w));
      _recentPower.removeWhere(
          (e) => now.difference(e.at) > const Duration(seconds: 15));
    }
    final pace = snap.paceSec500m;
    final rowing = (snap.strokeRate ?? 0) >= 1 ||
        (pace != null && pace > 60 && pace < 900);
    if (state.phase == RampPhase.waiting && rowing) {
      state = state.copyWith(phase: RampPhase.running, live: _merged());
    } else {
      state = state.copyWith(live: _merged());
    }
  }

  /// Switch between pace and watt targeting — only before the test has started.
  void setPaceMode(bool paceMode) {
    if (state.phase != RampPhase.waiting) return;
    state = state.copyWith(paceMode: paceMode);
  }

  /// Rolling average power over the last [seconds]s (0 when no data).
  double recentAvgPower([int seconds = 10]) {
    final cutoff = DateTime.now().subtract(Duration(seconds: seconds));
    final xs = _recentPower.where((e) => e.at.isAfter(cutoff)).map((e) => e.w);
    return xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;
  }

  void _tick() {
    final s = state;
    if (s.phase != RampPhase.running) return;
    final now = DateTime.now();

    if (_lastDataAt != null && now.difference(_lastDataAt!) > _noDataTimeout) {
      finish();
      return;
    }

    final pace = _lastRaw?.paceSec500m;
    final freshPace = pace != null && pace > 60 && pace < 900;
    _meter.tick(
      seconds: 1,
      paceSec500m: freshPace ? pace : null,
      powerW: _lastRaw?.powerW,
    );

    var elapsed = s.elapsed + const Duration(seconds: 1);
    var stepElapsed = s.stepElapsed + const Duration(seconds: 1);
    var step = s.step;
    if (stepElapsed.inSeconds >= RampProtocol.stepSeconds) {
      step += 1;
      stepElapsed = Duration.zero;
      ref.read(rowingCuesProvider).onSwitch();
    }

    // Fail: after the first 10 s of a step, if the 10 s average power stays
    // below 92 % of the step target for 6 s straight, the rower is done.
    final stepTarget = _proto.targetForStep(s.step);
    final avg = recentAvgPower();
    if (s.stepElapsed.inSeconds >= 10 && avg > 0 && avg < 0.92 * stepTarget) {
      _belowSince ??= now;
      if (now.difference(_belowSince!) >= const Duration(seconds: 6)) {
        finish();
        return;
      }
    } else {
      _belowSince = null;
    }

    state = s.copyWith(
      elapsed: elapsed,
      stepElapsed: stepElapsed,
      step: step,
      targetWatts: _proto.targetForStep(step),
      recentAvgWatts: avg,
      live: _merged(),
    );
    _maybeSample(elapsed);
  }

  void _maybeSample(Duration elapsed) {
    final r = _lastRaw;
    if (r == null) return;
    if (elapsed.inSeconds - _lastSampleSecond < 3) return;
    _lastSampleSecond = elapsed.inSeconds;
    _samples.add(RowingSample(
      id: 0,
      rowingSessionId: 0,
      tOffsetMs: elapsed.inMilliseconds,
      strokeRate: r.strokeRate,
      strokeCount: r.strokeCount,
      distanceM: _meter.distanceM,
      paceSec500m: r.paceSec500m,
      powerW: _effectivePower(r),
      energyKcal: _meter.energyKcal,
      heartRate: r.heartRate,
    ));
  }

  /// Ends the test, persists it as an `ftp_ramp` session, and puts the id in
  /// state so the screen can navigate to the result.
  Future<int?> finish() async {
    if (state.phase == RampPhase.done) return state.sessionId;
    _ticker?.cancel();
    _sub?.cancel();
    _ticker = null;
    state = state.copyWith(phase: RampPhase.done);

    final ids = await _rowing.startSession(kind: FtpProtocol.ramp.kind);
    if (_samples.isNotEmpty) {
      await _rowing.addSamples(ids.rowingSessionId, _samples);
    }
    final best = bestMinuteWatts(_samples);
    final rates = _samples
        .map((x) => x.strokeRate)
        .whereType<double>()
        .where((x) => x > 0)
        .toList();
    await _rowing.finalize(
      ids.sessionId,
      distanceM: _meter.distanceM,
      duration: state.elapsed,
      avgStrokeRate:
          rates.isEmpty ? 0 : rates.reduce((a, b) => a + b) / rates.length,
      avgPower: best, // best-minute power — computeFtp() reads this for the ramp
      energyKcal: _meter.energyKcal,
    );
    await ref.read(rowerServiceProvider).disconnect();
    ref.invalidate(recentSessionsProvider);
    for (final p in rowingProgressProviders) {
      ref.invalidate(p);
    }
    state = state.copyWith(sessionId: ids.sessionId);
    return ids.sessionId;
  }

  Future<void> abort() async {
    _ticker?.cancel();
    _sub?.cancel();
    _ticker = null;
    await ref.read(rowerServiceProvider).disconnect();
  }
}

final rampTestProvider =
    NotifierProvider.autoDispose<RampTestController, RampTestState>(
        RampTestController.new);
