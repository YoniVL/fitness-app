import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/models/program.dart';
import '../database/app_database.dart';
import 'settings_repository.dart';

/// Plain description of a program to persist (used by the generator UI).
class NewProgramDraft {
  const NewProgramDraft({
    required this.name,
    required this.category,
    required this.equipmentProfile,
    this.level,
    this.daysPerWeek,
    required this.days,
  });

  final String name;
  final String category;
  final List<String> equipmentProfile;
  final ProgramLevel? level;
  final int? daysPerWeek;
  final List<NewProgramDayDraft> days;
}

class NewProgramDayDraft {
  const NewProgramDayDraft({required this.label, required this.exercises});
  final String label;
  final List<NewProgramExerciseDraft> exercises;
}

class NewProgramExerciseDraft {
  const NewProgramExerciseDraft({
    required this.exerciseId,
    required this.sets,
    required this.reps,
    required this.restBetweenSets,
    required this.restAfterExercise,
  });
  final int exerciseId;
  final int sets;
  final int reps;
  final int restBetweenSets;
  final int restAfterExercise;
}

class ProgramRepository {
  ProgramRepository(this._appDb, this._settings);

  final AppDatabase _appDb;
  final SettingsRepository _settings;

  // --- Reading programs ----------------------------------------------

  Future<List<Program>> allStrengthPrograms() async {
    final db = await _appDb.database;
    final rows = await db.query('programs',
        where: 'discipline = ?', whereArgs: ['strength'], orderBy: 'name');
    return rows.map(Program.fromMap).toList();
  }

  Future<List<Program>> rowingTemplates() async {
    final db = await _appDb.database;
    final rows = await db.query('programs',
        where: "discipline = 'rowing' AND is_template = 1", orderBy: 'name');
    return rows.map(Program.fromMap).toList();
  }

  /// Strength programs to show in the library: the user's own programs, plus
  /// templates whose equipment profile is covered by [owned]. Sorted by level
  /// (beginner -> medium -> advanced), then name.
  Future<List<Program>> visibleStrengthPrograms(Set<String> owned) async {
    final all = await allStrengthPrograms();
    final visible =
        all.where((p) => !p.isTemplate || p.fitsEquipment(owned)).toList();
    visible.sort((a, b) {
      final la = a.level?.index ?? 99;
      final lb = b.level?.index ?? 99;
      if (la != lb) return la.compareTo(lb);
      return a.name.compareTo(b.name);
    });
    return visible;
  }

  /// Persists a user-owned program (`is_template = 0`). Returns the new id.
  Future<int> createProgram(NewProgramDraft draft) async {
    final db = await _appDb.database;
    return db.transaction((txn) async {
      final programId = await txn.insert('programs', {
        'name': draft.name,
        'category': draft.category,
        'discipline': Discipline.strength.name,
        'is_template': 0,
        'level': draft.level?.name,
        'days_per_week': draft.daysPerWeek,
        'equipment_profile': draft.equipmentProfile.join(','),
      });
      for (var d = 0; d < draft.days.length; d++) {
        final day = draft.days[d];
        final dayId = await txn.insert('program_days', {
          'program_id': programId,
          'day_index': d,
          'label': day.label,
        });
        for (var i = 0; i < day.exercises.length; i++) {
          final e = day.exercises[i];
          await txn.insert('program_exercises', {
            'program_day_id': dayId,
            'exercise_id': e.exerciseId,
            'order_index': i,
            'target_sets': e.sets,
            'target_reps': e.reps,
            'target_weight': null,
            'rest_seconds': e.restBetweenSets,
            'rest_after_exercise': e.restAfterExercise,
          });
        }
      }
      return programId;
    });
  }

  /// Replaces every day/exercise of an existing (user-owned) program in place.
  /// Logged sessions that pointed at the old days keep their sets but lose the
  /// program-day link (their `program_day_id` becomes null); the progress
  /// cursor resets to day 1 since day meanings changed.
  Future<void> updateProgramContent(
    int programId, {
    String? name,
    required List<NewProgramDayDraft> days,
  }) async {
    final db = await _appDb.database;
    await db.transaction((txn) async {
      if (name != null) {
        await txn.update('programs', {'name': name},
            where: 'id = ?', whereArgs: [programId]);
      }

      final oldDayRows = await txn.query('program_days',
          columns: ['id'], where: 'program_id = ?', whereArgs: [programId]);
      final oldDayIds = oldDayRows.map((r) => r['id'] as int).toList();
      if (oldDayIds.isNotEmpty) {
        final placeholders = List.filled(oldDayIds.length, '?').join(',');
        await txn.update('workout_sessions', {'program_day_id': null},
            where: 'program_day_id IN ($placeholders)', whereArgs: oldDayIds);
        await txn.update('rowing_sessions', {'program_day_id': null},
            where: 'program_day_id IN ($placeholders)', whereArgs: oldDayIds);
      }
      // Cascades to program_exercises / program_row_segments.
      await txn.delete('program_days',
          where: 'program_id = ?', whereArgs: [programId]);

      for (var d = 0; d < days.length; d++) {
        final day = days[d];
        final dayId = await txn.insert('program_days', {
          'program_id': programId,
          'day_index': d,
          'label': day.label,
        });
        for (var i = 0; i < day.exercises.length; i++) {
          final e = day.exercises[i];
          await txn.insert('program_exercises', {
            'program_day_id': dayId,
            'exercise_id': e.exerciseId,
            'order_index': i,
            'target_sets': e.sets,
            'target_reps': e.reps,
            'target_weight': null,
            'rest_seconds': e.restBetweenSets,
            'rest_after_exercise': e.restAfterExercise,
          });
        }
      }

      await txn.delete('program_progress',
          where: 'program_id = ?', whereArgs: [programId]);
      await txn.update('programs', {'days_per_week': days.length},
          where: 'id = ?', whereArgs: [programId]);
    });
  }

