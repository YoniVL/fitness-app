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
