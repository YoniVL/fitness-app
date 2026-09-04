import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/database/app_database.dart';

/// Back-up / restore of the whole local database as a single `.db` file.
class Backup {
  Backup._();

  /// Copies the live database to a temp file and opens the share sheet.
  static Future<void> export() async {
    final src = await AppDatabase.instance.filePath();
    final stamp = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final tmpDir = await getTemporaryDirectory();
    final dst = p.join(tmpDir.path, 'cadans-backup-$stamp.db');

    // Checkpoint any WAL data into the main file before copying.
    final db = await AppDatabase.instance.database;
    try {
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}

    await File(src).copy(dst);
    await Share.shareXFiles(
      [XFile(dst)],
      subject: 'Cadans back-up',
    );
  }

  /// Lets the user pick a `.db` file and replaces the current database with it.
  /// Returns true when a file was imported (the app should then restart or
  /// invalidate its providers).
  static Future<bool> import() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: false,
    );
    final path = picked?.files.single.path;
    if (path == null) return false;

    // Cheap sanity check: SQLite files start with "SQLite format 3\0".
    final header = await File(path).openRead(0, 16).first;
    if (String.fromCharCodes(header).startsWith('SQLite format 3')) {
      // ok
    } else {
      throw const FormatException('Geen geldig databasebestand.');
    }

    final dst = await AppDatabase.instance.filePath();
    await AppDatabase.instance.close();
    try {
      await File('$dst-wal').delete();
    } catch (_) {}
    try {
      await File('$dst-shm').delete();
    } catch (_) {}
    await File(path).copy(dst);
    // Reopen (runs onUpgrade if the imported file is an older schema).
    await AppDatabase.instance.database;
    debugPrint('[Backup] imported $path');
    return true;
  }

  /// Wipes everything: deletes the database file so it is recreated + reseeded
  /// from scratch (empty log, no own programs, default settings).
  static Future<void> factoryReset() async {
    final dst = await AppDatabase.instance.filePath();
    await AppDatabase.instance.close();
    for (final f in [dst, '$dst-wal', '$dst-shm']) {
      try {
        await File(f).delete();
      } catch (_) {}
    }
    await AppDatabase.instance.database; // onCreate + seedDatabase
    debugPrint('[Backup] factory reset');
  }
}
