import 'package:flutter/widgets.dart';

/// A consistent spacing scale — use these instead of ad-hoc `SizedBox` values.
abstract class Gap {
  static const xs = SizedBox(height: 4, width: 4);
  static const s = SizedBox(height: 8, width: 8);
  static const m = SizedBox(height: 12, width: 12);
  static const l = SizedBox(height: 16, width: 16);
  static const xl = SizedBox(height: 24, width: 24);
}

/// Standard screen-level padding — use instead of ad-hoc `EdgeInsets`.
abstract class Insets {
  /// A plain padded screen (`Padding` around a single child).
  static const screen = EdgeInsets.all(16);

  /// A scrolling `ListView`'s content padding — extra room at the bottom so
  /// the last item clears the bottom nav / gesture bar.
  static const screenList = EdgeInsets.fromLTRB(16, 16, 16, 32);

  /// Inside a `Card`.
  static const card = EdgeInsets.all(16);
}
