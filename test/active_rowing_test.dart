import 'package:fitnesstracker/domain/models/program.dart';
import 'package:fitnesstracker/domain/models/workout_session.dart';
import 'package:fitnesstracker/features/rowing/state/active_rowing_provider.dart';
import 'package:flutter_test/flutter_test.dart';

ProgramRowSegment _seg(int order, int seconds, {bool rest = false}) =>
    ProgramRowSegment(
      id: order,
      programDayId: 1,
      orderIndex: order,
      durationSeconds: seconds,
      intensityLabel: rest ? 'Rust' : 'Blok',
      isRest: rest,
    );

ActiveRowingState _state(List<ProgramRowSegment> segs,
        {int index = 0, Duration segElapsed = Duration.zero}) =>
    ActiveRowingState(
      session: WorkoutSession(
        id: 1,
        discipline: Discipline.rowing,
        startedAt: DateTime(2026, 9, 3, 8),
      ),
      rowingSessionId: 1,
      segments: segs,
      segmentIndex: index,
      segmentElapsed: segElapsed,
    );

void main() {
  test('free row has no segments and no current segment', () {
    final s = _state(const []);
    expect(s.isFreeRow, isTrue);
    expect(s.currentSegment, isNull);
    expect(s.segmentRemaining, isNull);
  });

  test('segmentRemaining counts down and clamps at zero', () {
    final segs = [_seg(0, 60), _seg(1, 30)];
    expect(_state(segs, segElapsed: const Duration(seconds: 20)).segmentRemaining,
        const Duration(seconds: 40));
    expect(_state(segs, segElapsed: const Duration(seconds: 90)).segmentRemaining,
        Duration.zero);
  });

  test('onLastSegment', () {
    final segs = [_seg(0, 60), _seg(1, 30), _seg(2, 60)];
    expect(_state(segs, index: 1).onLastSegment, isFalse);
    expect(_state(segs, index: 2).onLastSegment, isTrue);
  });

  test('plannedTotalSeconds sums every segment', () {
    final segs = [_seg(0, 60), _seg(1, 30, rest: true), _seg(2, 60)];
    expect(_state(segs).plannedTotalSeconds, 150);
  });

  test('copyWith keeps identity fields', () {
    final s = _state([_seg(0, 60)]);
    final n = s.copyWith(segmentIndex: 5, pausedReason: PauseReason.user);
    expect(n.session.id, s.session.id);
    expect(n.rowingSessionId, s.rowingSessionId);
    expect(n.segmentIndex, 5);
    expect(n.paused, isTrue);
  });

  test('paused reflects the pause reason', () {
    final s = _state([_seg(0, 60)]);
    expect(s.paused, isFalse);
    expect(s.copyWith(pausedReason: PauseReason.idle).paused, isTrue);
    expect(s.copyWith(pausedReason: PauseReason.background).paused, isTrue);
    expect(s.copyWith(pausedReason: PauseReason.none).paused, isFalse);
  });

  group('RowingMeter', () {
    test('integrates distance from the split', () {
      final m = RowingMeter();
      // 2:00 /500m = 120 s → 4.166 m/s.
      m.tick(seconds: 1, paceSec500m: 120);
      m.tick(seconds: 1, paceSec500m: 120);
      expect(m.distanceM, closeTo(8.33, 0.01));
    });

    test('adds nothing without a plausible split', () {
      final m = RowingMeter();
      m.tick(seconds: 1); // no pace → not rowing
      m.tick(seconds: 1, paceSec500m: 0);
      m.tick(seconds: 1, paceSec500m: 5000); // absurdly slow → ignored
      expect(m.distanceM, 0);
    });

    test('integrates energy from power', () {
      final m = RowingMeter();
      m.tick(seconds: 10, powerW: 200);
      expect(m.energyKcal, greaterThan(0));
      final after = m.energyKcal;
      m.tick(seconds: 5, powerW: 0);
      expect(m.energyKcal, after); // no power → no energy
    });

    test('seed carries a rehydrated session forward', () {
      final m = RowingMeter()..seed(distanceM: 1500, energyKcal: 40);
      m.tick(seconds: 1, paceSec500m: 120);
      expect(m.distanceM, closeTo(1504.17, 0.01));
      expect(m.energyKcal, 40);
    });
  });

  test('a session starts in the not-started state and the clock is frozen', () {
    final s = _state([_seg(0, 60)]).copyWith(pausedReason: PauseReason.notStarted);
    expect(s.paused, isTrue);
    expect(s.elapsed, Duration.zero);
  });

  test('segmentProgressFraction tracks the segment cursor', () {
    final segs = [_seg(0, 100), _seg(1, 100), _seg(2, 200)];
    // Start of segment 1 = 100/400.
    expect(_state(segs, index: 1).segmentProgressFraction, 0.25);
    // 50 s into segment 1 = 150/400.
    expect(
        _state(segs, index: 1, segElapsed: const Duration(seconds: 50))
            .segmentProgressFraction,
        0.375);
  });
}
