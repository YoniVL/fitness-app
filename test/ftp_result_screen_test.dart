import 'package:fitnesstracker/data/repositories/settings_repository.dart';
import 'package:fitnesstracker/data/repositories/rowing_repository.dart';
import 'package:fitnesstracker/domain/models/program.dart';
import 'package:fitnesstracker/domain/models/rowing.dart';
import 'package:fitnesstracker/domain/models/workout_session.dart';
import 'package:fitnesstracker/domain/rowing_ftp.dart';
import 'package:fitnesstracker/features/rowing/ftp_result_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the computed FTP for a guided 20-min test', (tester) async {
    final segs = ftpTestSegments(FtpProtocol.test20, ProgramLevel.medium);
    final total = segs.fold(0, (a, s) => a + s.durationSeconds);
    final window = FtpProtocol.test20.effortWindow(segs)!;
    final detail = RowingSessionDetail(
      session: WorkoutSession(
          id: 7, discipline: Discipline.rowing, startedAt: DateTime(2026, 9, 4)),
      rowing: RowingSession(
        id: 1,
        sessionId: 7,
        totalDistanceM: 5000,
        totalEnergyKcal: 300,
        avgStrokeRate: 26,
        avgPower: 220,
        durationSeconds: total,
        kind: 'ftp_20min',
      ),
      planSegments: segs,
      samples: [
        for (var t = window.startSec * 1000;
            t <= window.endSec * 1000;
            t += 3000)
          RowingSample(
              id: 0, rowingSessionId: 1, tOffsetMs: t, powerW: 220, paceSec500m: 120),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rowingSessionDetailProvider(7)
              .overrideWith((ref) async => detail),
          rowingDragKProvider.overrideWith((ref) async => kGeneric),
        ],
        child: const MaterialApp(home: FtpResultScreen(sessionId: 7)),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('209 W'), findsOneWidget); // 220 * 0.95
    expect(find.text('OPSLAAN ALS MIJN FTP'), findsOneWidget);
    expect(find.text('20-minutentest'), findsOneWidget);
  });
}
