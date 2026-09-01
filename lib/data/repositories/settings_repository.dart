import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';

/// Thin key/value access over the `app_settings` table.
class SettingsRepository {
  SettingsRepository(this._appDb);

  final AppDatabase _appDb;

  Future<String?> getString(String key) async {
    final db = await _appDb.database;
    final rows =
        await db.query('app_settings', where: 'key = ?', whereArgs: [key], limit: 1);
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
  Future<void> setBool(String key, bool value) => set(key, value ? 'true' : 'false');
}

class SettingsKeys {
  static const defaultRestSeconds = 'default_rest_seconds';
  static const restTimerSound = 'rest_timer_sound';
  static const weeklySchedule = 'weekly_schedule';
}

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(AppDatabase.instance),
);

/// Default rest duration between sets (seconds), user-configurable.
final defaultRestSecondsProvider = FutureProvider<int>(
  (ref) => ref.watch(settingsRepositoryProvider).getInt(SettingsKeys.defaultRestSeconds, 120),
);
