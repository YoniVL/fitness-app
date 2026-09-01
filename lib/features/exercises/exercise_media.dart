import 'package:flutter/material.dart';

/// Bundled two-frame demo photos per exercise (start / end position), shown as
/// a slow cross-fade so you can see the movement.
///
/// Photos: everkinetic (https://everkinetic.com) via
/// https://github.com/yuhonas/free-exercise-db — licensed **CC BY-SA 3.0**.
/// The attribution lives in the Settings › Credits screen; keep it there.
const String exercisePhotoCredit =
    'Oefeningfoto’s: everkinetic, via free-exercise-db (github.com/yuhonas/'
    'free-exercise-db). Licentie: Creative Commons Naamsvermelding-GelijkDelen '
    '3.0 (CC BY-SA 3.0).';

/// Exercise name (canonical English, as seeded) → asset slug. Files live at
/// `assets/exercise_media/<slug>_0.jpg` and `<slug>_1.jpg`.
const Map<String, String> _photoSlugs = {
  'Barbell Romanian deadlift': 'barbell_romanian_deadlift',
  'Barbell back squat': 'barbell_back_squat',
  'Barbell bench press': 'barbell_bench_press',
  'Barbell curl': 'barbell_curl',
  'Barbell deadlift': 'barbell_deadlift',
  'Barbell front squat': 'barbell_front_squat',
  'Barbell hip thrust': 'barbell_hip_thrust',
  'Barbell incline press': 'barbell_incline_press',
  'Barbell overhead press': 'barbell_overhead_press',
  'Barbell row': 'barbell_row',
  'Barbell skull crusher': 'barbell_skull_crusher',
  'Cable crunch': 'cable_crunch',
  'Cable face pull': 'cable_face_pull',
  'Cable fly': 'cable_fly',
  'Cable lat pulldown': 'cable_lat_pulldown',
  'Cable seated row': 'cable_seated_row',
  'Cable triceps pushdown': 'cable_triceps_pushdown',
  'Dead bug': 'dead_bug',
  'Dips': 'dips',
  'Dumbbell Arnold press': 'dumbbell_arnold_press',
  'Dumbbell Bulgarian split squat': 'dumbbell_bulgarian_split_squat',
  'Dumbbell Romanian deadlift': 'dumbbell_romanian_deadlift',
  'Dumbbell Russian twist': 'dumbbell_russian_twist',
  'Dumbbell bench press': 'dumbbell_bench_press',
  'Dumbbell chest-supported row': 'dumbbell_chest_supported_row',
  'Dumbbell close-grip press': 'dumbbell_close_grip_press',
  'Dumbbell concentration curl': 'dumbbell_concentration_curl',
  'Dumbbell curl': 'dumbbell_curl',
  'Dumbbell floor press': 'dumbbell_floor_press',
  'Dumbbell fly': 'dumbbell_fly',
  'Dumbbell front raise': 'dumbbell_front_raise',
  'Dumbbell goblet squat': 'dumbbell_goblet_squat',
  'Dumbbell hammer curl': 'dumbbell_hammer_curl',
  'Dumbbell high-incline row': 'dumbbell_high_incline_row',
  'Dumbbell hip thrust': 'dumbbell_hip_thrust',
  'Dumbbell incline curl': 'dumbbell_incline_curl',
  'Dumbbell incline press': 'dumbbell_incline_press',
  'Dumbbell kickback': 'dumbbell_kickback',
  'Dumbbell lateral raise': 'dumbbell_lateral_raise',
  'Dumbbell one-arm row': 'dumbbell_one_arm_row',
  'Dumbbell overhead triceps extension': 'dumbbell_overhead_triceps_extension',
  'Dumbbell pullover': 'dumbbell_pullover',
  'Dumbbell reverse fly': 'dumbbell_reverse_fly',
  'Dumbbell seated calf raise': 'dumbbell_seated_calf_raise',
  'Dumbbell shoulder press': 'dumbbell_shoulder_press',
  'Dumbbell side bend': 'dumbbell_side_bend',
  'Dumbbell single-leg RDL': 'dumbbell_single_leg_rdl',
  'Dumbbell split squat': 'dumbbell_split_squat',
  'Dumbbell standing calf raise': 'dumbbell_standing_calf_raise',
  'Dumbbell step-up': 'dumbbell_step_up',
  'Dumbbell swing': 'dumbbell_swing',
  'Dumbbell walking lunge': 'dumbbell_walking_lunge',
  'Glute bridge': 'glute_bridge',
  'Hanging leg raise': 'hanging_leg_raise',
  'Lying leg raise': 'lying_leg_raise',
  'Machine leg curl': 'machine_leg_curl',
  'Machine leg extension': 'machine_leg_extension',
  'Machine leg press': 'machine_leg_press',
  'Machine seated calf raise': 'machine_seated_calf_raise',
  'Machine standing calf raise': 'machine_standing_calf_raise',
  'Plank': 'plank',
  'Pull-up': 'pull_up',
  'Push-up': 'push_up',
};

/// The two asset paths for [exerciseName], or null when there is no demo.
List<String>? exercisePhotoAssets(String? exerciseName) {
  if (exerciseName == null) return null;
  final slug = _photoSlugs[exerciseName];
  if (slug == null) return null;
  return [
    'assets/exercise_media/${slug}_0.jpg',
    'assets/exercise_media/${slug}_1.jpg',
  ];
}

bool hasExercisePhoto(String? exerciseName) =>
    exerciseName != null && _photoSlugs.containsKey(exerciseName);

/// Two-frame exercise demo: the start and end position of the rep, cross-fading
/// back and forth. Renders nothing when the exercise has no bundled photos.
class ExerciseDemo extends StatefulWidget {
  const ExerciseDemo({
    super.key,
    required this.exerciseName,
    this.maxHeight = 210,
    this.borderRadius = 16,
  });

  final String? exerciseName;

  /// The demo is a fixed 3:2 panel sized to the available width, capped here.
  final double maxHeight;
  final double borderRadius;

  @override
  State<ExerciseDemo> createState() => _ExerciseDemoState();
}

class _ExerciseDemoState extends State<ExerciseDemo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.38, 0.62, curve: Curves.easeInOut),
  );

  List<String>? _assets;
  bool _precached = false;

  @override
  void initState() {
    super.initState();
    _assets = exercisePhotoAssets(widget.exerciseName);
    if (_assets != null) _c.repeat(reverse: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_precached && _assets != null) {
      _precached = true;
      for (final a in _assets!) {
        precacheImage(AssetImage(a), context);
      }
    }
  }

  @override
  void didUpdateWidget(ExerciseDemo old) {
    super.didUpdateWidget(old);
    if (old.exerciseName != widget.exerciseName) {
      _assets = exercisePhotoAssets(widget.exerciseName);
      _precached = false;
      if (_assets != null) {
        _c.repeat(reverse: true);
      } else {
        _c.stop();
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final assets = _assets;
    if (assets == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : widget.maxHeight * 1.5;
        var h = availW * 2 / 3;
        if (h > widget.maxHeight) h = widget.maxHeight;
        if (constraints.maxHeight.isFinite && h > constraints.maxHeight) {
          h = constraints.maxHeight;
        }
        final w = h * 1.5;

        return Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: SizedBox(
              width: w,
              height: h,
              child: AnimatedBuilder(
                animation: _fade,
                builder: (context, _) => Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: scheme.surfaceContainerHighest),
                    Image.asset(assets[0], fit: BoxFit.cover),
                    Opacity(
                      opacity: _fade.value,
                      child: Image.asset(assets[1], fit: BoxFit.cover),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
