/// Formatting helpers for rowing numbers — pace, distance, duration.
///
/// Dutch conventions: decimal comma, "km" past 1000 m.
library;

/// `Duration` → `mm:ss`, or `h:mm:ss` past an hour.
String hmsLabel(Duration d) {
  final total = d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}

/// Seconds per 500 m → `2:11 /500m`. Null / non-positive → `–`.
String paceLabel(double? secPer500, {bool withUnit = true}) {
  if (secPer500 == null || secPer500 <= 0 || secPer500.isInfinite) return '–';
  final total = secPer500.round();
  final m = total ~/ 60;
  final s = (total % 60).toString().padLeft(2, '0');
  return withUnit ? '$m:$s /500m' : '$m:$s';
}

/// Pace from a distance + duration (for summaries without a stored pace).
double? paceSecPer500(double distanceM, Duration elapsed) {
  if (distanceM <= 0 || elapsed.inMilliseconds <= 0) return null;
  return elapsed.inMilliseconds / 1000 / distanceM * 500;
}

/// Metres → `850 m` or `3,2 km`.
String distanceLabel(double metres) {
  if (metres < 1000) return '${metres.round()} m';
  final km = metres / 1000;
  final text = km.toStringAsFixed(km >= 10 ? 0 : 1);
  return '${text.replaceAll('.', ',')} km';
}

/// Stroke rate → `24 SPM`. Null / zero → `–`.
String spmLabel(double? spm) {
  if (spm == null || spm <= 0) return '–';
  return '${spm.round()} SPM';
}

/// Power in watts → `142 W`. Null / zero → `–`.
String powerLabel(double? watts) {
  if (watts == null || watts <= 0) return '–';
  return '${watts.round()} W';
}
