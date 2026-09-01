import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/models/program.dart';
import '../database/app_database.dart';

class ProgramRepository {
  ProgramRepository(this._appDb);

  final AppDatabase _appDb;

  Future<List<Program>> templates({Discipline? discipline}) async {
    final db = await _appDb.database;
    final rows = await db.query(
      'programs',
      where: discipline == null
          ? 'is_template = 1'
          : 'is_template = 1 AND discipline = ?',
      whereArgs: discipline == null ? null : [discipline.name],
      orderBy: 'discipline, name',
    );
    return rows.map(Program.fromMap).toList();
  }

  Future<Program?> programById(int id) async {
    final db = await _appDb.database;
    final rows = await db.query('programs', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Program.fromMap(rows.first);
  }

  Future<List<ProgramDay>> daysForProgram(int programId) async {
    final db = await _appDb.database;
    final rows = await db.query(
      'program_days',
      where: 'program_id = ?',
      whereArgs: [programId],
      orderBy: 'day_index',
    );
    return rows.map(ProgramDay.fromMap).toList();
  }

  Future<ProgramDay?> dayById(int id) async {
    final db = await _appDb.database;
    final rows = await db.query('program_days', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : ProgramDay.fromMap(rows.first);
  }

  Future<List<ProgramExercise>> exercisesForDay(int programDayId) async {
    final db = await _appDb.database;
    final rows = await db.query(
      'program_exercises',
      where: 'program_day_id = ?',
      whereArgs: [programDayId],
      orderBy: 'order_index',
    );
    return rows.map(ProgramExercise.fromMap).toList();
  }

  Future<List<ProgramRowSegment>> rowSegmentsForDay(int programDayId) async {
    final db = await _appDb.database;
    final rows = await db.query(
      'program_row_segments',
      where: 'program_day_id = ?',
      whereArgs: [programDayId],
      orderBy: 'order_index',
    );
    return rows.map(ProgramRowSegment.fromMap).toList();
  }

  /// The program day scheduled for [weekday] (`DateTime.monday`..`sunday`),
  /// based on the `weekly_schedule` setting, or null if nothing is planned.
  Future<ProgramDay?> scheduledDayFor(DateTime date) async {
    final db = await _appDb.database;
    final rows = await db.query('app_settings',
        where: 'key = ?', whereArgs: ['weekly_schedule'], limit: 1);
    if (rows.isEmpty) return null;
    final raw = rows.first['value'] as String;
    final Map<String, dynamic> schedule =
        (jsonDecode(raw) as Map).cast<String, dynamic>();
    final dayId = schedule['${date.weekday}'];
    if (dayId is! int) return null;
    return dayById(dayId);
  }

  Future<void> setScheduledDay(int weekday, int? programDayId) async {
    final db = await _appDb.database;
    final rows = await db.query('app_settings',
        where: 'key = ?', whereArgs: ['weekly_schedule'], limit: 1);
    final Map<String, dynamic> schedule = rows.isEmpty
        ? {}
        : (jsonDecode(rows.first['value'] as String) as Map).cast<String, dynamic>();
    if (programDayId == null) {
      schedule.remove('$weekday');
    } else {
      schedule['$weekday'] = programDayId;
    }
    await db.insert(
      'app_settings',
      {'key': 'weekly_schedule', 'value': jsonEncode(schedule)},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

final programRepositoryProvider = Provider<ProgramRepository>(
  (ref) => ProgramRepository(AppDatabase.instance),
);

final strengthTemplatesProvider = FutureProvider<List<Program>>(
  (ref) => ref.watch(programRepositoryProvider).templates(discipline: Discipline.strength),
);

final rowingTemplatesProvider = FutureProvider<List<Program>>(
  (ref) => ref.watch(programRepositoryProvider).templates(discipline: Discipline.rowing),
);

final scheduledDayTodayProvider = FutureProvider<ProgramDay?>(
  (ref) => ref.watch(programRepositoryProvider).scheduledDayFor(DateTime.now()),
);
