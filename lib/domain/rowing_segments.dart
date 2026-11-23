import 'models/program.dart';
import 'rowing_format.dart' show blockDistanceLabel;

/// Whether [seg] has run its course: the metres rowed for a distance block, the
/// time for a timed one.
bool segmentComplete(
  ProgramRowSegment seg, {
  required int elapsedSeconds,
  required double distanceM,
}) =>
    seg.isDistance
        ? distanceM >= seg.distanceM!
        : elapsedSeconds >= seg.durationSeconds;

/// A block's length for a list: its distance (`2 km`) for a distance block,
/// else its duration formatted by [timeLabel].
String segmentLengthLabel(
        ProgramRowSegment seg, String Function(int seconds) timeLabel) =>
    seg.isDistance
        ? blockDistanceLabel(seg.distanceM!)
        : timeLabel(seg.durationSeconds);

/// Where a session is in its plan: the block, how long it has been in it, and
/// the session distance at which the block began.
typedef SegmentCursor = ({
  int index,
  int elapsedSeconds,
  double startDistanceM,
});

/// Works out the block a session was in after it ran for [elapsed] and covered
/// [distanceM] — used when an app restart picks a session back up. A timed block
/// is over after its duration; a distance block when the session distance has
/// grown by its metres, which is read back from the saved [samples] (elapsed ms,
/// cumulative metres, oldest first). Once every block has run its course the
/// cursor stays on the last one.
SegmentCursor locateSegment(
  List<ProgramRowSegment> segments,
  List<({int tMs, double distanceM})> samples,
  Duration elapsed,
  double distanceM,
) {
  if (segments.isEmpty) {
    return (index: 0, elapsedSeconds: elapsed.inSeconds, startDistanceM: 0);
  }
  final elapsedMs = elapsed.inMilliseconds;

  // (time, distance) track, monotone in both; anchored at the origin and at now.
  final track = <({int tMs, double d})>[(tMs: 0, d: 0)];
  for (final s in samples) {
    if (s.tMs <= track.last.tMs) continue;
    track.add((tMs: s.tMs, d: s.distanceM < track.last.d ? track.last.d : s.distanceM));
  }
  if (elapsedMs > track.last.tMs) {
    track.add((tMs: elapsedMs, d: distanceM < track.last.d ? track.last.d : distanceM));
  }

  double distanceAt(int tMs) {
    if (tMs <= 0) return 0;
    for (var i = 1; i < track.length; i++) {
      if (tMs <= track[i].tMs) {
        final a = track[i - 1], b = track[i];
        final f = (tMs - a.tMs) / (b.tMs - a.tMs);
        return a.d + (b.d - a.d) * f;
      }
    }
    return track.last.d;
  }

  /// The time at which the session had covered [d] metres, or null if not yet.
  int? timeAtDistance(double d) {
    if (d <= 0) return 0;
    for (var i = 1; i < track.length; i++) {
      if (track[i].d >= d) {
        final a = track[i - 1], b = track[i];
        if (b.d == a.d) return b.tMs;
        final f = (d - a.d) / (b.d - a.d);
        return (a.tMs + (b.tMs - a.tMs) * f).round();
      }
    }
    return null;
  }

  var t = 0;
  for (var i = 0; i < segments.length; i++) {
    final seg = segments[i];
    final startD = distanceAt(t);
    final int? endT = seg.isDistance
        ? timeAtDistance(startD + seg.distanceM!)
        : t + seg.durationSeconds * 1000;
    final isLast = i == segments.length - 1;
    if (endT == null || endT > elapsedMs || isLast) {
      return (
        index: i,
        elapsedSeconds: ((elapsedMs - t) ~/ 1000).clamp(0, 1 << 30),
        startDistanceM: startD,
      );
    }
    t = endT;
  }
  // Unreachable (the last block always returns above).
  return (index: segments.length - 1, elapsedSeconds: 0, startDistanceM: 0);
}
