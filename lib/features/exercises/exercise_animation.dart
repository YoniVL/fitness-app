import 'package:flutter/material.dart';

import '../../domain/taxonomy.dart';

/// A small looping stick-figure animation of a movement pattern. There is no
/// per-exercise media yet, so every exercise shows the animation for its
/// [MovementPattern] — enough to see how the movement roughly works.
class ExerciseAnimation extends StatefulWidget {
  const ExerciseAnimation({super.key, required this.pattern, this.size = 160});

  final MovementPattern? pattern;
  final double size;

  @override
  State<ExerciseAnimation> createState() => _ExerciseAnimationState();
}

class _ExerciseAnimationState extends State<ExerciseAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final def = _defFor(widget.pattern);
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeInOut);
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: curve,
        builder: (context, _) => CustomPaint(
          painter: _FigurePainter(
            pose: _Pose.lerp(def.a, def.b, curve.value),
            twoArmed: def.twoArmed,
            body: scheme.onSurface.withValues(alpha: 0.9),
            far: scheme.onSurface.withValues(alpha: 0.35),
            load: scheme.primary,
            ground: scheme.onSurface.withValues(alpha: 0.15),
          ),
        ),
      ),
    );
  }
}

/// Joints in a 100x100, y-down box. Figure faces right (+x).
class _Pose {
  const _Pose({
    required this.head,
    required this.neck,
    required this.hip,
    required this.knee,
    required this.ankle,
    required this.elbow,
    required this.hand,
    this.showLoad = true,
  });

  final Offset head, neck, hip, knee, ankle, elbow, hand;
  final bool showLoad;

  static _Pose lerp(_Pose a, _Pose b, double t) => _Pose(
        head: Offset.lerp(a.head, b.head, t)!,
        neck: Offset.lerp(a.neck, b.neck, t)!,
        hip: Offset.lerp(a.hip, b.hip, t)!,
        knee: Offset.lerp(a.knee, b.knee, t)!,
        ankle: Offset.lerp(a.ankle, b.ankle, t)!,
        elbow: Offset.lerp(a.elbow, b.elbow, t)!,
        hand: Offset.lerp(a.hand, b.hand, t)!,
        showLoad: a.showLoad,
      );
}

class _AnimDef {
  const _AnimDef(this.a, this.b, {this.twoArmed = true});
  final _Pose a, b;
  final bool twoArmed;
}

const _standing = _Pose(
  head: Offset(50, 13),
  neck: Offset(50, 26),
  hip: Offset(50, 54),
  knee: Offset(50, 74),
  ankle: Offset(50, 92),
  elbow: Offset(50, 40),
  hand: Offset(50, 52),
);

_Pose _w(_Pose base,
        {Offset? head,
        Offset? neck,
        Offset? hip,
        Offset? knee,
        Offset? ankle,
        Offset? elbow,
        Offset? hand,
        bool? showLoad}) =>
    _Pose(
      head: head ?? base.head,
      neck: neck ?? base.neck,
      hip: hip ?? base.hip,
      knee: knee ?? base.knee,
      ankle: ankle ?? base.ankle,
      elbow: elbow ?? base.elbow,
      hand: hand ?? base.hand,
      showLoad: showLoad ?? base.showLoad,
    );

