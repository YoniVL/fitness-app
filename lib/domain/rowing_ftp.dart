import 'dart:math' as math;

import 'models/program.dart';
import 'models/rowing.dart';
import 'rowing_workouts.dart' show RowIntensity;

/// The inputs [computeFtp] needs from a finished test session (a subset of the
/// repository's `RowingSessionDetail`, kept here to avoid a domain→data import).
typedef FtpSessionData = ({
  List<RowingSample> samples,
  List<ProgramRowSegment> planSegments,
  double totalDistanceM,
  int durationSeconds,
});

/// FTP-based personalisation for rowing.
///
/// The trainer reports instantaneous **power (W)** and **pace (s/500m)**
/// directly, so FTP is just measured power × a protocol factor — no formula
/// needed for the number itself. The only conversion is turning a *target*
/// power into a *target* split for display, via the generic ergometer drag
/// relation `W = k / v³` (v in s/m), with `k` calibrated from the trainer's own
/// (power, pace) samples. [kGeneric] is the fallback until a calibration exists.
const double kGeneric = 2.80;

/// Split (seconds per 500 m) that [watts] corresponds to on an erg with drag
/// factor [dragK].
double splitForWatts(double watts, {double dragK = kGeneric}) {
  if (watts <= 0) return double.infinity;
  final vPerMetre = math.pow(dragK / watts, 1 / 3).toDouble();
  return vPerMetre * 500;
}

/// Power (W) held at a [sec500] split on an erg with drag factor [dragK].
double wattsForSplit(double sec500, {double dragK = kGeneric}) {
  if (sec500 <= 0) return 0;
  final vPerMetre = sec500 / 500;
  return dragK / (vPerMetre * vPerMetre * vPerMetre);
}

/// Fit the trainer's drag factor `k` from paired (power, pace) samples:
/// `k = W · v³`, taken as the median over the session. Returns null when there
/// isn't enough usable data (needs ~20 samples), so the caller keeps the
/// previous value.
double? calibrateDragK(List<RowingSample> samples) {
  final ks = <double>[];
  for (final s in samples) {
    final w = s.powerW;
    final p = s.paceSec500m;
    if (w == null || w <= 0 || p == null || p <= 0) continue;
    final v = p / 500;
    final k = w * v * v * v;
    if (k >= 1.0 && k <= 8.0) ks.add(k);
  }
  if (ks.length < 20) return null;
  ks.sort();
  final mid = ks.length ~/ 2;
  return ks.length.isOdd ? ks[mid] : (ks[mid - 1] + ks[mid]) / 2;
}

/// Where an FTP value came from.
enum FtpSource {
  test20,
  testShort,
  ramp,
  manual,
  import;

  static FtpSource fromName(String? v) =>
      FtpSource.values.firstWhere((s) => s.name == v,
          orElse: () => FtpSource.manual);

  String get label => switch (this) {
        FtpSource.test20 => '20-minutentest',
        FtpSource.testShort => 'Korte test',
        FtpSource.ramp => 'Ramptest',
        FtpSource.manual => 'Handmatig',
        FtpSource.import => 'Uit logboek',
      };
}

/// A stored FTP: the watt value, when it was set, and how.
class RowingFtp {
  const RowingFtp({
    required this.watts,
    required this.setAt,
    required this.source,
  });

  final double watts;
  final DateTime setAt;
  final FtpSource source;

  /// The FTP split (s/500 m) at drag factor [dragK].
  double splitSeconds({double dragK = kGeneric}) =>
      splitForWatts(watts, dragK: dragK);

  Map<String, Object?> toJson() => {
        'w': watts,
        'at': setAt.millisecondsSinceEpoch,
        'src': source.name,
      };

  factory RowingFtp.fromJson(Map<String, Object?> j) => RowingFtp(
        watts: (j['w'] as num).toDouble(),
        setAt: DateTime.fromMillisecondsSinceEpoch((j['at'] as num).toInt()),
        source: FtpSource.fromName(j['src'] as String?),
      );
}

/// One training zone derived from an FTP: its share of FTP power, the target
/// power, and the split band (fast..slow seconds per 500 m) it maps to.
class RowingZone {
  const RowingZone({
    required this.ftpFraction,
    required this.targetWatts,
    required this.targetSplitSeconds,
    required this.splitFastSeconds,
    required this.splitSlowSeconds,
  });

  final double ftpFraction;
  final double targetWatts;
  final double targetSplitSeconds;
  final double splitFastSeconds;
  final double splitSlowSeconds;
}

