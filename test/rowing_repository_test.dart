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

  test('deleting a session drops it from the weekly distance', () async {
    final keep = await rowing.logManualSession(
        distanceM: 4000, duration: const Duration(minutes: 20));
    final drop = await rowing.logManualSession(
        distanceM: 3000, duration: const Duration(minutes: 16));
    expect((await rowing.weeklyDistance()).last.distanceM, 7000);

    await WorkoutSessionRepository(AppDatabase.instance).deleteSession(drop);
    expect((await rowing.weeklyDistance()).last.distanceM, 4000);
    expect((await rowing.weeklyDistance()).last.sessions, 1);

    // Sanity: the kept session is untouched.
    expect(await rowing.rowingDetail(keep), isNotNull);
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

  test('an ad-hoc workout keeps its segments across a "restart"', () async {
    final segs = [
      const ProgramRowSegment(
          id: 0,
          programDayId: 0,
          orderIndex: 0,
          durationSeconds: 120,
          targetStrokeRate: 18,
          intensityLabel: 'Warming-up',
          zone: 'easy'),
      const ProgramRowSegment(
          id: 0,
          programDayId: 0,
          orderIndex: 1,
          durationSeconds: 600,
          targetStrokeRate: 22,
          intensityLabel: 'Endurance',
          zone: 'steady'),
    ];
    final ids = await rowing.startSession(
        segmentsJson: encodeRowSegments(segs), kind: 'endurance');
    // Fresh repo instance = the app coming back up.
    final detail = await RowingRepository(AppDatabase.instance)
        .rowingDetail(ids.sessionId);
    expect(detail!.planSegments, hasLength(2));
    expect(detail.planSegments[1].intensityLabel, 'Endurance');
    expect(detail.planSegments[1].zone, 'steady');
    expect(detail.rowing.kind, 'endurance');
  });

  test('paceHistory filters by kind; benchmarkHistory groups + picks the PR',
      () async {
    await rowing.logManualSession(
        distanceM: 5000,
        duration: const Duration(minutes: 22),
        kind: 'endurance',
        when: DateTime(2026, 8, 1));
    await rowing.logManualSession(
        distanceM: 2000,
        duration: const Duration(minutes: 7, seconds: 40),
        kind: 'test',
        when: DateTime(2026, 8, 10));
    await rowing.logManualSession(
        distanceM: 2000,
        duration: const Duration(minutes: 7, seconds: 20),
        kind: 'test',
        when: DateTime(2026, 8, 24));

    expect(await rowing.paceHistory(kinds: {'endurance'}), hasLength(1));
    expect(await rowing.paceHistory(kinds: {'test'}), hasLength(2));
    expect(await rowing.paceHistory(), hasLength(3));

    final benches = await rowing.benchmarkHistory();
    expect(benches, hasLength(1));
    expect(benches.first.distanceM, 2000);
    expect(benches.first.attempts, hasLength(2));
    expect(benches.first.bestSeconds, 7 * 60 + 20);
    expect(benches.first.latest.seconds, 7 * 60 + 20);
  });

  test('logManualSession respects the given date', () async {
    final when = DateTime(2026, 7, 15, 9, 30);
    await rowing.logManualSession(
        distanceM: 3000, duration: const Duration(minutes: 15), when: when);
    final recent = await sessions.recentSessions();
    expect(recent.first.session.startedAt,
        when.subtract(const Duration(minutes: 15)));
  });

  test('finalize writes the aggregate distance and keeps the samples', () async {
    final ids = await rowing.startSession();
    await rowing.addSamples(ids.rowingSessionId, [
      for (var i = 0; i < 4; i++)
        RowingSample(
          id: 0,
          rowingSessionId: ids.rowingSessionId,
          tOffsetMs: i * 2000,
          distanceM: i * 100.0,
        ),
    ]);
    await rowing.finalize(ids.sessionId,
        distanceM: 300, duration: const Duration(minutes: 2));
    final detail = await rowing.rowingDetail(ids.sessionId);
    expect(detail!.rowing.totalDistanceM, 300);
    expect(detail.samples, hasLength(4));
  });
}
