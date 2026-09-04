import 'package:fitnesstracker/domain/rowing_achievements.dart';
import 'package:fitnesstracker/features/rowing/rowing_achievements_screen.dart';
import 'package:fitnesstracker/features/rowing/state/rowing_achievements_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

class _FakeNotifier extends RowingAchievementsNotifier {
  _FakeNotifier(this._view);
  final AchievementsView _view;
  @override
  Future<AchievementsView> build() async => _view;
}

Future<void> _pump(WidgetTester tester, AchievementsView view) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        rowingAchievementsProvider.overrideWith(() => _FakeNotifier(view)),
      ],
      child: const MaterialApp(home: RowingAchievementsScreen()),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  setUpAll(() => initializeDateFormatting('nl'));

  testWidgets('fresh tracker: nothing unlocked, first rungs are the goals',
      (tester) async {
    const stats = AchievementStats();
    await _pump(tester, (
      stats: stats,
      earnedIds: earnedAchievements(stats),
      unlockedAt: const <String, DateTime>{},
    ));

    expect(tester.takeException(), isNull);
    expect(find.textContaining('0 van'), findsOneWidget);
    // First ladder card (afstand) shows its first rung as the goal.
    expect(find.text('In totaal 10 km'), findsOneWidget);
  });

  testWidgets('populated: shows a reached rung with its date', (tester) async {
    const stats = AchievementStats(
      totalDistanceM: 63000,
      sessionCount: 12,
    );
    final earned = earnedAchievements(stats);
    await _pump(tester, (
      stats: stats,
      earnedIds: earned,
      unlockedAt: {
        for (final id in earned) id: DateTime(2026, 5, 20),
      },
    ));

    expect(tester.takeException(), isNull);
    // 63 km reached → the 100 km rung is the next goal.
    expect(find.text('In totaal 100 km'), findsOneWidget);
    expect(find.textContaining('behaald'), findsWidgets);
  });
}
