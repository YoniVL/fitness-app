// App-level smoke test. Feature logic is covered by the other test files
// (schema_test, workout_session_repository_test, active_workout_test,
// rest_timer_test).

import 'package:fitnesstracker/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('muscleGroupIcon always resolves to an icon', () {
    for (final key in ['chest', 'back', 'legs', 'core', 'unknown-key', '']) {
      expect(muscleGroupIcon(key), isA<IconData>());
    }
  });

  testWidgets('themes build for light and dark', (tester) async {
    expect(AppTheme.light().useMaterial3, isTrue);
    expect(AppTheme.dark().colorScheme.brightness, Brightness.dark);
  });
}
