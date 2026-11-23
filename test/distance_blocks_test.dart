import 'dart:convert';

import 'package:fitnesstracker/data/database/app_database.dart';
import 'package:fitnesstracker/data/database/migrations.dart';
import 'package:fitnesstracker/data/repositories/program_repository.dart';
import 'package:fitnesstracker/data/repositories/rowing_repository.dart';
import 'package:fitnesstracker/data/repositories/settings_repository.dart';
import 'package:fitnesstracker/domain/models/program.dart';
import 'package:fitnesstracker/domain/models/workout_session.dart';
import 'package:fitnesstracker/features/rowing/state/active_rowing_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show ConflictAlgorithm;

import 'helpers.dart';

ProgramRowSegment _timed(int order, int seconds, {bool rest = false}) =>
    ProgramRowSegment(
      id: order,
      programDayId: 1,
      orderIndex: order,
      durationSeconds: seconds,
      intensityLabel: rest ? 'Rust' : 'Blok',
      isRest: rest,
    );

ProgramRowSegment _dist(int order, int meters, {int estimate = 300}) =>
    ProgramRowSegment(
      id: order,
      programDayId: 1,
      orderIndex: order,
      durationSeconds: estimate,
      intensityLabel: 'Afstand',
      distanceM: meters,
    );

ActiveRowingState _state(
  List<ProgramRowSegment> segs, {
  int index = 0,
  Duration segElapsed = Duration.zero,
  double segDistance = 0,
}) =>
    ActiveRowingState(
      session: WorkoutSession(
          id: 1, discipline: Discipline.rowing, startedAt: DateTime(2026, 9, 3)),
      rowingSessionId: 1,
      segments: segs,
      segmentIndex: index,
      segmentElapsed: segElapsed,
      segmentDistanceM: segDistance,
    );

