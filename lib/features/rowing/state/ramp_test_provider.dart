import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/rowing_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../data/repositories/workout_session_repository.dart';
import '../../../domain/models/rowing.dart';
import '../../../domain/rowing_format.dart';
import '../../../domain/rowing_ftp.dart';
import '../rower_service.dart';
import '../rowing_cues.dart';
import 'active_rowing_provider.dart' show RowingMeter;

enum RampPhase { waiting, running, done }

enum RampHold { onPace, close, dropping }

/// How the rower is tracking the current step's target. No reading yet (0) is
/// treated as on-pace, not as a collapse — otherwise a momentary data gap
/// reads as "je valt terug".
RampHold rampHold(double recentAvgWatts, double targetWatts) {
  if (targetWatts <= 0 || recentAvgWatts <= 0) return RampHold.onPace;
  if (recentAvgWatts >= 0.97 * targetWatts) return RampHold.onPace;
  if (recentAvgWatts >= 0.90 * targetWatts) return RampHold.close;
  return RampHold.dropping;
}

/// The same for a stroke-rate ramp: the 10 s average stroke rate against the
/// step's target. A stroke rate is read in whole spm and wobbles by one, so the
/// bands are in spm rather than a percentage.
RampHold rampHoldSpm(double recentAvgSpm, double targetSpm) {
  if (targetSpm <= 0 || recentAvgSpm <= 0) return RampHold.onPace;
  if (recentAvgSpm >= targetSpm - 0.5) return RampHold.onPace;
  if (recentAvgSpm >= targetSpm - 1.5) return RampHold.close;
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
    this.targetSpm = 0,
    this.recentAvgSpm = 0,
    this.spmMode = true,
    this.live,
    this.sessionId,
  });

  final RampPhase phase;
  final int step; // 0-based
  final Duration stepElapsed;
  final Duration elapsed;
  final double targetWatts;

  /// Rolling ~10 s average power, for the "holding / dropping" indicator. In
  /// stroke-rate mode this is the stroke-rate equivalent (the trainer reports
  /// no real watts).
  final double recentAvgWatts;

  /// The current step's target stroke rate, and the rolling ~10 s average.
  final double targetSpm;
  final double recentAvgSpm;

  /// Run the test on stroke rate (spm) instead of watts. The default — most
  /// rowing trainers have no power meter and only really report stroke rate.
  /// Chosen on the start screen before the test begins.
  final bool spmMode;

  final RowerSnapshot? live;

  /// Set once the finished test is persisted.
  final int? sessionId;

  Duration get stepRemaining =>
      Duration(seconds: RampProtocol.stepSeconds) - stepElapsed;

  RampTestState copyWith({
    RampPhase? phase,
    int? step,
    Duration? stepElapsed,
    Duration? elapsed,
    double? targetWatts,
    double? recentAvgWatts,
    double? targetSpm,
    double? recentAvgSpm,
    bool? spmMode,
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
        targetSpm: targetSpm ?? this.targetSpm,
        recentAvgSpm: recentAvgSpm ?? this.recentAvgSpm,
        spmMode: spmMode ?? this.spmMode,
        live: live ?? this.live,
        sessionId: sessionId ?? this.sessionId,
      );
}

/// Drives a ramp test: a target (stroke rate, or watts with a power meter) that
/// rises every minute, ending when the rower can no longer hold it (or taps
/// Stop). FTP ≈ 0.75 × best 60-second power (for stroke rate: its notional
/// power, see `wattsForSpm`).
class RampTestController extends AutoDisposeNotifier<RampTestState> {
  RampProtocol _proto = const RampProtocol();
  final _samples = <RowingSample>[];
  RowingMeter _meter = RowingMeter();
  Timer? _ticker;
  StreamSubscription<RowerSnapshot>? _sub;

  RowerSnapshot? _lastRaw;
  DateTime? _lastDataAt;
  final _recentPower = <({DateTime at, double w})>[];
  final _recentSpm = <({DateTime at, double spm})>[];
  DateTime? _belowSince;
  int _lastSampleSecond = -3;

  /// Metres per stroke for distance and tempo — see
  /// [SettingsRepository.rowingMetersPerStroke]. Fetched once in [begin] since
  /// [_onSnapshot] is a synchronous callback.
  double _metersPerStroke = kDefaultMetersPerStroke;

  /// The watts to work with. With a power meter (watt mode): the trainer's own
  /// reading, falling back to the stroke-rate equivalent. In stroke-rate mode:
  /// always the stroke-rate equivalent — the trainer's power field is ignored
  /// (without a meter it is a tiny fixed function of the stroke rate).
  double? _effectivePower(RowerSnapshot? snap) {
    if (snap == null) return null;
    if (!state.spmMode) {
      final w = snap.powerW;
      if (w != null && w > 0) return w;
    }
    final spm = snap.strokeRate;
    return spm != null && spm >= 1 ? wattsForSpm(spm) : null;
  }