_AnimDef _defFor(MovementPattern? p) {
  switch (p) {
    case MovementPattern.horizontalPush:
      return _AnimDef(
        _w(_standing, elbow: const Offset(44, 34), hand: const Offset(40, 40)),
        _w(_standing, elbow: const Offset(60, 34), hand: const Offset(84, 34)),
      );
    case MovementPattern.verticalPush:
      return _AnimDef(
        _w(_standing, elbow: const Offset(58, 30), hand: const Offset(56, 22)),
        _w(_standing, elbow: const Offset(52, 10), hand: const Offset(51, 0)),
      );
    case MovementPattern.horizontalPull:
      final bent = _w(_standing,
          head: const Offset(36, 20),
          neck: const Offset(42, 29),
          hip: const Offset(54, 50),
          knee: const Offset(54, 72),
          ankle: const Offset(54, 92));
      return _AnimDef(
        _w(bent, elbow: const Offset(44, 44), hand: const Offset(40, 62)),
        _w(bent, elbow: const Offset(58, 36), hand: const Offset(56, 44)),
      );
    case MovementPattern.verticalPull:
      return _AnimDef(
        _w(_standing, elbow: const Offset(54, 8), hand: const Offset(56, 0)),
        _w(_standing, elbow: const Offset(64, 34), hand: const Offset(56, 46)),
      );
    case MovementPattern.squat:
      return _AnimDef(
        _w(_standing, elbow: const Offset(56, 34), hand: const Offset(62, 30)),
        _w(_standing,
            head: const Offset(40, 30),
            neck: const Offset(45, 40),
            hip: const Offset(46, 66),
            knee: const Offset(62, 76),
            ankle: const Offset(52, 92),
            elbow: const Offset(58, 44),
            hand: const Offset(66, 40)),
      );
    case MovementPattern.hinge:
      return _AnimDef(
        _standing,
        _w(_standing,
            head: const Offset(28, 26),
            neck: const Offset(38, 32),
            hip: const Offset(54, 50),
            knee: const Offset(56, 72),
            ankle: const Offset(56, 92),
            elbow: const Offset(44, 54),
            hand: const Offset(42, 72)),
      );
    case MovementPattern.lunge:
      return _AnimDef(
        _standing,
        _w(_standing,
            hip: const Offset(50, 62),
            knee: const Offset(52, 84),
            ankle: const Offset(54, 92),
            neck: const Offset(50, 34),
            head: const Offset(50, 21),
            elbow: const Offset(50, 46),
            hand: const Offset(50, 58)),
      );
    case MovementPattern.core:
      final lying = _Pose(
        head: const Offset(74, 62),
        neck: const Offset(66, 64),
        hip: const Offset(44, 68),
        knee: const Offset(34, 54),
        ankle: const Offset(28, 66),
        elbow: const Offset(66, 56),
        hand: const Offset(72, 52),
        showLoad: false,
      );
      return _AnimDef(
        lying,
        _w(lying,
            head: const Offset(60, 40),
            neck: const Offset(56, 50),
            elbow: const Offset(54, 46),
            hand: const Offset(56, 40)),
        twoArmed: false,
      );
    case MovementPattern.bicepsIso:
      return _AnimDef(
        _w(_standing, elbow: const Offset(52, 44), hand: const Offset(56, 58)),
        _w(_standing, elbow: const Offset(52, 44), hand: const Offset(58, 26)),
        twoArmed: false,
      );
    case MovementPattern.tricepsIso:
      return _AnimDef(
        _w(_standing, elbow: const Offset(50, 34), hand: const Offset(54, 24)),
        _w(_standing, elbow: const Offset(50, 34), hand: const Offset(52, 56)),
        twoArmed: false,
      );
    case MovementPattern.sideDeltIso:
      return _AnimDef(
        _w(_standing, elbow: const Offset(52, 44), hand: const Offset(53, 56)),
        _w(_standing, elbow: const Offset(68, 28), hand: const Offset(86, 26)),
      );
    case MovementPattern.calfIso:
      return _AnimDef(
        _w(_standing, hand: const Offset(50, 50), showLoad: false),
        _w(_standing,
            head: const Offset(50, 9),
            neck: const Offset(50, 22),
            hip: const Offset(50, 50),
            knee: const Offset(50, 70),
            ankle: const Offset(50, 88),
            elbow: const Offset(50, 36),
            hand: const Offset(50, 46),
            showLoad: false),
      );
    case null:
      return _AnimDef(
        _w(_standing, elbow: const Offset(52, 44), hand: const Offset(56, 58)),
        _w(_standing, elbow: const Offset(52, 44), hand: const Offset(58, 30)),
        twoArmed: false,
      );
  }
}

class _FigurePainter extends CustomPainter {
  _FigurePainter({
    required this.pose,
    required this.twoArmed,
    required this.body,
    required this.far,
    required this.load,
    required this.ground,
  });

  final _Pose pose;
  final bool twoArmed;
  final Color body, far, load, ground;

  Offset _p(Offset o, Size s) =>
      Offset(o.dx / 100 * s.width, o.dy / 100 * s.height);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    Paint stroke(Color c) => Paint()
      ..color = c
      ..strokeWidth = w * 0.03
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // Ground.
    canvas.drawLine(
      Offset(w * 0.12, size.height * 0.95),
      Offset(w * 0.88, size.height * 0.95),
      Paint()
        ..color = ground
        ..strokeWidth = w * 0.02
        ..strokeCap = StrokeCap.round,
    );

    final neck = _p(pose.neck, size);
    final hip = _p(pose.hip, size);
    final knee = _p(pose.knee, size);
    final ankle = _p(pose.ankle, size);
    final elbow = _p(pose.elbow, size);
    final hand = _p(pose.hand, size);
    final head = _p(pose.head, size);
    final dx = w * 0.045;
    final farPaint = stroke(far)..strokeWidth = w * 0.024;

    // Far-side limbs first (behind), lighter and simpler: near leg's knee at
    // 60% bend, near arm's elbow at 70%.
    final farKnee = Offset.lerp(
        Offset(hip.dx, (hip.dy + ankle.dy) / 2), knee, 0.6)!;
    canvas.drawLine(Offset(hip.dx - dx, hip.dy),
        Offset(farKnee.dx - dx, farKnee.dy), farPaint);
    canvas.drawLine(Offset(farKnee.dx - dx, farKnee.dy),
        Offset(ankle.dx - dx, ankle.dy), farPaint);
    if (twoArmed) {
      final farElbow = Offset.lerp(neck, elbow, 0.7)!;
      canvas.drawLine(neck, Offset(farElbow.dx - dx, farElbow.dy), farPaint);
      canvas.drawLine(Offset(farElbow.dx - dx, farElbow.dy),
          Offset(hand.dx - dx, hand.dy), farPaint);
    }

    // Torso + near leg + near arm.
    final near = stroke(body);
    canvas.drawLine(neck, hip, near);
    canvas.drawLine(hip, knee, near);
    canvas.drawLine(knee, ankle, near);
    canvas.drawLine(neck, elbow, near);
    canvas.drawLine(elbow, hand, near);

    // Shoulder + hip bars, to read as a torso not a stick.
    canvas.drawLine(Offset(neck.dx - dx * 0.7, neck.dy),
        Offset(neck.dx + dx * 0.7, neck.dy), near);
    canvas.drawLine(Offset(hip.dx - dx * 0.7, hip.dy),
        Offset(hip.dx + dx * 0.7, hip.dy), near);

    // Head with a small gap from the neck.
    canvas.drawCircle(
        head, w * 0.075, Paint()..color = body ..style = PaintingStyle.fill);

    if (pose.showLoad) {
      canvas.drawCircle(hand, w * 0.055, Paint()..color = load);
    }
  }

  @override
  bool shouldRepaint(_FigurePainter old) => true;
}