  Future<void> deleteProgram(int programId) async {
    final db = await _appDb.database;
    await db.delete('programs', where: 'id = ?', whereArgs: [programId]);
    final activeId = await _settings.activeProgramId();
    if (activeId == programId) await _settings.setActiveProgramId(null);
  }

  Future<Program?> programById(int id) async {
    final db = await _appDb.database;
    final rows =
        await db.query('programs', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Program.fromMap(rows.first);
  }

  Future<List<ProgramDay>> daysForProgram(int programId) async {
    final db = await _appDb.database;
    final rows = await db.query('program_days',
        where: 'program_id = ?', whereArgs: [programId], orderBy: 'day_index');
    return rows.map(ProgramDay.fromMap).toList();
  }

  Future<ProgramDay?> dayById(int id) async {
    final db = await _appDb.database;
    final rows = await db
        .query('program_days', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : ProgramDay.fromMap(rows.first);
  }

  Future<List<ProgramExercise>> exercisesForDay(int programDayId) async {
    final db = await _appDb.database;
    final rows = await db.query('program_exercises',
        where: 'program_day_id = ?',
        whereArgs: [programDayId],
        orderBy: 'order_index');
    return rows.map(ProgramExercise.fromMap).toList();
  }

  Future<List<ProgramRowSegment>> rowSegmentsForDay(int programDayId) async {
    final db = await _appDb.database;
    final rows = await db.query('program_row_segments',
        where: 'program_day_id = ?',
        whereArgs: [programDayId],
        orderBy: 'order_index');
    return rows.map(ProgramRowSegment.fromMap).toList();
  }

  // --- Active program + progression cursor --------------------------

  Future<void> setActiveProgram(int programId) async {
    final db = await _appDb.database;
    // Reset the cursor whenever a program is (re)chosen.
    await db.insert(
      'program_progress',
      {'program_id': programId, 'current_day_index': 0, 'round': 1},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _settings.setActiveProgramId(programId);
  }

  Future<void> clearActiveProgram() => _settings.setActiveProgramId(null);

  Future<ActiveProgram?> activeProgram() async {
    final id = await _settings.activeProgramId();
    if (id == null) return null;
    final program = await programById(id);
    if (program == null) return null;
    final days = await daysForProgram(id);
    if (days.isEmpty) return null;

    final db = await _appDb.database;
    final rows = await db.query('program_progress',
        where: 'program_id = ?', whereArgs: [id], limit: 1);
    final cursor = rows.isEmpty ? 0 : (rows.first['current_day_index'] as int);
    final round = rows.isEmpty ? 1 : (rows.first['round'] as int);
    return ActiveProgram(
      program: program,
      days: days,
      currentDayIndex: cursor % days.length,
      round: round,
    );
  }

  /// Advances the cursor of the active program if [finishedProgramDayId] is its
  /// current day. Wrapping past the last day bumps the round counter.
  Future<void> advanceIfCurrentDay(int finishedProgramDayId) async {
    final active = await activeProgram();
    if (active == null) return;
    if (active.currentDay.id != finishedProgramDayId) return;

    final next = (active.currentDayIndex + 1) % active.dayCount;
    final round = next == 0 ? active.round + 1 : active.round;
    final db = await _appDb.database;
    await db.update(
      'program_progress',
      {
        'current_day_index': next,
        'round': round,
        'last_completed_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'program_id = ?',
      whereArgs: [active.program.id],
    );
  }

  Future<void> setCursor(int programId, int dayIndex) async {
    final db = await _appDb.database;
    final updated = await db.update(
      'program_progress',
      {'current_day_index': dayIndex},
      where: 'program_id = ?',
      whereArgs: [programId],
    );
    if (updated == 0) {
      await db.insert('program_progress', {
        'program_id': programId,
        'current_day_index': dayIndex,
        'round': 1,
      });
    }
  }
}

final programRepositoryProvider = Provider<ProgramRepository>(
  (ref) => ProgramRepository(
    AppDatabase.instance,
    ref.watch(settingsRepositoryProvider),
  ),
);

final rowingTemplatesProvider = FutureProvider<List<Program>>(
  (ref) => ref.watch(programRepositoryProvider).rowingTemplates(),
);

final visibleStrengthProgramsProvider = FutureProvider<List<Program>>(
  (ref) async {
    final owned = await ref.watch(ownedEquipmentProvider.future);
    return ref.watch(programRepositoryProvider).visibleStrengthPrograms(owned);
  },
);

final activeProgramProvider = FutureProvider<ActiveProgram?>(
  (ref) => ref.watch(programRepositoryProvider).activeProgram(),
);
