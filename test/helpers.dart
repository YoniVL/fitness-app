import 'package:fitnesstracker/data/database/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Opens a fresh in-memory database as the [AppDatabase] singleton, running the
/// full `onCreate` (schema + seed). Call [closeTestDatabase] in tearDown.
Future<void> initTestDatabase() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  await AppDatabase.instance.close();
  await AppDatabase.instance.openAt(inMemoryDatabasePath, factory: databaseFactoryFfi);
}

Future<void> closeTestDatabase() => AppDatabase.instance.close();