/// Rowing power zones (UT2 / UT1 / AT / TR / AN), keyed to the app's
/// [RowIntensity]. Fractions are of FTP power.
class RowingZones {
  RowingZones._(this._byZone);

  final Map<RowIntensity, RowingZone> _byZone;

  RowingZone? operator [](RowIntensity zone) => _byZone[zone];

  /// (lo, mid, hi) power fraction of FTP per zone.
  static const _bands = <RowIntensity, (double, double, double)>{
    RowIntensity.easy: (0.55, 0.63, 0.70), // UT2
    RowIntensity.steady: (0.70, 0.75, 0.80), // UT1
    RowIntensity.threshold: (0.84, 0.89, 0.94), // AT
    RowIntensity.hard: (0.95, 1.00, 1.05), // TR
    RowIntensity.max: (1.10, 1.20, 1.35), // AN
  };

  static RowingZones fromFtp(double ftpWatts, {double dragK = kGeneric}) {
    final out = <RowIntensity, RowingZone>{};
    _bands.forEach((zone, band) {
      final (lo, mid, hi) = band;
      out[zone] = RowingZone(
        ftpFraction: mid,
        targetWatts: ftpWatts * mid,
        targetSplitSeconds: splitForWatts(ftpWatts * mid, dragK: dragK),
        // Higher power → faster (smaller) split.
        splitFastSeconds: splitForWatts(ftpWatts * hi, dragK: dragK),
        splitSlowSeconds: splitForWatts(ftpWatts * lo, dragK: dragK),
      );
    });
    return RowingZones._(out);
  }
}

/// The FTP test protocols.
enum FtpProtocol {
  test20,
  testShort,
  ramp;

  /// FTP = (effort average power) × [multiplier]. For [ramp] the basis is the
  /// best 60-second average power instead of the effort average.
  double get multiplier => switch (this) {
        FtpProtocol.test20 => 0.95,
        FtpProtocol.testShort => 0.88,
        FtpProtocol.ramp => 0.75,
      };

  String get kind => switch (this) {
        FtpProtocol.test20 => 'ftp_20min',
        FtpProtocol.testShort => 'ftp_short',
        FtpProtocol.ramp => 'ftp_ramp',
      };

  FtpSource get source => switch (this) {
        FtpProtocol.test20 => FtpSource.test20,
        FtpProtocol.testShort => FtpSource.testShort,
        FtpProtocol.ramp => FtpSource.ramp,
      };

  String get label => switch (this) {
        FtpProtocol.test20 => '20-minutentest',
        FtpProtocol.testShort => 'Korte test (~2 km)',
        FtpProtocol.ramp => 'Ramptest',
      };

  String get blurb => switch (this) {
        FtpProtocol.test20 =>
          'Twintig minuten zo hard mogelijk volhouden. De gouden standaard.',
        FtpProtocol.testShort =>
          'Ongeveer 2 km alles eruit. Korter af te zien, iets minder precies.',
        FtpProtocol.ramp =>
          'Het wattdoel loopt elke minuut op tot je niet meer volgt.',
      };

  static FtpProtocol? fromKind(String? kind) {
    for (final p in FtpProtocol.values) {
      if (p.kind == kind) return p;
    }
    return null;
  }

  /// The effort window `[startSec, endSec]` inside a guided test session: the
  /// longest non-rest segment that isn't the warm-up.
  ({int startSec, int endSec})? effortWindow(List<ProgramRowSegment> segs) {
    if (segs.isEmpty) return null;
    var acc = 0;
    ({int startSec, int endSec})? best;
    var bestDur = 0;
    for (var i = 0; i < segs.length; i++) {
      final dur = segs[i].durationSeconds;
      if (i > 0 && !segs[i].isRest && dur > bestDur) {
        best = (startSec: acc, endSec: acc + dur);
        bestDur = dur;
      }
      acc += dur;
    }
    return best;
  }
}

/// How an FTP number was derived from a test session.
enum FtpMethod {
  /// Effort (or best-minute) power × the protocol's fixed factor.
  multiplier,

  /// Two-point Critical Power fit over the session's power curve.
  criticalPower,
}

/// The outcome of an FTP test: the computed FTP plus what it was derived from.
class FtpResult {
  const FtpResult({
    required this.watts,
    required this.protocol,
    this.method = FtpMethod.multiplier,
    this.effortWatts,
    this.effortPaceSeconds,
    this.cpWPrime,
    this.lowConfidence = false,
  });

  final double watts;
  final FtpProtocol protocol;
  final FtpMethod method;
  final double? effortWatts;
  final double? effortPaceSeconds;

  /// The anaerobic work capacity `W'` (joules) when [method] is criticalPower.
  final double? cpWPrime;

