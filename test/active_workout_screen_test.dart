import 'package:fitnesstracker/features/strength/active_workout_screen.dart';
import 'package:fitnesstracker/features/strength/state/active_workout_provider.dart';
import 'package:fitnesstracker/domain/models/exercise.dart';
import 'package:fitnesstracker/domain/models/program.dart';
import 'package:fitnesstracker/domain/models/workout_session.dart';
import 'package:fitnesstracker/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake controller so the screen render can be tested without touching sqflite
/// (sqflite_common_ffi does not complete inside the widget-test async zone).
class _FakeActiveWorkout extends ActiveWorkoutController {
  _FakeActiveWorkout(this._initial);
  final ActiveWorkoutState? _initial;

  @override
  Future<ActiveWorkoutState?> build() async => _initial;
}

ExerciseBlock _block(int id, String name) => ExerciseBlock(
      exercise: Exercise(
        id: id,
        name: name,
        primaryMuscleGroupId: 1,
        equipmentTags: const ['dumbbell'],
      ),
      targetSets: 3,
      targetReps: 8,
      restBetweenSets: 30,
      restAfterExercise: 60,
    );

void main() {
  testWidgets('shows one fullscreen exercise page at a time', (tester) async {
    // Reproduce a real phone viewport + the real theme: the bug that collapsed
    // content to zero height (Size.fromHeight -> infinite FilledButton width
    // inside a Row) only shows under realistic width constraints.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final state = ActiveWorkoutState(
      session: WorkoutSession(
        id: 1,
        discipline: Discipline.strength,
        programDayId: 3,
        startedAt: DateTime(2026, 9, 1, 9),
      ),
      blocks: [
        _block(1, 'Bankdrukken'),
        _block(2, 'Dumbbell shoulder press'),
        _block(3, 'Incline bankdruk'),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeWorkoutProvider.overrideWith(() => _FakeActiveWorkout(state)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ActiveWorkoutScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    // The pager opens on the first (current) exercise.
    expect(find.text('Bankdrukken'), findsOneWidget);
    expect(find.text('Oefening 1/3'), findsOneWidget);
    expect(find.byType(PageView), findsOneWidget);
    expect(find.textContaining('set 1/3'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Klaar'), findsOneWidget);

    // Regression guard: the "Klaar" button must actually occupy space.
    final btn = tester.getRect(find.widgetWithText(FilledButton, 'Klaar'));
    expect(btn.height, greaterThan(40));
    expect(btn.width, greaterThan(200));
  });

  testWidgets('shows the empty hint when there are no blocks', (tester) async {
    final state = ActiveWorkoutState(
      session: WorkoutSession(
        id: 1,
        discipline: Discipline.strength,
        startedAt: DateTime(2026, 9, 1, 9),
      ),
      blocks: const [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeWorkoutProvider.overrideWith(() => _FakeActiveWorkout(state)),
        ],
        child: const MaterialApp(home: ActiveWorkoutScreen()),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Nog geen oefeningen'), findsOneWidget);
  });
}
