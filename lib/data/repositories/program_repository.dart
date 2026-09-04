import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/models/program.dart';
import '../../domain/models/rowing_plan.dart';
import '../../domain/rowing_ftp.dart';
import '../../domain/rowing_workouts.dart' show RowIntensity;
import '../database/app_database.dart';
import 'settings_repository.dart';

/// Plain description of a program to persist (used by the generator UIs).
class NewProgramDraft {
  const NewProgramDraft({
    required this.name,
    required this.category,
    required this.equipmentProfile,
    this.discipline = Discipline.strength,
    this.level,
    this.daysPerWeek,
    this.rowingGoal,
    this.ftpWattsAtGen,
    required this.days,
  });

  final String name;
  final String category;
  final List<String> equipmentProfile;
  final Discipline discipline;
  final ProgramLevel? level;
  final int? daysPerWeek;
  final RowingGoal? rowingGoal;

  /// The FTP a generated rowing plan's per-segment targets were built against.
  final double? ftpWattsAtGen;
  final List<NewProgramDayDraft> days;
}

class NewProgramDayDraft {
  const NewProgramDayDraft({
    required this.label,
    this.exercises = const [],
    this.segments = const [],
    this.rowSessionType,
  });
  final String label;
  final List<NewProgramExerciseDraft> exercises;
  final List<NewRowSegmentDraft> segments;

  /// `RowSessionType.name` for a generated rowing-plan day, else null.
  final String? rowSessionType;
}

class NewRowSegmentDraft {
  const NewRowSegmentDraft({
    required this.durationSeconds,
    this.targetStrokeRate,
    required this.intensityLabel,
    this.isRest = false,
    this.drillKey,
    this.zone,
    this.targetWatts,
  });
  final int durationSeconds;
  final int? targetStrokeRate;
  final String intensityLabel;
  final bool isRest;
  final String? drillKey;
  final String? zone;
  final double? targetWatts;
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