void main() {
  group('live state with a distance block', () {
    final segs = [_timed(0, 120), _dist(1, 2000, estimate: 500), _timed(2, 60)];

    test('the block is complete on its metres, not on its estimate', () {
      // 600 s in the block is past the 500 s estimate but only 1500 m rowed.
      final slow = _state(segs,
          index: 1, segElapsed: const Duration(seconds: 600), segDistance: 1500);
      expect(slow.currentSegmentComplete, isFalse);
      final done = _state(segs,
          index: 1, segElapsed: const Duration(seconds: 30), segDistance: 2000);
      expect(done.currentSegmentComplete, isTrue);
    });

    test('metres left count down and clamp at zero', () {
      expect(_state(segs, index: 1, segDistance: 1250).segmentRemainingDistanceM,
          750);
      expect(_state(segs, index: 1, segDistance: 2400).segmentRemainingDistanceM,
          0);
      expect(_state(segs, index: 0).segmentRemainingDistanceM, isNull);
    });

    test('a planned session ending on a distance block completes on its metres',
        () {
      final ends = [_timed(0, 60), _dist(1, 5000)];
      expect(_state(ends, index: 1, segDistance: 4999).plannedSessionComplete,
          isFalse);
      expect(_state(ends, index: 1, segDistance: 5000).plannedSessionComplete,
          isTrue);
      // Time alone never finishes it.
      expect(
          _state(ends,
                  index: 1,
                  segElapsed: const Duration(seconds: 9999),
                  segDistance: 10)
              .plannedSessionComplete,
          isFalse);
    });

    test('the profile marker moves with the metres inside a distance block', () {
      // total = 120 + 500 + 60 = 680 s; at the start of the block: 120/680.
      final start = _state(segs, index: 1).segmentProgressFraction;
      expect(start, closeTo(120 / 680, 0.001));
      // Halfway through the metres: 120 + 250.
      final half = _state(segs, index: 1, segDistance: 1000).segmentProgressFraction;
      expect(half, closeTo(370 / 680, 0.001));
      // Elapsed time doesn't move it inside a distance block.
      final slow = _state(segs,
              index: 1, segElapsed: const Duration(seconds: 400), segDistance: 1000)
          .segmentProgressFraction;
      expect(slow, half);
    });

    test('a timed block still runs on the clock', () {
      final s = _state(segs, index: 0, segElapsed: const Duration(seconds: 120));
      expect(s.currentSegmentComplete, isTrue);
    });
  });

  group('storage', () {
    setUp(initTestDatabase);
    tearDown(closeTestDatabase);

    test('the library templates contain distance blocks', () async {
      final db = await AppDatabase.instance.database;
      final n = (await db.rawQuery(
              'SELECT COUNT(*) AS n FROM program_row_segments '
              'WHERE distance_m IS NOT NULL'))
          .first['n'] as int;
      expect(n, greaterThan(20));
      // ...and never on a rest block.
      final onRest = (await db.rawQuery(
              'SELECT COUNT(*) AS n FROM program_row_segments '
              'WHERE distance_m IS NOT NULL AND is_rest = 1'))
          .first['n'] as int;
      expect(onRest, 0);
    });

    test('createProgram keeps the distance and reads it back', () async {
      final repo = ProgramRepository(
          AppDatabase.instance, SettingsRepository(AppDatabase.instance));
      final id = await repo.createProgram(NewProgramDraft(
        name: 'Afstandsplan',
        category: ProgramCategory.rowGenerated,
        discipline: Discipline.rowing,
        equipmentProfile: const [],
        days: [
          NewProgramDayDraft(label: 'Dag 1', rowSessionType: 'endurance', segments: [
            NewRowSegmentDraft(
                durationSeconds: 1577,
                distanceM: 6000,
                targetStrokeRate: 21,
                intensityLabel: '6.000 m'),
            NewRowSegmentDraft(
                durationSeconds: 90, intensityLabel: 'Rust', isRest: true),
          ]),
        ],
      ));
      final day = (await repo.daysForProgram(id)).single;
      final segs = await repo.rowSegmentsForDay(day.id);
      expect(segs[0].distanceM, 6000);
      expect(segs[0].isDistance, isTrue);
      expect(segs[0].durationSeconds, 1577);
      expect(segs[1].distanceM, isNull);
    });

    test('the ad-hoc workout JSON round-trips the distance', () {
      final segs = [_timed(0, 180), _dist(1, 2000, estimate: 490)];
      final back = decodeRowSegments(encodeRowSegments(segs));
      expect(back[0].distanceM, isNull);
      expect(back[1].distanceM, 2000);
      expect(back[1].durationSeconds, 490);
    });

    test('an older workout JSON without distances still decodes', () {
      final json = jsonEncode([
        {'d': 60, 'spm': 20, 'label': 'Oud', 'rest': false}
      ]);
      final segs = decodeRowSegments(json);
      expect(segs.single.distanceM, isNull);
      expect(segs.single.isDistance, isFalse);
    });
  });

  group('migration v9 -> v10', () {
    setUp(initTestDatabase);
    tearDown(closeTestDatabase);

    test('reseeds the templates, keeps history and carries the active plan over',
        () async {
      final db = await AppDatabase.instance.database;
      final settings = SettingsRepository(AppDatabase.instance);

      // A template plan the user is on, with some sessions logged against it.
      final plan = (await db.query('programs',
              where: "discipline = 'rowing' AND category = 'row_plan' "
                  'AND is_template = 1',
              limit: 1))
          .first;
      final planName = plan['name'] as String;
      final oldId = plan['id'] as int;
      final days = await db.query('program_days',
          where: 'program_id = ?', whereArgs: [oldId], orderBy: 'day_index');
      final day = days[2];
      final daySegs = await db.query('program_row_segments',
          where: 'program_day_id = ?', whereArgs: [day['id']]);

      final templatesBefore = (await db.rawQuery(
              "SELECT COUNT(*) AS n FROM programs "
              "WHERE discipline = 'rowing' AND is_template = 1"))
          .first['n'] as int;

      final wsId = await db.insert('workout_sessions', {
        'discipline': 'rowing',
        'program_day_id': day['id'],
        'started_at': DateTime(2026, 10, 1).millisecondsSinceEpoch,
        'ended_at': DateTime(2026, 10, 1, 1).millisecondsSinceEpoch,
      });
      await db.insert('rowing_sessions', {
        'session_id': wsId,
        'program_day_id': day['id'],
        'total_distance_m': 4200.0,
        'duration_seconds': 1800,
        'kind': 'endurance',
      });
      await db.insert('program_progress',
          {'program_id': oldId, 'current_day_index': 3, 'round': 2},
          conflictAlgorithm: ConflictAlgorithm.replace);
      await settings.setActiveRowingProgramId(oldId);

      await migrateV9toV10(db);

      // The history row survives, no longer pointing at a deleted day, and keeps
      // the plan it followed as its own copy.
      final ws = (await db.query('workout_sessions',
              where: 'id = ?', whereArgs: [wsId]))
          .single;
      expect(ws['program_day_id'], isNull);
      final rs = (await db.query('rowing_sessions',
              where: 'session_id = ?', whereArgs: [wsId]))
          .single;
      expect(rs['program_day_id'], isNull);
      expect(rs['total_distance_m'], 4200.0);
      final kept = decodeRowSegments(rs['segments_json'] as String);
      expect(kept.length, daySegs.length);

      // The old template is gone, the library is whole again.
      expect(await db.query('programs', where: 'id = ?', whereArgs: [oldId]),
          isEmpty);
      final templatesAfter = (await db.rawQuery(
              "SELECT COUNT(*) AS n FROM programs "
              "WHERE discipline = 'rowing' AND is_template = 1"))
          .first['n'] as int;
      expect(templatesAfter, templatesBefore);

      // The active plan is now its reseeded twin, at the same place in it.
      final activeId = await settings.activeRowingProgramId();
      expect(activeId, isNotNull);
      expect(activeId, isNot(oldId));
      final twin = (await db.query('programs',
              where: 'id = ?', whereArgs: [activeId]))
          .single;
      expect(twin['name'], planName);
      expect(twin['is_template'], 1);
      final progress = (await db.query('program_progress',
              where: 'program_id = ?', whereArgs: [activeId]))
          .single;
      expect(progress['current_day_index'], 3);
      expect(progress['round'], 2);
    });

    test('is safe to run when the column is already there', () async {
      final db = await AppDatabase.instance.database;
      await migrateV9toV10(db);
      await migrateV9toV10(db);
      final n = (await db.rawQuery(
              "SELECT COUNT(*) AS n FROM programs "
              "WHERE discipline = 'rowing' AND is_template = 1 "
              "AND category = 'row_plan'"))
          .first['n'] as int;
      expect(n, greaterThanOrEqualTo(12));
    });

    test('a user-owned plan is left alone', () async {
      final db = await AppDatabase.instance.database;
      final repo = ProgramRepository(
          AppDatabase.instance, SettingsRepository(AppDatabase.instance));
      final id = await repo.createProgram(NewProgramDraft(
        name: 'Mijn plan',
        category: ProgramCategory.rowGenerated,
        discipline: Discipline.rowing,
        equipmentProfile: const [],
        days: [
          NewProgramDayDraft(label: 'Dag 1', segments: [
            NewRowSegmentDraft(durationSeconds: 600, intensityLabel: 'Duur'),
          ]),
        ],
      ));
      await migrateV9toV10(db);
      expect(await db.query('programs', where: 'id = ?', whereArgs: [id]),
          hasLength(1));
      final days = await repo.daysForProgram(id);
      expect(await repo.rowSegmentsForDay(days.single.id), hasLength(1));
    });
  });
}
