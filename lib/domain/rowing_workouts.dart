import 'models/program.dart';
import 'models/rowing_plan.dart';

/// Intensity zone of a block — drives the colour of the interval profile and a
/// rough stroke-rate band.
enum RowIntensity { easy, steady, threshold, hard, max, rest }

/// One block of a rowing workout (a segment before it is persisted).
class RowBlock {
  const RowBlock(
    this.seconds, {
    this.spm,
    this.intensity = RowIntensity.steady,
    required this.label,
    this.isRest = false,
    this.drillKey,
  });

  final int seconds;
  final int? spm;
  final RowIntensity intensity;
  final String label;
  final bool isRest;
  final String? drillKey;

  /// Derive an intensity zone from a stored segment's stroke rate + rest flag,
  /// for rendering older data that has no explicit zone.
  static RowIntensity zoneFor({required int? spm, required bool isRest}) {
    if (isRest) return RowIntensity.rest;
    if (spm == null) return RowIntensity.steady;
    if (spm <= 17) return RowIntensity.easy;
    if (spm <= 21) return RowIntensity.steady;
    if (spm <= 25) return RowIntensity.threshold;
    if (spm <= 29) return RowIntensity.hard;
    return RowIntensity.max;
  }
}

/// A named, reusable rowing workout. [blocks] builds the concrete blocks scaled
/// by [ProgramLevel] and a `build` factor (0..1, later weeks of a plan → higher).
class RowWorkout {
  const RowWorkout({
    required this.id,
    required this.name,
    required this.type,
    required this.focus,
    required this.approxMinutes,
    required this.blocks,
  });

  final String id;
  final String name;
  final RowSessionType type;
  final String focus;
  final int approxMinutes;
  final List<RowBlock> Function(ProgramLevel level, double build) blocks;
}

// --- block helpers ---------------------------------------------------

int _lvl(ProgramLevel l) => l.index; // 0 beginner, 1 medium, 2 advanced

RowBlock _wu([int min = 3]) =>
    RowBlock(min * 60, spm: 18, intensity: RowIntensity.easy, label: 'Warming-up');
RowBlock _cd([int min = 2]) =>
    RowBlock(min * 60, spm: 16, intensity: RowIntensity.easy, label: 'Uitroeien');
RowBlock _rest(int sec) => RowBlock(sec,
    spm: 16, intensity: RowIntensity.rest, label: 'Rust', isRest: true);

/// N × (work / rest), numbered, with warm-up + cool-down.
List<RowBlock> _reps(
  int reps, {
  required int workSec,
  required int restSec,
  required int spm,
  required RowIntensity intensity,
  required String workLabel,
  int wuMin = 3,
  int cdMin = 2,
}) {
  final out = <RowBlock>[_wu(wuMin)];
  for (var i = 0; i < reps; i++) {
    out.add(RowBlock(workSec,
        spm: spm, intensity: intensity, label: '$workLabel ${i + 1}/$reps'));
    if (i < reps - 1) out.add(_rest(restSec));
  }
  out.add(_cd(cdMin));
  return out;
}

// --- the catalogue -------------------------------------------------

