import 'package:fitnesstracker/data/repositories/settings_repository.dart';
import 'package:fitnesstracker/domain/rowing_ftp.dart';
import 'package:fitnesstracker/features/rowing/ftp_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

Future<void> _pump(WidgetTester tester,
    {RowingFtp? ftp, bool hasMeter = true}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        rowingFtpProvider.overrideWith((ref) async => ftp),
        rowingDragKProvider.overrideWith((ref) async => kGeneric),
        rowingHasPowerMeterProvider.overrideWith((ref) async => hasMeter),
        rowingFtpHistoryProvider.overrideWith((ref) async => const <RowingFtp>[]),
      ],
      child: const MaterialApp(home: FtpScreen()),
    ),
  );
}

void main() {
  setUpAll(() => initializeDateFormatting('nl'));

  testWidgets('empty state shows the three ways to set an FTP', (tester) async {
    await _pump(tester);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Nog geen FTP ingesteld'), findsOneWidget);
    expect(find.text('Doe een test'), findsOneWidget);
    expect(find.text('Handmatig invoeren'), findsOneWidget);
    expect(find.text('Overnemen uit logboek'), findsOneWidget);
  });

  testWidgets('shows the stored FTP', (tester) async {
    await _pump(tester,
        ftp: RowingFtp(
            watts: 214, setAt: DateTime(2026, 9, 1), source: FtpSource.test20));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('214 W'), findsOneWidget);
    expect(find.textContaining('20-minutentest'), findsWidgets);
  });

  testWidgets('without a power meter the FTP reads as a stroke rate',
      (tester) async {
    final ftp = RowingFtp(
        watts: 146, setAt: DateTime(2026, 9, 1), source: FtpSource.ramp);
    await _pump(tester, ftp: ftp, hasMeter: false);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('${ftp.spm.round()} SPM'), findsOneWidget);
    expect(find.text('146 W'), findsNothing);
    expect(find.text('Huidige drempel'), findsOneWidget);
  });
}
