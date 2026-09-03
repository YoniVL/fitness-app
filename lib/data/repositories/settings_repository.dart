import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/taxonomy.dart';
import '../database/app_database.dart';

/// Thin key/value access over the `app_settings` table.
class SettingsRepository {
  SettingsRepository(this._appDb);

  final AppDatabase _appDb;

  Future<String?> getString(String key) async {
    final db = await _appDb.database;
    final rows = await db
        .query('app_settings', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<int> getInt(String key, int fallback) async {
    final raw = await getString(key);
    return int.tryParse(raw ?? '') ?? fallback;
  }

  Future<bool> getBool(String key, bool fallback) async {
    final raw = await getString(key);
    if (raw == null) return fallback;
    return raw == 'true' || raw == '1';
  }

  Future<void> set(String key, String value) async {
    final db = await _appDb.database;
    await db.insert(
      'app_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> setInt(String key, int value) => set(key, '$value');
  Future<void> setBool(String key, bool value) =>
      set(key, value ? 'true' : 'false');

  Future<void> remove(String key) async {
    final db = await _appDb.database;
    await db.delete('app_settings', where: 'key = ?', whereArgs: [key]);
  }

  // --- Convenience ----------------------------------------------------

  Future<Set<String>> ownedEquipment() async {
    final tags = Equipment.parse(await getString(SettingsKeys.ownedEquipment));
    return tags.isEmpty ? {...Equipment.defaultOwned} : tags.toSet();
  }

  Future<void> setOwnedEquipment(Set<String> tags) =>
      set(SettingsKeys.ownedEquipment, Equipment.join(tags));

  Future<int> restBetweenSets() =>
      getInt(SettingsKeys.defaultRestBetweenSets, 30);

  Future<int> restAfterExercise() =>
      getInt(SettingsKeys.defaultRestAfterExercise, 60);

  Future<bool> autoProgression() =>
      getBool(SettingsKeys.autoProgression, true);

  Future<bool> warmupSuggestions() =>
      getBool(SettingsKeys.warmupSuggestions, false);

  Future<int?> activeProgramId() async {
    final raw = await getString(SettingsKeys.activeProgramId);
    return raw == null ? null : int.tryParse(raw);
  }

  Future<void> setActiveProgramId(int? id) =>
      id == null ? remove(SettingsKeys.activeProgramId) : setInt(SettingsKeys.activeProgramId, id);

  Future<int?> activeRowingProgramId() async {
    final raw = await getString(SettingsKeys.activeRowingProgramId);
    return raw == null ? null : int.tryParse(raw);
  }

  Future<void> setActiveRowingProgramId(int? id) => id == null
      ? remove(SettingsKeys.activeRowingProgramId)
      : setInt(SettingsKeys.activeRowingProgramId, id);

  /// Whether the simulated rower is used instead of the Bluetooth trainer.
  /// Until the user makes an explicit choice it defaults to on when no trainer
  /// is paired (so "losse roeisessie" still has data), off once one is.
  Future<bool> rowingDemoMode() async {
    final raw = await getString(SettingsKeys.rowingDemoMode);
    if (raw != null) return raw == 'true' || raw == '1';
    return (await getString(SettingsKeys.rowingDeviceId)) == null;
  }
}

class SettingsKeys {
  static const ownedEquipment = 'owned_equipment';
  static const defaultRestBetweenSets = 'default_rest_between_sets';
  static const defaultRestAfterExercise = 'default_rest_after_exercise';
  static const restTimerSound = 'rest_timer_sound';
  static const activeProgramId = 'active_program_id';
  static const autoProgression = 'auto_progression';
  static const warmupSuggestions = 'warmup_suggestions';
  static const activeRowingProgramId = 'active_rowing_program_id';
  static const rowingDeviceId = 'rowing_device_id';
  static const rowingDeviceName = 'rowing_device_name';
  static const rowingDemoMode = 'rowing_demo_mode';
  static const rowingCueSound = 'rowing_cue_sound';
}

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(AppDatabase.instance),
);

final ownedEquipmentProvider = FutureProvider<Set<String>>(
  (ref) => ref.watch(settingsRepositoryProvider).ownedEquipment(),
);

final defaultRestBetweenSetsProvider = FutureProvider<int>(
  (ref) => ref.watch(settingsRepositoryProvider).restBetweenSets(),
);

final defaultRestAfterExerciseProvider = FutureProvider<int>(
  (ref) => ref.watch(settingsRepositoryProvider).restAfterExercise(),
);

final restTimerSoundProvider = FutureProvider<bool>(
  (ref) => ref
      .watch(settingsRepositoryProvider)
      .getBool(SettingsKeys.restTimerSound, true),
);

final autoProgressionProvider = FutureProvider<bool>(
  (ref) => ref.watch(settingsRepositoryProvider).autoProgression(),
);

final warmupSuggestionsProvider = FutureProvider<bool>(
  (ref) => ref.watch(settingsRepositoryProvider).warmupSuggestions(),
);
