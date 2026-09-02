// App-level smoke tests. Feature logic is covered by the other test files.

import 'package:fitnesstracker/app/router.dart';
import 'package:fitnesstracker/app/theme.dart';
import 'package:fitnesstracker/features/home/discipline_chooser_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('themes build for light and dark', (tester) async {
    expect(AppTheme.light().useMaterial3, isTrue);
    expect(AppTheme.dark().colorScheme.brightness, Brightness.dark);
  });

  test('router starts at the discipline chooser', () {
    expect(appRouter.configuration.findMatch(Uri.parse('/')), isNotNull);
    // The two discipline shells and the chooser are all registered.
    for (final path in const [
      '/strength/today',
      '/strength/library',
      '/strength/log',
      '/rowing/today',
      '/rowing/library',
      '/rowing/log',
      '/rowing/active',
      '/workout/active',
    ]) {
      expect(appRouter.configuration.findMatch(Uri.parse(path)), isNotNull,
          reason: '$path should resolve');
    }
  });

  testWidgets('discipline chooser shows both options', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DisciplineChooserScreen()));
    expect(find.text('Krachttraining'), findsOneWidget);
    expect(find.text('Roeien'), findsOneWidget);
  });
}
