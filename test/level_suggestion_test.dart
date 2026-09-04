import 'package:fitnesstracker/data/repositories/settings_repository.dart';
import 'package:fitnesstracker/domain/models/program.dart';
import 'package:fitnesstracker/features/rowing/widgets/level_suggestion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester,
    {required double watts, required ProgramLevel level}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        rowingLevelProvider.overrideWith((ref) async => level),
      ],
      child: MaterialApp(
        home: Scaffold(body: LevelSuggestionCard(ftpWatts: watts)),
      ),
    ),
  );
}

void main() {
  testWidgets('suggests a higher level for a strong FTP', (tester) async {
    await _pump(tester, watts: 260, level: ProgramLevel.medium);
    await tester.pump();
    expect(find.textContaining('Gevorderd'), findsOneWidget);
    expect(find.text('Overnemen'), findsOneWidget);
  });

  testWidgets('hidden when the level already matches', (tester) async {
    await _pump(tester, watts: 130, level: ProgramLevel.medium);
    await tester.pump();
    expect(find.text('Overnemen'), findsNothing);
  });
}
