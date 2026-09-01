import 'package:flutter/material.dart';

import '../../domain/taxonomy.dart';

/// A small looping stick-figure animation of an exercise. There's no per-exercise
/// media yet, so the animation is built from the movement [pattern] plus the
/// [equipment] (bench, barbell vs dumbbells) — enough to see how it roughly works.
class ExerciseAnimation extends StatefulWidget {
  const ExerciseAnimation({
    super.key,
    required this.pattern,
    this.equipment = const [],
    this.size = 160,
  });

  final MovementPattern? pattern;
  final List<String> equipment;
  final double size;

  @override
  State<ExerciseAnimation> createState() => _ExerciseAnimationState();
}

class _ExerciseAnimationState extends State<ExerciseAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final def = _defFor(widget.pattern, widget.equipment.toSet());
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeInOut);
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: curve,
        builder: (context, _) => CustomPaint(
          painter: _FigurePainter(
            pose: _Pose.lerp(def.a, def.b, curve.value),
            prop: def.prop,
            load: def.load,
            twoArmed: def.twoArmed,
            ink: scheme.onSurface.withValues(alpha: 0.92),
            far: scheme.onSurface.withValues(alpha: 0.33),
            accent: scheme.primary,
            faint: scheme.onSurface.withValues(alpha: 0.14),
          ),
        ),
      ),
    );
  }
}

enum _Prop { none, benchFlat, benchIncline, benchHip }

enum _Load { none, barbell, dumbbell }

/// Joints in a 100x100, y-down box. Figure faces right (+x). [handLoad] toggles
/// which anchor the weight hangs on (hands, or hips for squat/hip-thrust).
class _Pose {
  const _Pose({
    required this.head,
    required this.neck,
    required this.hip,
    required this.knee,
    required this.ankle,
    required this.elbow,
    required this.hand,
    this.loadAtHip = false,
  });

  final Offset head, neck, hip, knee, ankle, elbow, hand;
  final bool loadAtHip;

  static _Pose lerp(_Pose a, _Pose b, double t) => _Pose(
        head: Offset.lerp(a.head, b.head, t)!,
        neck: Offset.lerp(a.neck, b.neck, t)!,
        hip: Offset.lerp(a.hip, b.hip, t)!,
        knee: Offset.lerp(a.knee, b.knee, t)!,
        ankle: Offset.lerp(a.ankle, b.ankle, t)!,
        elbow: Offset.lerp(a.elbow, b.elbow, t)!,
        hand: Offset.lerp(a.hand, b.hand, t)!,
        loadAtHip: a.loadAtHip,
      );
}

class _AnimDef {
  const _AnimDef(this.a, this.b,
      {this.twoArmed = true, this.prop = _Prop.none, this.load = _Load.none});
  final _Pose a, b;
  final bool twoArmed;
  final _Prop prop;
  final _Load load;
}

const _standing = _Pose(
  head: Offset(50, 13),
  neck: Offset(50, 26),
  hip: Offset(50, 53),
  knee: Offset(50, 73),
  ankle: Offset(50, 91),
  elbow: Offset(50, 40),
  hand: Offset(50, 52),
);

_Pose _w(_Pose b,
        {Offset? head,
        Offset? neck,
        Offset? hip,
        Offset? knee,
        Offset? ankle,
        Offset? elbow,
        Offset? hand,
        bool? loadAtHip}) =>
    _Pose(
      head: head ?? b.head,
      neck: neck ?? b.neck,
      hip: hip ?? b.hip,
      knee: knee ?? b.knee,
      ankle: ankle ?? b.ankle,
      elbow: elbow ?? b.elbow,
      hand: hand ?? b.hand,
      loadAtHip: loadAtHip ?? b.loadAtHip,
    );

_Load _loadFor(Set<String> eq) {
  if (eq.contains(Equipment.barbell)) return _Load.barbell;
  if (eq.contains(Equipment.dumbbell) || eq.contains(Equipment.kettlebell)) {
    return _Load.dumbbell;
  }
  return _Load.none;
}

