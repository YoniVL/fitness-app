import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// Resolves the opened database. Repositories generally use
/// [AppDatabase.instance] directly and await `database` per call; this provider
/// is handy for widgets that need to gate on "db ready".
final databaseProvider = FutureProvider<Database>((ref) {
  return AppDatabase.instance.database;
});