/// ~40 named rowing workouts across the session types. Compiled from common
/// indoor-rowing training practice (Concept2 / Pete Plan / British Rowing).
final List<RowWorkout> rowWorkouts = [
  // ===== Endurance =====
  RowWorkout(
    id: 'end_20',
    name: '20 min rustig',
    type: RowSessionType.endurance,
    focus: 'Aerobe basis op een lage slag.',
    approxMinutes: 20,
    blocks: (l, b) => [
      _wu(2),
      RowBlock((14 + b * 4).round() * 60,
          spm: 19 + _lvl(l), intensity: RowIntensity.steady, label: 'Endurance'),
      _cd(2),
    ],
  ),
  RowWorkout(
    id: 'end_30',
    name: '30 min duurstuk',
    type: RowSessionType.endurance,
    focus: 'Lang aaneengesloten op gespreksniveau.',
    approxMinutes: 30,
    blocks: (l, b) => [
      _wu(3),
      RowBlock((22 + b * 6).round() * 60,
          spm: 20 + _lvl(l), intensity: RowIntensity.steady, label: 'Endurance'),
      _cd(2),
    ],
  ),
  RowWorkout(
    id: 'end_40',
    name: '40 min duurstuk',
    type: RowSessionType.endurance,
    focus: 'Volumesessie, rustig en gelijkmatig.',
    approxMinutes: 40,
    blocks: (l, b) => [
      _wu(3),
      RowBlock((32 + b * 6).round() * 60,
          spm: 20 + _lvl(l), intensity: RowIntensity.steady, label: 'Endurance'),
      _cd(3),
    ],
  ),
  RowWorkout(
    id: 'end_50',
    name: '50 min lang',
    type: RowSessionType.endurance,
    focus: 'Grote volumesessie voor de wekelijkse "long row".',
    approxMinutes: 52,
    blocks: (l, b) => [
      _wu(4),
      RowBlock((40 + b * 8).round() * 60,
          spm: 19 + _lvl(l), intensity: RowIntensity.steady, label: 'Endurance'),
      _cd(4),
    ],
  ),
  RowWorkout(
    id: 'end_3x10',
    name: '3 × 10 min r20',
    type: RowSessionType.endurance,
    focus: 'Duurblokken met een korte losroei-pauze.',
    approxMinutes: 38,
    blocks: (l, b) => [
      _wu(3),
      for (var i = 0; i < 3; i++) ...[
        RowBlock((9 + b).round() * 60,
            spm: 20 + _lvl(l),
            intensity: RowIntensity.steady,
            label: 'Endurance ${i + 1}/3'),
        if (i < 2) _rest(90),
      ],
      _cd(3),
    ],
  ),
  RowWorkout(
    id: 'end_2x20',
    name: '2 × 20 min r20',
    type: RowSessionType.endurance,
    focus: 'Klassiek volumeblok, twee lange stukken.',
    approxMinutes: 48,
    blocks: (l, b) => [
      _wu(3),
      RowBlock((18 + b * 3).round() * 60,
          spm: 20 + _lvl(l),
          intensity: RowIntensity.steady,
          label: 'Endurance 1/2'),
      _rest(180),
      RowBlock((18 + b * 3).round() * 60,
          spm: 20 + _lvl(l),
          intensity: RowIntensity.steady,
          label: 'Endurance 2/2'),
      _cd(3),
    ],
  ),
  RowWorkout(
    id: 'end_progressive',
    name: 'Progressief 30 min',
    type: RowSessionType.endurance,
    focus: 'Elke 10 min iets sneller: r18 → r20 → r22.',
    approxMinutes: 34,
    blocks: (l, b) => [
      _wu(3),
      RowBlock(600,
          spm: 18 + _lvl(l), intensity: RowIntensity.steady, label: 'r18'),
      RowBlock(600,
          spm: 20 + _lvl(l), intensity: RowIntensity.steady, label: 'r20'),
      RowBlock((8 + b * 2).round() * 60,
          spm: 22 + _lvl(l),
          intensity: RowIntensity.threshold,
          label: 'r22'),
      _cd(3),
    ],
  ),
  RowWorkout(
    id: 'end_5k',
    name: '5.000 m gelijkmatig',
    type: RowSessionType.endurance,
    focus: 'Vaste afstand op duurtempo.',
    approxMinutes: 24,
    blocks: (l, b) => [
      _wu(3),
      RowBlock(1140,
          spm: 20 + _lvl(l),
          intensity: RowIntensity.steady,
          label: '5.000 m'),
      _cd(2),
    ],
  ),

  // ===== Herstel =====
  RowWorkout(
    id: 'rec_15',
    name: 'Herstel 15 min',
    type: RowSessionType.herstel,
    focus: 'Heel licht, lange uithaal, ontspannen.',
    approxMinutes: 15,
    blocks: (l, b) => [
      RowBlock(120, spm: 16, intensity: RowIntensity.easy, label: 'Warming-up'),
      RowBlock(660, spm: 17, intensity: RowIntensity.easy, label: 'Rustig'),
    ],
  ),
  RowWorkout(
    id: 'rec_20',
    name: 'Herstel 20 min',
    type: RowSessionType.herstel,
    focus: 'Actief herstel op zeer lage slag.',
    approxMinutes: 20,
    blocks: (l, b) => [
      RowBlock(120, spm: 16, intensity: RowIntensity.easy, label: 'Warming-up'),
      RowBlock(1020, spm: 17, intensity: RowIntensity.easy, label: 'Rustig'),
    ],
  ),

  // ===== Drempel =====
  RowWorkout(
    id: 'thr_3x6',
    name: '3 × 6 min / 2 min',
    type: RowSessionType.drempel,
    focus: 'Comfortabel-hard, net onder wedstrijdtempo.',
    approxMinutes: 33,
    blocks: (l, b) => _reps(3,
        workSec: ((5 + b) * 60).round(),
        restSec: 120,
        spm: 24 + _lvl(l),
        intensity: RowIntensity.threshold,
        workLabel: 'Drempel'),
  ),
  RowWorkout(
    id: 'thr_4x5',
    name: '4 × 5 min / 90 s',
    type: RowSessionType.drempel,
    focus: 'Vier stevige blokken met korte rust.',
    approxMinutes: 33,
    blocks: (l, b) => _reps(4,
        workSec: ((4 + b) * 60).round(),
        restSec: 90,
        spm: 25 + _lvl(l),
        intensity: RowIntensity.threshold,
        workLabel: 'Drempel'),
  ),
  RowWorkout(
    id: 'thr_2x15',
    name: '2 × 15 min / 3 min',
    type: RowSessionType.drempel,
    focus: 'Lange drempelblokken — mentaal taai.',
    approxMinutes: 40,
    blocks: (l, b) => [
      _wu(3),
      RowBlock((13 + b * 3).round() * 60,
          spm: 24 + _lvl(l),
          intensity: RowIntensity.threshold,
          label: 'Drempel 1/2'),
      _rest(180),
      RowBlock((13 + b * 3).round() * 60,
          spm: 24 + _lvl(l),
          intensity: RowIntensity.threshold,
          label: 'Drempel 2/2'),
      _cd(3),
    ],
  ),
  RowWorkout(
    id: 'thr_4x2000',
    name: '4 × 2.000 m / 3:30',
    type: RowSessionType.drempel,
    focus: 'Afstandsblokken rond 2k-tempo + 8 sec.',
    approxMinutes: 44,
    blocks: (l, b) => _reps(4,
        workSec: 480 - _lvl(l) * 20,
        restSec: 210,
        spm: 26 + _lvl(l),
        intensity: RowIntensity.threshold,
        workLabel: '2.000 m'),
  ),
  RowWorkout(
    id: 'thr_3x3000',
    name: '3 × 3.000 m / 5 min',
    type: RowSessionType.drempel,
    focus: 'Lange afstandsblokken, gelijkmatig hard.',
    approxMinutes: 48,
    blocks: (l, b) => _reps(3,
        workSec: 720 - _lvl(l) * 30,
        restSec: 300,
        spm: 24 + _lvl(l),
        intensity: RowIntensity.threshold,
        workLabel: '3.000 m'),
  ),
  RowWorkout(
    id: 'thr_5x4',
    name: '5 × 4 min / 2 min',
    type: RowSessionType.drempel,
    focus: 'Vijf blokken, opbouwend in gevoel.',
    approxMinutes: 35,
    blocks: (l, b) => _reps(5,
        workSec: 240,
        restSec: 120,
        spm: 25 + _lvl(l),
        intensity: RowIntensity.threshold,
        workLabel: 'Drempel'),
  ),

  // ===== Korte intervallen =====
  RowWorkout(
    id: 'sh_8x250',
    name: '8 × 250 m / 1:30',
    type: RowSessionType.intervalKort,
    focus: 'Korte, scherpe stukjes met veel rust.',
    approxMinutes: 26,
    blocks: (l, b) => _reps(8,
        workSec: 55 - _lvl(l) * 3,
        restSec: 90,
        spm: 28 + _lvl(l),
        intensity: RowIntensity.hard,
        workLabel: '250 m'),
  ),
  RowWorkout(
    id: 'sh_10x1',
    name: '10 × 1 min / 1 min',
    type: RowSessionType.intervalKort,
    focus: 'Klassieke minuutjes, 1:1 werk-rust.',
    approxMinutes: 26,
    blocks: (l, b) => _reps((8 + b * 2).round(),
        workSec: 60,
        restSec: 60,
        spm: 28 + _lvl(l),
        intensity: RowIntensity.hard,
        workLabel: 'Hard'),
  ),
  RowWorkout(
    id: 'sh_6x2',
    name: '6 × 2 min / 2 min',
    type: RowSessionType.intervalKort,
    focus: 'Iets langer, blijf net beheerst.',
    approxMinutes: 28,
    blocks: (l, b) => _reps((5 + b).round(),
        workSec: 120,
        restSec: 120,
        spm: 27 + _lvl(l),
        intensity: RowIntensity.hard,
        workLabel: 'Hard'),
  ),
  RowWorkout(
    id: 'sh_12x40',
    name: '12 × 40 s / 20 s',
    type: RowSessionType.intervalKort,
    focus: 'Korte werk, korte rust — scherp blijven.',
    approxMinutes: 20,
    blocks: (l, b) => _reps((10 + b * 2).round(),
        workSec: 40,
        restSec: 20,
        spm: 29 + _lvl(l),
        intensity: RowIntensity.hard,
        workLabel: 'Hard'),
  ),
  RowWorkout(
    id: 'sh_20x30',
    name: '20 × 30 s / 30 s',
    type: RowSessionType.intervalKort,
    focus: 'Veel herhalingen, hoog ritme.',
    approxMinutes: 26,
    blocks: (l, b) => _reps((16 + b * 4).round(),
        workSec: 30,
        restSec: 30,
        spm: 30 + _lvl(l),
        intensity: RowIntensity.hard,
        workLabel: 'Hard'),
  ),
  RowWorkout(
    id: 'sh_8x500',
    name: '8 × 500 m / 2 min',
    type: RowSessionType.intervalKort,
    focus: 'Pete Plan-klassieker rond 5k-tempo.',
    approxMinutes: 32,
    blocks: (l, b) => _reps((6 + b * 2).round(),
        workSec: 110 - _lvl(l) * 5,
        restSec: 120,
        spm: 28 + _lvl(l),
        intensity: RowIntensity.hard,
        workLabel: '500 m'),
  ),
  RowWorkout(
    id: 'sh_4x1000',
    name: '4 × 1.000 m / 3 min',
    type: RowSessionType.intervalKort,
    focus: 'Wedstrijdgericht rond 2k + 4 sec.',
    approxMinutes: 30,
    blocks: (l, b) => _reps(4,
        workSec: 235 - _lvl(l) * 10,
        restSec: 180,
        spm: 28 + _lvl(l),
        intensity: RowIntensity.hard,
        workLabel: '1.000 m'),
  ),

  // ===== Lange intervallen =====
  RowWorkout(
    id: 'lo_4x4',
    name: '4 × 4 min / 2 min',
    type: RowSessionType.intervalLang,
    focus: 'VO2-blokken, hard maar herhaalbaar.',
    approxMinutes: 34,
    blocks: (l, b) => _reps(4,
        workSec: (200 + b * 40).round(),
        restSec: 120,
        spm: 26 + _lvl(l),
        intensity: RowIntensity.hard,
        workLabel: 'Interval'),
  ),
  RowWorkout(
    id: 'lo_5x3',
    name: '5 × 3 min / 90 s',
    type: RowSessionType.intervalLang,
    focus: 'Vijf pittige blokken met korte rust.',
    approxMinutes: 32,
    blocks: (l, b) => _reps(5,
        workSec: 180,
        restSec: 90,
        spm: 27 + _lvl(l),
        intensity: RowIntensity.hard,
        workLabel: 'Interval'),
  ),
  RowWorkout(
    id: 'lo_3x6',
    name: '3 × 6 min / 3 min',
    type: RowSessionType.intervalLang,
    focus: 'Lange harde stukken, tempo-uithouding.',
    approxMinutes: 34,
    blocks: (l, b) => _reps(3,
        workSec: (330 + b * 30).round(),
        restSec: 180,
        spm: 26 + _lvl(l),
        intensity: RowIntensity.hard,
        workLabel: 'Interval'),
  ),
  RowWorkout(
    id: 'lo_6x2_r28',
    name: '6 × 2 min r28 / 2 min',
    type: RowSessionType.intervalLang,
    focus: 'Hoger ritme aanhouden per blok.',
    approxMinutes: 30,
    blocks: (l, b) => _reps(6,
        workSec: 120,
        restSec: 120,
        spm: 28 + _lvl(l),
        intensity: RowIntensity.hard,
        workLabel: 'r28'),
  ),

  // ===== Piramide =====
  RowWorkout(
    id: 'pyr_12321_min',
    name: 'Piramide 1-2-3-2-1 min',
    type: RowSessionType.piramide,
    focus: 'Oplopend en aflopend, 1 min rust ertussen.',
    approxMinutes: 24,
    blocks: (l, b) {
      final steps = [60, 120, 180, 120, 60];
      final names = ['Opbouw', 'Middel', 'Piek', 'Middel', 'Afbouw'];
      final spm = [23, 25, 27, 25, 23];
      final out = <RowBlock>[_wu(3)];
      for (var i = 0; i < steps.length; i++) {
        out.add(RowBlock((steps[i] * (0.85 + b * 0.3)).round(),
            spm: spm[i] + _lvl(l),
            intensity: i == 2 ? RowIntensity.hard : RowIntensity.threshold,
            label: names[i]));
        if (i < steps.length - 1) out.add(_rest(60));
      }
      out.add(_cd(2));
      return out;
    },
  ),
  RowWorkout(
    id: 'pyr_dist',
    name: 'Piramide 250-500-750-500-250 m',
    type: RowSessionType.piramide,
    focus: 'Afstandsladder met evenveel rust als werk.',
    approxMinutes: 26,
    blocks: (l, b) {
      final secs = [55, 110, 165, 110, 55];
      final out = <RowBlock>[_wu(3)];
      for (var i = 0; i < secs.length; i++) {
        out.add(RowBlock(secs[i] - _lvl(l) * 3,
            spm: 27 + _lvl(l),
            intensity: RowIntensity.hard,
            label: '${[250, 500, 750, 500, 250][i]} m'));
        if (i < secs.length - 1) out.add(_rest(secs[i]));
      }
      out.add(_cd(2));
      return out;
    },
  ),
  RowWorkout(
    id: 'pyr_24642',
    name: 'Piramide 2-4-6-4-2 min',
    type: RowSessionType.piramide,
    focus: 'Grote piramide, drempel-intensiteit.',
    approxMinutes: 34,
    blocks: (l, b) {
      final steps = [120, 240, 360, 240, 120];
      final out = <RowBlock>[_wu(3)];
      for (var i = 0; i < steps.length; i++) {
        out.add(RowBlock(steps[i],
            spm: 24 + _lvl(l) + (i == 2 ? 2 : 0),
            intensity: i == 2 ? RowIntensity.hard : RowIntensity.threshold,
            label: '${[2, 4, 6, 4, 2][i]} min'));
        if (i < steps.length - 1) out.add(_rest(90));
      }
      out.add(_cd(3));
      return out;
    },
  ),
  RowWorkout(
    id: 'pyr_rate',
    name: 'Slagladder r20-22-24-26-24-22-20',
    type: RowSessionType.piramide,
    focus: 'Elke 3 min de slag omhoog en weer terug.',
    approxMinutes: 27,
    blocks: (l, b) {
      final rates = [20, 22, 24, 26, 24, 22, 20];
      final out = <RowBlock>[_wu(2)];
      for (final r in rates) {
        out.add(RowBlock(180,
            spm: r + _lvl(l),
            intensity: r >= 26 ? RowIntensity.hard : RowIntensity.threshold,
            label: 'r$r'));
      }
      out.add(_cd(2));
      return out;
    },
  ),

  // ===== Krachthalen =====
  RowWorkout(
    id: 'pw_10x10',
    name: '10 × 10 halen r20 / 40 s',
    type: RowSessionType.krachtStroken,
    focus: 'Maximale druk per haal, lage slag.',
    approxMinutes: 20,
    blocks: (l, b) => _reps((8 + b * 2).round(),
        workSec: 25,
        restSec: 40,
        spm: 19 + _lvl(l),
        intensity: RowIntensity.hard,
        workLabel: 'Krachthaal'),
  ),
  RowWorkout(
    id: 'pw_8x20',
    name: '8 × 20 halen r18 / 1 min',
    type: RowSessionType.krachtStroken,
    focus: 'Langere krachtblokjes, focus op de beendruk.',
    approxMinutes: 22,
    blocks: (l, b) {
      final out = _reps((6 + b * 2).round(),
          workSec: 45,
          restSec: 60,
          spm: 18 + _lvl(l),
          intensity: RowIntensity.hard,
          workLabel: 'Krachthaal');
      return out
          .map((x) => x.label.startsWith('Krachthaal')
              ? RowBlock(x.seconds,
                  spm: x.spm,
                  intensity: x.intensity,
                  label: x.label,
                  drillKey: RowDrill.krachtHaal.key)
              : x)
          .toList();
    },
  ),
  RowWorkout(
    id: 'pw_4x15_45',
    name: '4 × (15 hard / 45 rustig)',
    type: RowSessionType.krachtStroken,
    focus: 'Explosief starten, dan uitrijden.',
    approxMinutes: 18,
    blocks: (l, b) {
      final out = <RowBlock>[_wu(3)];
      final n = (4 + b * 2).round();
      for (var i = 0; i < n; i++) {
        out.add(RowBlock(15,
            spm: 30 + _lvl(l),
            intensity: RowIntensity.max,
            label: 'Hard ${i + 1}/$n'));
        out.add(RowBlock(45,
            spm: 18, intensity: RowIntensity.easy, label: 'Uitrijden'));
      }
      out.add(_cd(2));
      return out;
    },
  ),
  RowWorkout(
    id: 'pw_6x250',
    name: '6 × 250 m kracht r22 / 2 min',
    type: RowSessionType.krachtStroken,
    focus: 'Zware halen op een lage slag, veel rust.',
    approxMinutes: 24,
    blocks: (l, b) => _reps(6,
        workSec: 60,
        restSec: 120,
        spm: 21 + _lvl(l),
        intensity: RowIntensity.hard,
        workLabel: '250 m kracht'),
  ),

  // ===== Sprint (onder krachtStroken-type voor de mix) =====
  RowWorkout(
    id: 'sp_8x100',
    name: '8 × 100 m / 1 min',
    type: RowSessionType.intervalKort,
    focus: 'Volle sprints, volledig herstel.',
    approxMinutes: 18,
    blocks: (l, b) => _reps(8,
        workSec: 22 - _lvl(l),
        restSec: 60,
        spm: 32 + _lvl(l),
        intensity: RowIntensity.max,
        workLabel: 'Sprint'),
  ),
  RowWorkout(
    id: 'sp_500tt',
    name: '500 m tijdrit',
    type: RowSessionType.intervalKort,
    focus: 'Alles-eruit test met lange warming-up.',
    approxMinutes: 18,
    blocks: (l, b) => [
      _wu(6),
      RowBlock(95 - _lvl(l) * 5,
          spm: 34 + _lvl(l), intensity: RowIntensity.max, label: '500 m TT'),
      _cd(4),
    ],
  ),
  RowWorkout(
    id: 'sp_4x250',
    name: '4 × 250 m / 3 min',
    type: RowSessionType.intervalKort,
    focus: 'Sprintafstanden met bijna volledig herstel.',
    approxMinutes: 20,
    blocks: (l, b) => _reps(4,
        workSec: 48 - _lvl(l) * 3,
        restSec: 180,
        spm: 32 + _lvl(l),
        intensity: RowIntensity.max,
        workLabel: '250 m'),
  ),
  RowWorkout(
    id: 'sp_6x10',
    name: '6 × (10 s max / 50 s)',
    type: RowSessionType.krachtStroken,
    focus: 'Neuraal: korte all-out pieken.',
    approxMinutes: 16,
    blocks: (l, b) {
      final out = <RowBlock>[_wu(4)];
      for (var i = 0; i < 6; i++) {
        out.add(RowBlock(10,
            spm: 36, intensity: RowIntensity.max, label: 'Max ${i + 1}/6'));
        out.add(RowBlock(50,
            spm: 16, intensity: RowIntensity.easy, label: 'Rustig'));
      }
      out.add(_cd(3));
      return out;
    },
  ),

  // ===== Techniek (drills) =====
  RowWorkout(
    id: 'tech_basis',
    name: 'Techniek — basisdrills',
    type: RowSessionType.techniek,
    focus: 'Alleen benen → armen → hele haal, met pauzes.',
    approxMinutes: 22,
    blocks: (l, b) => [
      RowBlock(120, spm: 16, intensity: RowIntensity.easy, label: 'Warming-up'),
      for (final d in const [
        RowDrill.benenOnly,
        RowDrill.armenOnly,
        RowDrill.armenRomp,
        RowDrill.pauzeHaal,
        RowDrill.opbouwHaal,
      ])
        RowBlock((120 + b * 30).round(),
            spm: 18,
            intensity: RowIntensity.steady,
            label: 'Techniek — ${d.label}',
            drillKey: d.key),
      RowBlock(240,
          spm: 20 + _lvl(l),
          intensity: RowIntensity.steady,
          label: 'Endurance'),
      _cd(2),
    ],
  ),
  RowWorkout(
    id: 'tech_ratio',
    name: 'Techniek — ratio & controle',
    type: RowSessionType.techniek,
    focus: 'Omgekeerde ratio en pauzehalen op lage slag.',
    approxMinutes: 20,
    blocks: (l, b) => [
      RowBlock(120, spm: 16, intensity: RowIntensity.easy, label: 'Warming-up'),
      for (final d in const [
        RowDrill.omgekeerdeRatio,
        RowDrill.pauzeHaal,
        RowDrill.opbouwHaal,
        RowDrill.omgekeerdeRatio,
      ])
        RowBlock((150 + b * 30).round(),
            spm: 18,
            intensity: RowIntensity.steady,
            label: 'Techniek — ${d.label}',
            drillKey: d.key),
      RowBlock(180,
          spm: 20 + _lvl(l),
          intensity: RowIntensity.steady,
          label: 'Endurance'),
      _cd(2),
    ],
  ),
  RowWorkout(
    id: 'tech_legs',
    name: 'Techniek — beendruk',
    type: RowSessionType.techniek,
    focus: 'Focus op de aanzet vanuit de benen.',
    approxMinutes: 22,
    blocks: (l, b) => [
      RowBlock(120, spm: 16, intensity: RowIntensity.easy, label: 'Warming-up'),
      for (final d in const [
        RowDrill.benenOnly,
        RowDrill.opbouwHaal,
        RowDrill.krachtHaal,
        RowDrill.benenOnly,
      ])
        RowBlock((150 + b * 30).round(),
            spm: d == RowDrill.krachtHaal ? 19 : 18,
            intensity: d == RowDrill.krachtHaal
                ? RowIntensity.threshold
                : RowIntensity.steady,
            label: 'Techniek — ${d.label}',
            drillKey: d.key),
      RowBlock(240,
          spm: 20 + _lvl(l),
          intensity: RowIntensity.steady,
          label: 'Endurance'),
      _cd(2),
    ],
  ),
];

Iterable<RowWorkout> workoutsOfType(RowSessionType type) =>
    rowWorkouts.where((w) => w.type == type);

RowWorkout? workoutById(String id) {
  for (final w in rowWorkouts) {
    if (w.id == id) return w;
  }
  return null;
}
