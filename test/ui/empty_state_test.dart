import 'package:fitnesstracker/ui/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the message, an optional icon and action', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EmptyState(
          'Nog geen sessies',
          icon: Icons.rowing,
          action: TextButton(onPressed: () {}, child: const Text('Plan starten')),
        ),
      ),
    ));

    expect(find.text('Nog geen sessies'), findsOneWidget);
    expect(find.byIcon(Icons.rowing), findsOneWidget);
    expect(find.text('Plan starten'), findsOneWidget);
  });

  testWidgets('works without an icon or action', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: EmptyState('Niets hier')),
    ));

    expect(find.text('Niets hier'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