  /// The (target watts, target spm) for ramp step [n] in the given mode.
  ({double watts, double spm}) _targetsFor(int n, bool spmMode) {
    final spm = _proto.targetSpmForStep(n);
    return (
      watts: spmMode ? wattsForSpm(spm) : _proto.targetForStep(n),
      spm: spm,
    );
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
    final settings = ref.read(settingsRepositoryProvider);
    final ftp = await settings.rowingFtp();
    _metersPerStroke = await settings.rowingMetersPerStroke();
    _proto = RampProtocol.seeded(ftp?.watts);
    _meter = RowingMeter();
    _samples.clear();
    _recentPower.clear();
    _recentSpm.clear();
    _lastRaw = null;
    _lastDataAt = null;
    _belowSince = null;
    _lastSampleSecond = -3;
    final t = _targetsFor(0, true);
    state = RampTestState(targetWatts: t.watts, targetSpm: t.spm);
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

  void _onSnapshot(RowerSnapshot snapIn) {
    if (state.phase == RampPhase.done) return;
    final snap =
        snapIn.withPace(paceFromStrokes(snapIn.strokeRate, _metersPerStroke));
    _lastRaw = snap;
    final strokes = _meter.observeStrokes(snap.strokeCount);
    final now = DateTime.now();
    _lastDataAt = now;

    final w = _effectivePower(snap);
    if (w != null) {
      _recentPower.add((at: now, w: w));
      _recentPower.removeWhere(
          (e) => now.difference(e.at) > const Duration(seconds: 15));
    }
    final spm = snap.strokeRate;
    if (spm != null && spm >= 1) {
      _recentSpm.add((at: now, spm: spm));
      _recentSpm.removeWhere(
          (e) => now.difference(e.at) > const Duration(seconds: 15));
    }
    final rowing = (spm ?? 0) >= 1;
    if (state.phase == RampPhase.waiting && rowing) {
      state = state.copyWith(phase: RampPhase.running, live: _merged());
    } else {
      state = state.copyWith(live: _merged());
    }
    if (state.phase == RampPhase.running) {
      _meter.addStrokes(strokes, _metersPerStroke);
    }
  }

  /// Switch between stroke-rate and watt targeting — only before the test has
  /// started.
  void setSpmMode(bool spmMode) {
    if (state.phase != RampPhase.waiting) return;
    final t = _targetsFor(state.step, spmMode);
    state = state.copyWith(
        spmMode: spmMode, targetWatts: t.watts, targetSpm: t.spm);
  }

  /// Rolling average stroke rate over the last [seconds]s (0 when no data).
  double recentAvgSpm([int seconds = 10]) {
    final cutoff = DateTime.now().subtract(Duration(seconds: seconds));
    final xs = _recentSpm.where((e) => e.at.isAfter(cutoff)).map((e) => e.spm);
    return xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;
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

    _meter.tick(seconds: 1, powerW: _lastRaw?.powerW);

    var elapsed = s.elapsed + const Duration(seconds: 1);
    var stepElapsed = s.stepElapsed + const Duration(seconds: 1);
    var step = s.step;
    if (stepElapsed.inSeconds >= RampProtocol.stepSeconds) {
      step += 1;
      stepElapsed = Duration.zero;
      ref.read(rowingCuesProvider).onSwitch();
    }

    // Fail: after the first 10 s of a step, if the 10 s average stays clearly
    // below the step target (92 % of the watts, or 1.5 spm) for 6 s straight,
    // the rower is done.
    final avg = recentAvgPower();
    final avgSpm = recentAvgSpm();
    final below = s.spmMode
        ? avgSpm > 0 && avgSpm < _proto.targetSpmForStep(s.step) - 1.5
        : avg > 0 && avg < 0.92 * _proto.targetForStep(s.step);
    if (s.stepElapsed.inSeconds >= 10 && below) {
      _belowSince ??= now;
      if (now.difference(_belowSince!) >= const Duration(seconds: 6)) {
        finish();
        return;
      }
    } else {
      _belowSince = null;
    }

    final t = _targetsFor(step, s.spmMode);
    state = s.copyWith(
      elapsed: elapsed,
      stepElapsed: stepElapsed,
      step: step,
      targetWatts: t.watts,
      targetSpm: t.spm,
      recentAvgWatts: avg,
      recentAvgSpm: avgSpm,
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
