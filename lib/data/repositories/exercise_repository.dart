import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/exercise.dart';
import '../../domain/models/muscle_group.dart';
import '../database/app_database.dart';

class ExerciseRepository {
  ExerciseRepository(this._appDb);

  final AppDatabase _appDb;

  Future<List<MuscleGroup>> muscleGroups() async {
    final db = await _appDb.database;
    final rows = await db.query('muscle_groups', orderBy: 'id');
    return rows.map(MuscleGroup.fromMap).toList();
  }

  /// All exercises, optionally filtered by primary muscle group and/or a
  /// case-insensitive name search.
  Future<List<Exercise>> exercises({int? muscleGroupId, String? search}) async {
    final db = await _appDb.database;
    final where = <String>[];
    final args = <Object?>[];
    if (muscleGroupId != null) {
      where.add('primary_muscle_group_id = ?');
      args.add(muscleGroupId);
    }
    if (search != null && search.trim().isNotEmpty) {
      where.add('name LIKE ?');
      args.add('%${search.trim()}%');
    }
    final rows = await db.query(
      'exercises',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(Exercise.fromMap).toList();
  }

  Future<Exercise?> byId(int id) async {
    final db = await _appDb.database;
    final rows = await db.query('exercises', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Exercise.fromMap(rows.first);
  }

  Future<Map<int, Exercise>> byIds(Iterable<int> ids) async {
    final unique = ids.toSet().toList();
    if (unique.isEmpty) return {};
    final db = await _appDb.database;
    final placeholders = List.filled(unique.length, '?').join(',');
    final rows = await db.query(
      'exercises',
      where: 'id IN ($placeholders)',
      whereArgs: unique,
    );
    return {for (final r in rows) r['id'] as int: Exercise.fromMap(r)};
  }

  /// The full strength catalogue with a `pattern` set — the generator's input.
  Future<List<Exercise>> strengthCatalogue() async {
    final db = await _appDb.database;
    final rows = await db.query('exercises',
        where: 'pattern IS NOT NULL', orderBy: 'name COLLATE NOCASE');
    return rows.map(Exercise.fromMap).toList();
  }

  /// muscle group id -> name, for aggregation / display.
  Future<Map<int, String>> muscleGroupNames() async {
    final groups = await muscleGroups();
    return {for (final g in groups) g.id: g.name};
  }

  Future<int> addCustom(Exercise exercise) async {
    final db = await _appDb.database;
    return db.insert('exercises', exercise.toMap()..['is_custom'] = 1);
  }
}

final exerciseRepositoryProvider = Provider<ExerciseRepository>(
  (ref) => ExerciseRepository(AppDatabase.instance),
);

final muscleGroupsProvider = FutureProvider<List<MuscleGroup>>(
  (ref) => ref.watch(exerciseRepositoryProvider).muscleGroups(),
);