  /// True when derived from too few samples or from distance/time (no samples).
  final bool lowConfidence;
}

double _mean(Iterable<double> xs) {
  var n = 0;
  var sum = 0.0;
  for (final x in xs) {
    sum += x;
    n++;
  }
  return n == 0 ? 0 : sum / n;
}

/// Highest rolling average power over a window of [windowSeconds] across the
/// session. 0 when there isn't enough data in any window.
double bestAvgWatts(List<RowingSample> samples, int windowSeconds) {
  final pts = [
    for (final s in samples)
      if (s.powerW != null && s.powerW! > 0) (t: s.tOffsetMs, w: s.powerW!),
  ]..sort((a, b) => a.t.compareTo(b.t));
  if (pts.length < 2) return 0;
  final windowMs = windowSeconds * 1000;
  var best = 0.0;
  for (var i = 0; i < pts.length; i++) {
    final end = pts[i].t + windowMs;
    var sum = 0.0;
    var n = 0;
    var lastT = pts[i].t;
    for (var j = i; j < pts.length && pts[j].t <= end; j++) {
      sum += pts[j].w;
      n++;
      lastT = pts[j].t;
    }
    // Only trust a window that is actually (mostly) filled — otherwise a tiny
    // cluster of samples at the end of the session would masquerade as a full
    // window average.
    if (n >= 3 && lastT - pts[i].t >= windowMs * 0.75) {
      best = math.max(best, sum / n);
    }
  }
  return best;
}

/// Highest 60-second rolling average power across the session (for the ramp
/// test). 0 when there isn't enough data.
double bestMinuteWatts(List<RowingSample> samples) => bestAvgWatts(samples, 60);

/// Two-point Critical Power fit: `P(t) = W' / t + CP`, from a short, powerful
/// effort [a] and a longer, lower one [b]. Returns null when the two points
/// can't support a fit — windows less than 90 s apart, power not falling with
/// duration, or an implausible CP.
({double cp, double wPrime})? criticalPower(
  ({int seconds, double watts}) a,
  ({int seconds, double watts}) b,
) {
  final (short, long) = a.seconds <= b.seconds ? (a, b) : (b, a);
  final t1 = short.seconds.toDouble();
  final t2 = long.seconds.toDouble();
  final p1 = short.watts;
  final p2 = long.watts;
  if (t2 - t1 < 90) return null;
  if (p1 <= 0 || p2 <= 0 || p1 <= p2) return null;
  final cp = (p1 * t1 - p2 * t2) / (t1 - t2);
  final wPrime = (p1 - p2) * t1 * t2 / (t2 - t1);
  if (cp <= 0 || cp >= p1 || cp > 4 * p2 || wPrime <= 0) return null;
  return (cp: cp, wPrime: wPrime);
}

/// Critical Power from the session's power curve: the best 60 s effort as the
/// short point and the best 240 s as the long one. Null unless the curve
/// genuinely falls off with duration (a ramp, or a hard fast start).
FtpResult? _tryCriticalPower(List<RowingSample> samples, FtpProtocol protocol) {
  final p1 = bestAvgWatts(samples, 60);
  final p2 = bestAvgWatts(samples, 240);
  final cp = criticalPower(
    (seconds: 60, watts: p1),
    (seconds: 240, watts: p2),
  );
  if (cp == null) return null;
  return FtpResult(
    watts: cp.cp,
    protocol: protocol,
    method: FtpMethod.criticalPower,
    effortWatts: p1,
    cpWPrime: cp.wPrime,
  );
}