  /// All rowing programs — the user's own plans first, then the templates.
  Future<List<Program>> rowingPrograms() async {
    final db = await _appDb.database;
    final rows = await db.query('programs',
        where: "discipline = 'rowing'",
        orderBy: 'is_template ASC, name');
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
        'discipline': draft.discipline.name,
        'is_template': 0,
        'level': draft.level?.name,
        'days_per_week': draft.daysPerWeek,
        'equipment_profile': draft.equipmentProfile.join(','),
        'goal': draft.rowingGoal?.name,
        'ftp_watts_at_gen': draft.ftpWattsAtGen,
      });
      for (var d = 0; d < draft.days.length; d++) {
        final day = draft.days[d];
        final dayId = await txn.insert('program_days', {
          'program_id': programId,
          'day_index': d,
          'label': day.label,
          'row_session_type': day.rowSessionType,
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
        for (var i = 0; i < day.segments.length; i++) {
          final s = day.segments[i];
          await txn.insert('program_row_segments', {
            'program_day_id': dayId,
            'order_index': i,
            'duration_seconds': s.durationSeconds,
            'target_stroke_rate': s.targetStrokeRate,
            'intensity_label': s.intensityLabel,
            'is_rest': s.isRest ? 1 : 0,
            'drill_key': s.drillKey,
            'zone': s.zone,
            'target_watts': s.targetWatts,
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

      await _detachSessionsFromProgramDays(txn, programId);
      // Cascades to program_exercises / program_row_segments.
      await txn.delete('program_days',
          where: 'program_id = ?', whereArgs: [programId]);

      for (var d = 0; d < days.length; d++) {
        final day = days[d];
        final dayId = await txn.insert('program_days', {
          'program_id': programId,
          'day_index': d,
          'label': day.label,
          'row_session_type': day.rowSessionType,
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

  /// Nulls out `workout_sessions`/`rowing_sessions.program_day_id` for every
  /// day of [programId] — neither table cascades from `program_days`, so this
  /// must run before those days are deleted or the delete throws on the
  /// foreign-key constraint. Logged sessions keep their rows; they just lose
  /// the link to a day that's about to stop existing.
  Future<void> _detachSessionsFromProgramDays(
      DatabaseExecutor txn, int programId) async {
    final dayRows = await txn.query('program_days',
        columns: ['id'], where: 'program_id = ?', whereArgs: [programId]);
    final dayIds = dayRows.map((r) => r['id'] as int).toList();
    if (dayIds.isEmpty) return;
    final placeholders = List.filled(dayIds.length, '?').join(',');
    await txn.update('workout_sessions', {'program_day_id': null},
        where: 'program_day_id IN ($placeholders)', whereArgs: dayIds);
    await txn.update('rowing_sessions', {'program_day_id': null},
        where: 'program_day_id IN ($placeholders)', whereArgs: dayIds);
  }

  /// Deletes a program (cascades to its days/exercises/segments), first
  /// detaching any logged sessions from those days so history is kept.
  Future<void> deleteProgram(int programId) async {
    final db = await _appDb.database;
    await db.transaction((txn) async {
      await _detachSessionsFromProgramDays(txn, programId);
      await txn.delete('programs', where: 'id = ?', whereArgs: [programId]);
    });
    if (await _settings.activeProgramId() == programId) {
      await _settings.setActiveProgramId(null);
    }
    if (await _settings.activeRowingProgramId() == programId) {
      await _settings.setActiveRowingProgramId(null);
    }
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

  /// Recomputes `target_watts` for every non-rest segment of [programId] from
  /// its stored zone against [ftpWatts], and records [ftpWatts] as the plan's
  /// generation FTP. Used when the user's FTP has drifted from the plan.
  Future<void> rewriteRowTargets(int programId, double ftpWatts) async {
    final db = await _appDb.database;
    final zones = RowingZones.fromFtp(ftpWatts);
    await db.transaction((txn) async {
      final segs = await txn.rawQuery(
        'SELECT s.id AS id, s.zone AS zone, s.is_rest AS is_rest '
        'FROM program_row_segments s '
        'JOIN program_days d ON d.id = s.program_day_id '
        'WHERE d.program_id = ?',
        [programId],
      );
      for (final row in segs) {
        final isRest = (row['is_rest'] as int? ?? 0) == 1;
        final zone = _rowIntensity(row['zone'] as String?);
        final watts = (isRest || zone == null)
            ? null
            : zones[zone]?.targetWatts.roundToDouble();
        await txn.update('program_row_segments', {'target_watts': watts},
            where: 'id = ?', whereArgs: [row['id']]);
      }
      await txn.update('programs', {'ftp_watts_at_gen': ftpWatts},
          where: 'id = ?', whereArgs: [programId]);
    });
  }

  static RowIntensity? _rowIntensity(String? name) {
    if (name == null) return null;
    for (final z in RowIntensity.values) {
      if (z.name == name) return z;
    }
    return null;
  }

  // --- Active program + progression cursor --------------------------

  Future<void> setActiveProgram(int programId) async {
    await _setActive(programId, rowing: false);
  }

  Future<void> setActiveRowingProgram(int programId) async {
    await _setActive(programId, rowing: true);
  }

  Future<void> _setActive(int programId, {required bool rowing}) async {
    final db = await _appDb.database;
    // Reset the cursor whenever a program is (re)chosen.
    await db.insert(
      'program_progress',
      {'program_id': programId, 'current_day_index': 0, 'round': 1},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    if (rowing) {
      await _settings.setActiveRowingProgramId(programId);
    } else {
      await _settings.setActiveProgramId(programId);
    }
  }

  Future<void> clearActiveProgram() => _settings.setActiveProgramId(null);
  Future<void> clearActiveRowingProgram() =>
      _settings.setActiveRowingProgramId(null);

  Future<ActiveProgram?> activeProgram() =>
      _buildActiveProgram(_settings.activeProgramId());

  Future<ActiveProgram?> activeRowingProgram() =>
      _buildActiveProgram(_settings.activeRowingProgramId());

  Future<ActiveProgram?> _buildActiveProgram(Future<int?> idFuture) async {
    final id = await idFuture;
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

  /// Advances the cursor of the active strength program if [finishedProgramDayId]
  /// is its current day. Wrapping past the last day bumps the round counter.
  Future<void> advanceIfCurrentDay(int finishedProgramDayId) async =>
      _advance(await activeProgram(), finishedProgramDayId);

  /// The rowing-slot equivalent of [advanceIfCurrentDay].
  Future<void> advanceRowingIfCurrentDay(int finishedProgramDayId) async =>
      _advance(await activeRowingProgram(), finishedProgramDayId);

  Future<void> _advance(ActiveProgram? active, int finishedProgramDayId) async {
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

final rowingProgramsProvider = FutureProvider<List<Program>>(
  (ref) => ref.watch(programRepositoryProvider).rowingPrograms(),
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

final activeRowingProgramProvider = FutureProvider<ActiveProgram?>(
  (ref) => ref.watch(programRepositoryProvider).activeRowingProgram(),
);
