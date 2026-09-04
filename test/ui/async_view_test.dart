import 'package:fitnesstracker/ui/async_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget harness(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('data renders the builder', (tester) async {
    const value = AsyncData<int>(7);
    await tester.pumpWidget(harness(value.view((d) => Text('n=$d'))));
    expect(find.text('n=7'), findsOneWidget);
  });

  testWidgets('loading shows the default LoadingBox', (tester) async {
    const value = AsyncLoading<int>();
    await tester.pumpWidget(harness(value.view((d) => Text('n=$d'))));
    expect(find.byType(LoadingBox), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('error shows the default ErrorBox', (tester) async {
    final value = AsyncError<int>('boom', StackTrace.empty);
    await tester.pumpWidget(harness(value.view((d) => Text('n=$d'))));
    expect(find.byType(ErrorBox), findsOneWidget);
  });

  testWidgets('viewOrNothing renders nothing while loading', (tester) async {
    const value = AsyncLoading<int>();
    await tester.pumpWidget(harness(value.viewOrNothing((d) => Text('n=$d'))));
    expect(find.byType(Text), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
