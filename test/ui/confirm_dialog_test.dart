import 'package:fitnesstracker/ui/confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget harness(void Function(bool) onResult) => MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final ok = await confirmDialog(context,
                    title: 'Sessie verwijderen?',
                    message: 'Dit kan niet ongedaan worden gemaakt.',
                    confirmLabel: 'Verwijderen',
                    destructive: true);
                onResult(ok);
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

  testWidgets('cancel returns false', (tester) async {
    bool? result;
    await tester.pumpWidget(harness((r) => result = r));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Sessie verwijderen?'), findsOneWidget);
    await tester.tap(find.text('Annuleren'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });

  testWidgets('confirm returns true', (tester) async {
    bool? result;
    await tester.pumpWidget(harness((r) => result = r));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Verwijderen'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });
}
