import 'package:flutter/material.dart';

/// A rectangle with one corner sliced off at 45° — the Modernist card motif.
/// Square everywhere else (the design system has zero corner radius).
///
/// [cut] is the leg length of the removed triangle, in logical pixels.
class ChamferBorder extends OutlinedBorder {
  const ChamferBorder({
    super.side = BorderSide.none,
    this.cut = 16,
    this.corner = Corner.topRight,
  });

  final double cut;
  final Corner corner;

  @override
  ChamferBorder copyWith({BorderSide? side, double? cut, Corner? corner}) =>
      ChamferBorder(
        side: side ?? this.side,
        cut: cut ?? this.cut,
        corner: corner ?? this.corner,
      );

  @override
  ChamferBorder scale(double t) =>
      ChamferBorder(side: side.scale(t), cut: cut * t, corner: corner);

  Path _path(Rect r, double c) {
    // Clamp so a small box can't produce a degenerate/self-crossing path.
    c = c.clamp(0, (r.shortestSide / 2)).toDouble();
    switch (corner) {
      case Corner.topLeft:
        return Path()
          ..moveTo(r.left + c, r.top)
          ..lineTo(r.right, r.top)
          ..lineTo(r.right, r.bottom)
          ..lineTo(r.left, r.bottom)
          ..lineTo(r.left, r.top + c)
          ..close();
      case Corner.topRight:
        return Path()
          ..moveTo(r.left, r.top)
          ..lineTo(r.right - c, r.top)
          ..lineTo(r.right, r.top + c)
          ..lineTo(r.right, r.bottom)
          ..lineTo(r.left, r.bottom)
          ..close();
      case Corner.bottomRight:
        return Path()
          ..moveTo(r.left, r.top)
          ..lineTo(r.right, r.top)
          ..lineTo(r.right, r.bottom - c)
          ..lineTo(r.right - c, r.bottom)
          ..lineTo(r.left, r.bottom)
          ..close();
      case Corner.bottomLeft:
        return Path()
          ..moveTo(r.left, r.top)
          ..lineTo(r.right, r.top)
          ..lineTo(r.right, r.bottom)
          ..lineTo(r.left + c, r.bottom)
          ..lineTo(r.left, r.bottom - c)
          ..close();
    }
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect.deflate(side.strokeInset), (cut - side.strokeInset).clamp(0, cut));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect, cut);

  @override
  void paintInterior(Canvas canvas, Rect rect, Paint paint,
          {TextDirection? textDirection}) =>
      canvas.drawPath(_path(rect, cut), paint);

  @override
  bool get preferPaintInterior => true;

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    final p = side.toPaint();
    canvas.drawPath(getOuterPath(rect.deflate(side.strokeOffset / 2)), p);
  }

  @override
  bool operator ==(Object other) =>
      other is ChamferBorder &&
      other.side == side &&
      other.cut == cut &&
      other.corner == corner;

  @override
  int get hashCode => Object.hash(side, cut, corner);
}

enum Corner { topLeft, topRight, bottomRight, bottomLeft }