/// Compute FTP from a finished test session.
FtpResult computeFtp(FtpSessionData detail, FtpProtocol protocol) {
  final samples = detail.samples;

  if (protocol == FtpProtocol.ramp) {
    return _tryCriticalPower(samples, protocol) ??
        () {
          final best = bestMinuteWatts(samples);
          return FtpResult(
            watts: best * protocol.multiplier,
            protocol: protocol,
            effortWatts: best,
            lowConfidence: best <= 0,
          );
        }();
  }

  final window = protocol.effortWindow(detail.planSegments);
  bool inWindow(RowingSample s) => window == null
      ? true
      : s.tOffsetMs >= window.startSec * 1000 &&
          s.tOffsetMs <= window.endSec * 1000;

  final effort = samples.where(inWindow).toList();

  // A long-enough effort with a real power drop-off supports a CP fit that
  // beats the fixed factor.
  final effortSeconds = window == null ? 0 : window.endSec - window.startSec;
  if (effortSeconds >= 180) {
    final cp = _tryCriticalPower(effort, protocol);
    if (cp != null) {
      final paces = [
        for (final s in effort)
          if (s.paceSec500m != null && s.paceSec500m! > 0) s.paceSec500m!,
      ];
      return FtpResult(
        watts: cp.watts,
        protocol: protocol,
        method: FtpMethod.criticalPower,
        effortWatts: cp.effortWatts,
        effortPaceSeconds: paces.isEmpty ? null : _mean(paces),
        cpWPrime: cp.cpWPrime,
      );
    }
  }
  final powers = [
    for (final s in effort)
      if (s.powerW != null && s.powerW! > 0) s.powerW!,
  ];
  final paces = [
    for (final s in effort)
      if (s.paceSec500m != null && s.paceSec500m! > 0) s.paceSec500m!,
  ];

  if (powers.length >= 5) {
    return FtpResult(
      watts: _mean(powers) * protocol.multiplier,
      protocol: protocol,
      effortWatts: _mean(powers),
      effortPaceSeconds: paces.isEmpty ? null : _mean(paces),
      lowConfidence: powers.length < 20,
    );
  }

  // No usable samples — fall back to the session's own distance / time.
  final d = detail.totalDistanceM;
  final t = detail.durationSeconds;
  if (d > 0 && t > 0) {
    final avgPace = t / d * 500;
    final avgW = wattsForSplit(avgPace);
    return FtpResult(
      watts: avgW * protocol.multiplier,
      protocol: protocol,
      effortWatts: avgW,
      effortPaceSeconds: avgPace,
      lowConfidence: true,
    );
  }
  return FtpResult(watts: 0, protocol: protocol, lowConfidence: true);
}

/// A rough training-level suggestion from FTP. 2k power ≈ FTP / 0.76. No body
/// weight is considered, so this is only a starting point.
ProgramLevel suggestedLevelFromFtp(double ftpWatts) {
  if (ftpWatts <= 0) return ProgramLevel.medium;
  final split2k = splitForWatts(ftpWatts / 0.76);
  if (split2k > 135) return ProgramLevel.beginner; // slower than 2:15
  if (split2k >= 120) return ProgramLevel.medium; // 2:00–2:15
  return ProgramLevel.advanced; // faster than 2:00
}

/// The rising watt target of a ramp test.
class RampProtocol {
  const RampProtocol({this.startWatts = 100, this.incrementWatts = 25});

  final double startWatts;
  final double incrementWatts;
  static const int stepSeconds = 60;

  /// Seeds the start at ~55 % of a known FTP (rounded to 10 W), else 100 W.
  factory RampProtocol.seeded(double? priorFtp) {
    if (priorFtp == null || priorFtp <= 0) return const RampProtocol();
    final start = ((priorFtp * 0.55) / 10).round() * 10.0;
    return RampProtocol(startWatts: math.max(80, start));
  }

  /// Target watts for step [n] (0-based).
  double targetForStep(int n) => startWatts + n * incrementWatts;
}

// --- Guided-test segments ------------------------------------------------

ProgramRowSegment _seg(
  int order,
  int seconds, {
  required int spm,
  required String label,
  required RowIntensity zone,
  bool rest = false,
}) =>
    ProgramRowSegment(
      id: 0,
      programDayId: 0,
      orderIndex: order,
      durationSeconds: seconds,
      targetStrokeRate: spm,
      intensityLabel: label,
      isRest: rest,
      zone: zone.name,
    );

/// Warm-up / all-out effort / cool-down for a guided FTP test. Not part of the
/// [rowWorkouts] catalogue — reached only from the FTP screen.
List<ProgramRowSegment> ftpTestSegments(FtpProtocol p, ProgramLevel level) {
  final lvl = level.index; // 0 beginner, 1 medium, 2 advanced
  switch (p) {
    case FtpProtocol.test20:
      return [
        _seg(0, 300, spm: 18, label: 'Warming-up', zone: RowIntensity.easy),
        _seg(1, 1200,
            spm: 26 + lvl, label: '20 min all-out', zone: RowIntensity.max),
        _seg(2, 240, spm: 16, label: 'Uitroeien', zone: RowIntensity.easy),
      ];
    case FtpProtocol.testShort:
      return [
        _seg(0, 360, spm: 18, label: 'Warming-up', zone: RowIntensity.easy),
        _seg(1, 480,
            spm: 30 + lvl, label: '~2.000 m all-out', zone: RowIntensity.max),
        _seg(2, 240, spm: 16, label: 'Uitroeien', zone: RowIntensity.easy),
      ];
    case FtpProtocol.ramp:
      return const []; // driven by RampTestController, not a segment list
  }
}
