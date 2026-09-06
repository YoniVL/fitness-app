import 'package:fitnesstracker/ui/stat_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders label and value', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: StatTile(label: 'Afstand', value: '8,2 km'),
      ),
    ));

    expect(find.text('AFSTAND'), findsOneWidget);
    expect(find.text('8,2 km'), findsOneWidget);
  });

  testWidgets('label above the value when requested', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: StatTile(
          label: 'Tempo',
          value: '2:03',
          size: StatSize.big,
          labelPosition: StatLabelPosition.above,
        ),
      ),
    ));

    final labelY = tester.getTopLeft(find.text('TEMPO')).dy;
    final valueY = tester.getTopLeft(find.text('2:03')).dy;
    expect(labelY, lessThan(valueY));
  });

  testWidgets('renders a badge and a sub-caption', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: StatTile(
          label: 'JIJ',
          value: '149 W',
          size: StatSize.hero,
          badge: 'op tempo',
          sub: '2:05 /500m',
        ),
      ),
    ));

    expect(find.text('OP TEMPO'), findsOneWidget);
    expect(find.text('2:05 /500m'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