_AnimDef _defFor(MovementPattern? p, Set<String> eq) {
  final hasBench = eq.contains(Equipment.bench);
  final hasIncline = eq.contains(Equipment.benchIncline);
  final load = _loadFor(eq);

  switch (p) {
    // --- Pressing --------------------------------------------------------
    case MovementPattern.horizontalPush:
      if (hasBench || hasIncline) {
        // Lying supine on a (flat or inclined) bench, pressing up.
        final incline = hasIncline && !hasBench;
        final base = incline
            ? const _Pose(
                head: Offset(22, 40),
                neck: Offset(30, 45),
                hip: Offset(58, 60),
                knee: Offset(66, 74),
                ankle: Offset(72, 91),
                elbow: Offset(40, 44),
                hand: Offset(46, 40))
            : const _Pose(
                head: Offset(20, 53),
                neck: Offset(29, 54),
                hip: Offset(60, 55),
                knee: Offset(66, 72),
                ankle: Offset(71, 90),
                elbow: Offset(39, 46),
                hand: Offset(41, 40));
        return _AnimDef(
          base,
          _w(base,
              elbow: Offset(base.elbow.dx + 4, base.elbow.dy - 10),
              hand: Offset(base.hand.dx + 6, base.hand.dy - 18)),
          prop: incline ? _Prop.benchIncline : _Prop.benchFlat,
          load: load == _Load.none ? _Load.dumbbell : load,
        );
      }
      return _AnimDef(
        _w(_standing, elbow: const Offset(43, 34), hand: const Offset(38, 40)),
        _w(_standing, elbow: const Offset(60, 34), hand: const Offset(86, 34)),
        load: load,
      );
    case MovementPattern.verticalPush:
      return _AnimDef(
        _w(_standing, elbow: const Offset(58, 30), hand: const Offset(56, 22)),
        _w(_standing, elbow: const Offset(52, 9), hand: const Offset(51, -1)),
        load: load == _Load.none ? _Load.dumbbell : load,
      );

    // --- Pulling --------------------------------------------------------
    case MovementPattern.horizontalPull:
      if (hasIncline) {
        // Chest-supported row: prone on an incline bench, pulling elbows back.
        const base = _Pose(
          head: Offset(24, 34),
          neck: Offset(32, 39),
          hip: Offset(60, 56),
          knee: Offset(66, 72),
          ankle: Offset(72, 90),
          elbow: Offset(30, 52),
          hand: Offset(28, 62),
        );
        return _AnimDef(
          base,
          _w(base, elbow: const Offset(42, 42), hand: const Offset(40, 46)),
          prop: _Prop.benchIncline,
          load: load == _Load.none ? _Load.dumbbell : load,
        );
      }
      final bent = _w(_standing,
          head: const Offset(34, 20),
          neck: const Offset(41, 29),
          hip: const Offset(55, 49),
          knee: const Offset(55, 71),
          ankle: const Offset(55, 91));
      return _AnimDef(
        _w(bent, elbow: const Offset(44, 44), hand: const Offset(40, 64)),
        _w(bent, elbow: const Offset(58, 36), hand: const Offset(56, 44)),
        load: load,
      );
    case MovementPattern.verticalPull:
      return _AnimDef(
        _w(_standing, elbow: const Offset(54, 7), hand: const Offset(56, -2)),
        _w(_standing, elbow: const Offset(64, 34), hand: const Offset(56, 46)),
        load: load,
      );

    // --- Legs ---------------------------------------------------------
    case MovementPattern.squat:
      final barback = load == _Load.barbell;
      return _AnimDef(
        _w(_standing,
            elbow: const Offset(44, 26),
            hand: const Offset(38, 24),
            loadAtHip: false),
        _w(_standing,
            head: const Offset(40, 30),
            neck: const Offset(45, 40),
            hip: const Offset(46, 65),
            knee: const Offset(62, 76),
            ankle: const Offset(52, 91),
            elbow: const Offset(41, 34),
            hand: const Offset(35, 32)),
        load: barback ? _Load.barbell : load,
      );
    case MovementPattern.hinge:
      if (hasBench && load != _Load.none) {
        // Hip thrust: upper back on the bench, hips drive up.
        const down = _Pose(
          head: Offset(24, 44),
          neck: Offset(31, 45),
          hip: Offset(54, 66),
          knee: Offset(72, 66),
          ankle: Offset(80, 89),
          elbow: Offset(31, 55),
          hand: Offset(28, 62),
          loadAtHip: true,
        );
        return _AnimDef(
          down,
          _w(down,
              hip: const Offset(56, 47),
              knee: const Offset(74, 56),
              neck: const Offset(31, 45)),
          prop: _Prop.benchHip,
          load: load,
          twoArmed: false,
        );
      }
      return _AnimDef(
        _standing,
        _w(_standing,
            head: const Offset(26, 26),
            neck: const Offset(37, 32),
            hip: const Offset(55, 49),
            knee: const Offset(56, 71),
            ankle: const Offset(56, 91),
            elbow: const Offset(44, 54),
            hand: const Offset(42, 74)),
        load: load,
      );
    case MovementPattern.lunge:
      return _AnimDef(
        _w(_standing,
            hip: const Offset(50, 52),
            knee: const Offset(56, 72),
            elbow: const Offset(50, 44),
            hand: const Offset(50, 56)),
        _w(_standing,
            hip: const Offset(52, 62),
            knee: const Offset(58, 82),
            ankle: const Offset(60, 91),
            neck: const Offset(52, 34),
            head: const Offset(52, 21),
            elbow: const Offset(52, 46),
            hand: const Offset(52, 58)),
        load: load,
        prop: hasBench ? _Prop.benchFlat : _Prop.none,
      );

    // --- Core & isolation ----------------------------------------------
    case MovementPattern.core:
      const lying = _Pose(
        head: Offset(74, 62),
        neck: Offset(66, 64),
        hip: Offset(44, 68),
        knee: Offset(34, 54),
        ankle: Offset(28, 66),
        elbow: Offset(66, 56),
        hand: Offset(72, 52),
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
        load: load == _Load.none ? _Load.dumbbell : load,
      );
    case MovementPattern.tricepsIso:
      return _AnimDef(
        _w(_standing, elbow: const Offset(50, 32), hand: const Offset(55, 22)),
        _w(_standing, elbow: const Offset(50, 32), hand: const Offset(52, 56)),
        twoArmed: false,
        load: load == _Load.none ? _Load.dumbbell : load,
      );
    case MovementPattern.sideDeltIso:
      return _AnimDef(
        _w(_standing, elbow: const Offset(52, 44), hand: const Offset(53, 56)),
        _w(_standing, elbow: const Offset(68, 27), hand: const Offset(88, 26)),
        load: _Load.dumbbell,
      );
    case MovementPattern.calfIso:
      return _AnimDef(
        _w(_standing, hand: const Offset(50, 50)),
        _w(_standing,
            head: const Offset(50, 9),
            neck: const Offset(50, 22),
            hip: const Offset(50, 49),
            knee: const Offset(50, 69),
            ankle: const Offset(50, 88),
            elbow: const Offset(50, 36),
            hand: const Offset(50, 46)),
        load: load,
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
    required this.prop,
    required this.load,
    required this.twoArmed,
    required this.ink,
    required this.far,
    required this.accent,
    required this.faint,
  });

  final _Pose pose;
  final _Prop prop;
  final _Load load;
  final bool twoArmed;
  final Color ink, far, accent, faint;

  Offset _p(Offset o, Size s) =>
      Offset(o.dx / 100 * s.width, o.dy / 100 * s.height);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    Paint line(Color c, [double mul = 1]) => Paint()
      ..color = c
      ..strokeWidth = w * 0.032 * mul
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // Ground.
    canvas.drawLine(Offset(w * 0.1, size.height * 0.94),
        Offset(w * 0.9, size.height * 0.94), line(faint, 0.7));

    // --- Prop (bench) --------------------------------------------------
    final benchPaint = Paint()..color = faint;
    switch (prop) {
      case _Prop.benchFlat:
        _rrect(canvas, size, 22, 56, 60, 62, benchPaint);
        _leg(canvas, size, 28, 62, 92);
        _leg(canvas, size, 66, 62, 92);
      case _Prop.benchIncline:
        // Reclined backrest: rises toward the head (upper-left), sitting just
        // behind the figure's spine.
        final back = Path()
          ..moveTo(_x(16, w), _y(46, size))
          ..lineTo(_x(60, w), _y(66, size))
          ..lineTo(_x(60, w), _y(73, size))
          ..lineTo(_x(16, w), _y(53, size))
          ..close();
        canvas.drawPath(back, benchPaint);
        // Seat pad at the low end.
        _rrect(canvas, size, 56, 67, 80, 74, benchPaint);
        _leg(canvas, size, 22, 53, 92);
        _leg(canvas, size, 72, 74, 92);
      case _Prop.benchHip:
        _rrect(canvas, size, 16, 46, 40, 52, benchPaint);
        _leg(canvas, size, 20, 52, 88);
        _leg(canvas, size, 40, 52, 88);
      case _Prop.none:
        break;
    }

    final neck = _p(pose.neck, size);
    final hip = _p(pose.hip, size);
    final knee = _p(pose.knee, size);
    final ankle = _p(pose.ankle, size);
    final elbow = _p(pose.elbow, size);
    final hand = _p(pose.hand, size);
    final head = _p(pose.head, size);
    final dx = w * 0.045;

    // Far-side limbs (behind), lighter & thinner.
    final farKnee =
        Offset.lerp(Offset(hip.dx, (hip.dy + ankle.dy) / 2), knee, 0.6)!;
    canvas.drawLine(Offset(hip.dx - dx, hip.dy),
        Offset(farKnee.dx - dx, farKnee.dy), line(far, 0.8));
    canvas.drawLine(Offset(farKnee.dx - dx, farKnee.dy),
        Offset(ankle.dx - dx, ankle.dy), line(far, 0.8));
    if (twoArmed) {
      final farElbow = Offset.lerp(neck, elbow, 0.7)!;
      canvas.drawLine(neck, Offset(farElbow.dx - dx, farElbow.dy), line(far, 0.8));
      canvas.drawLine(Offset(farElbow.dx - dx, farElbow.dy),
          Offset(hand.dx - dx, hand.dy), line(far, 0.8));
    }

    // Torso, near leg, near arm.
    final near = line(ink);
    canvas.drawLine(neck, hip, near);
    canvas.drawLine(hip, knee, near);
    canvas.drawLine(knee, ankle, near);
    canvas.drawLine(neck, elbow, near);
    canvas.drawLine(elbow, hand, near);
    // Shoulder + hip bars.
    canvas.drawLine(Offset(neck.dx - dx * 0.6, neck.dy),
        Offset(neck.dx + dx * 0.6, neck.dy), near);
    canvas.drawLine(Offset(hip.dx - dx * 0.6, hip.dy),
        Offset(hip.dx + dx * 0.6, hip.dy), near);

    // Head.
    canvas.drawCircle(
        head, w * 0.072, Paint()..color = ink ..style = PaintingStyle.fill);

    // --- Load --------------------------------------------------------
    final anchor = pose.loadAtHip ? hip : hand;
    switch (load) {
      case _Load.none:
        break;
      case _Load.barbell:
        final barPaint = Paint()
          ..color = accent
          ..strokeWidth = w * 0.028
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(anchor.dx - w * 0.24, anchor.dy),
            Offset(anchor.dx + w * 0.24, anchor.dy), barPaint);
        for (final s in const [-1, 1]) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset(anchor.dx + s * w * 0.22, anchor.dy),
                  width: w * 0.05,
                  height: w * 0.16),
              Radius.circular(w * 0.01),
            ),
            Paint()..color = accent,
          );
        }
      case _Load.dumbbell:
        final p = Paint()
          ..color = accent
          ..strokeWidth = w * 0.05
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(hand.dx - w * 0.05, hand.dy),
            Offset(hand.dx + w * 0.05, hand.dy), p);
        if (twoArmed) {
          canvas.drawLine(Offset(hand.dx - dx - w * 0.05, hand.dy),
              Offset(hand.dx - dx + w * 0.05, hand.dy),
              p..color = far);
        }
    }
  }

  double _x(double v, double w) => v / 100 * w;
  double _y(double v, Size s) => v / 100 * s.height;

  void _rrect(Canvas c, Size s, double x, double y, double x2, double y2,
      Paint p) {
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(_x(x, s.width), _y(y, s), _x(x2, s.width), _y(y2, s)),
        Radius.circular(s.width * 0.02),
      ),
      p,
    );
  }

  void _leg(Canvas c, Size s, double x, double y, double y2) {
    c.drawLine(Offset(_x(x, s.width), _y(y, s)),
        Offset(_x(x, s.width), _y(y2, s)),
        Paint()
          ..color = faint
          ..strokeWidth = s.width * 0.02);
  }

  @override
  bool shouldRepaint(_FigurePainter old) => true;
}
