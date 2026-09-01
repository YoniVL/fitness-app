import 'package:fake_async/fake_async.dart';
import 'package:fitnesstracker/features/strength/state/rest_timer_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProviderContainer container;
  late RestTimerNotifier timer;

  setUp(() {
    container = ProviderContainer();
    timer = container.read(restTimerProvider.notifier);
  });
  tearDown(() => container.dispose());

  test('counts down and deactivates at zero', () {
    fakeAsync((async) {
      timer.start(3);
      expect(container.read(restTimerProvider).remainingSeconds, 3);
      expect(container.read(restTimerProvider).active, isTrue);

      async.elapse(const Duration(seconds: 2));
      expect(container.read(restTimerProvider).remainingSeconds, 1);

      async.elapse(const Duration(seconds: 1));
      final state = container.read(restTimerProvider);
      expect(state.active, isFalse);
      expect(state.remainingSeconds, 0);
    });
  });

  test('+30s extends both total and remaining', () {
    fakeAsync((async) {
      timer.start(60);
      async.elapse(const Duration(seconds: 10));
      timer.addSeconds(30);
      final state = container.read(restTimerProvider);
      expect(state.remainingSeconds, 80);
      expect(state.totalSeconds, 90);
    });
  });

  test('skip stops the countdown immediately', () {
    fakeAsync((async) {
      timer.start(120);
      async.elapse(const Duration(seconds: 5));
      timer.skip();
      expect(container.read(restTimerProvider).active, isFalse);

      // No further ticks after skipping.
      async.elapse(const Duration(seconds: 5));
      expect(container.read(restTimerProvider).remainingSeconds, 0);
    });
  });
}
