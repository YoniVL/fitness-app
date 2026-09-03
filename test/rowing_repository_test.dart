import 'package:fitnesstracker/data/database/app_database.dart';
import 'package:fitnesstracker/data/repositories/program_repository.dart';
import 'package:fitnesstracker/data/repositories/rowing_repository.dart';
import 'package:fitnesstracker/data/repositories/settings_repository.dart';
import 'package:fitnesstracker/data/repositories/workout_session_repository.dart';
import 'package:fitnesstracker/domain/models/program.dart';
import 'package:fitnesstracker/domain/models/rowing.dart';
import 'package:fitnesstracker/domain/models/rowing_plan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  late RowingRepository rowing;
  late WorkoutSessionRepository sessions;

  setUp(() async {
    await initTestDatabase();
    rowing = RowingRepository(AppDatabase.instance);
    sessions = WorkoutSessionRepository(AppDatabase.instance);
  });
  tearDown(closeTestDatabase);

  test('manual session shows up in the log with a rowing summary', () async {
    await rowing.logManualSession(
      distanceM: 3200,
      duration: const Duration(minutes: 14, seconds: 30),
      avgStrokeRate: 24,
      notes: 'rustig',
    );

    final recent = await sessions.recentSessions();
    expect(recent, hasLength(1));
    final s = recent.first;
    expect(s.session.discipline, Discipline.rowing);
    expect(s.session.isFinished, isTrue);
    expect(s.rowing, isNotNull);
    expect(s.rowing!.distanceM, 3200);
    expect(s.rowing!.durationSeconds, 870);
    expect(s.rowing!.avgPaceSec500, closeTo(870 / 3200 * 500, 0.01));
  });

  test('start -> samples -> finalize -> detail', () async {
    final ids = await rowing.startSession();
    expect(await sessions.activeSession(discipline: Discipline.rowing),
        isNotNull);

    await rowing.addSamples(ids.rowingSessionId, [
      for (var i = 0; i < 5; i++)
        RowingSample(
          id: 0,
          rowingSessionId: ids.rowingSessionId,
          tOffsetMs: i * 2000,
          strokeRate: 22,
          distanceM: i * 30,
          paceSec500m: 130,
        ),
    ]);

    await rowing.finalize(
      ids.sessionId,
      distanceM: 120,
      duration: const Duration(seconds: 10),
      avgStrokeRate: 22,
    );

    expect(await sessions.activeSession(discipline: Discipline.rowing), isNull);

    final detail = await rowing.rowingDetail(ids.sessionId);
    expect(detail, isNotNull);
    expect(detail!.rowing.totalDistanceM, 120);
    expect(detail.rowing.durationSeconds, 10);
    expect(detail.samples, hasLength(5));
    expect(detail.samples.first.paceSec500m, 130);
  });

  test('discardSession removes the session and its rowing rows', () async {
    final ids = await rowing.startSession();
    await rowing.discardSession(ids.sessionId);
    expect(await rowing.rowingDetail(ids.sessionId), isNull);
    expect(await sessions.recentSessions(), isEmpty);
  });

  test('activeSession discipline filter ignores the other kind', () async {
    await sessions.startSession(discipline: Discipline.strength);
    // Newest unfinished is strength; a rowing-filtered lookup must not see it.
    expect(await sessions.activeSession(discipline: Discipline.rowing), isNull);
    expect(await sessions.activeSession(discipline: Discipline.strength),
        isNotNull);
  });

  test('progress aggregates: weekly distance, pace history, totals, streak',
      () async {
    await rowing.logManualSession(
        distanceM: 4000, duration: const Duration(minutes: 20));
    await rowing.logManualSession(
        distanceM: 3000, duration: const Duration(minutes: 16));

    final weekly = await rowing.weeklyDistance();
    expect(weekly, isNotEmpty);
    expect(weekly.last.distanceM, 7000);
    expect(weekly.last.sessions, 2);

    final pace = await rowing.paceHistory();
    expect(pace, hasLength(2));
    expect(pace.first.paceSec500, closeTo(1200 / 4000 * 500, 0.01));

    final totals = await rowing.totalsSince(
        DateTime.now().subtract(const Duration(days: 7)));
    expect(totals.sessions, 2);
    expect(totals.distanceM, 7000);
    expect(totals.durationSeconds, 20 * 60 + 16 * 60);

    expect(await rowing.weekStreak(), 1);
  });

  test('rowingDetail returns the plan segments for a plan session', () async {
    final programs = ProgramRepository(
        AppDatabase.instance, SettingsRepository(AppDatabase.instance));
    final programId = await programs.createProgram(NewProgramDraft(
      name: 'Plan',
      category: ProgramCategory.rowGenerated,
      discipline: Discipline.rowing,
      equipmentProfile: const [],
      daysPerWeek: 1,
      rowingGoal: RowingGoal.uithouding,
      days: [
        NewProgramDayDraft(label: 'Wk 1', segments: [
          NewRowSegmentDraft(
              durationSeconds: 180, targetStrokeRate: 18, intensityLabel: 'Warming-up'),
          NewRowSegmentDraft(
              durationSeconds: 1200, targetStrokeRate: 22, intensityLabel: 'Endurance'),
        ]),
      ],
    ));
    final dayId = (await programs.daysForProgram(programId)).first.id;

    final ids = await rowing.startSession(programDayId: dayId);
    await rowing.finalize(ids.sessionId,
        distanceM: 2000, duration: const Duration(minutes: 10));

    final detail = await rowing.rowingDetail(ids.sessionId);
    expect(detail!.planSegments, hasLength(2));
    expect(detail.planSegments.last.intensityLabel, 'Endurance');

    // A manual session has no plan segments.
    final manualId = await rowing.logManualSession(
        distanceM: 1000, duration: const Duration(minutes: 5));
    expect((await rowing.rowingDetail(manualId))!.planSegments, isEmpty);
  });

  test('paceHistory skips sessions with no distance', () async {
    final ids = await rowing.startSession();
    await rowing.finalize(ids.sessionId,
        distanceM: 0, duration: const Duration(minutes: 5));
    expect(await rowing.paceHistory(), isEmpty);
  });
}
