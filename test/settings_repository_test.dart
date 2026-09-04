import 'package:fitnesstracker/data/database/app_database.dart';
import 'package:fitnesstracker/data/repositories/settings_repository.dart';
import 'package:fitnesstracker/domain/models/program.dart';
import 'package:fitnesstracker/domain/rowing_ftp.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  late SettingsRepository repo;

  setUp(() async {
    await initTestDatabase();
    repo = SettingsRepository(AppDatabase.instance);
  });
  tearDown(closeTestDatabase);

  test('defaults', () async {
    expect(await repo.autoProgression(), isTrue);
    expect(await repo.warmupSuggestions(), isFalse);
    expect(await repo.restBetweenSets(), 30);
    expect(await repo.restAfterExercise(), 60);
  });

  test('warmupSuggestions round-trips', () async {
    await repo.setBool(SettingsKeys.warmupSuggestions, true);
    expect(await repo.warmupSuggestions(), isTrue);
  });

  test('rowingLevel defaults to medium and round-trips', () async {
    expect(await repo.rowingLevel(), ProgramLevel.medium);
    await repo.setRowingLevel(ProgramLevel.advanced);
    expect(await repo.rowingLevel(), ProgramLevel.advanced);
  });

  test('rowing FTP round-trips and clears', () async {
    expect(await repo.rowingFtp(), isNull);
    final ftp = RowingFtp(
        watts: 214, setAt: DateTime(2026, 9, 1), source: FtpSource.test20);
    await repo.setRowingFtp(ftp);
    final read = await repo.rowingFtp();
    expect(read!.watts, 214);
    expect(read.source, FtpSource.test20);
    await repo.clearRowingFtp();
    expect(await repo.rowingFtp(), isNull);
  });

  test('FTP history keeps entries in date order', () async {
    expect(await repo.ftpHistory(), isEmpty);
    await repo.appendFtpHistory(RowingFtp(
        watts: 200, setAt: DateTime(2026, 8, 1), source: FtpSource.manual));
    await repo.appendFtpHistory(RowingFtp(
        watts: 210, setAt: DateTime(2026, 7, 1), source: FtpSource.test20));
    final h = await repo.ftpHistory();
    expect(h.map((f) => f.watts).toList(), [210, 200]); // Jul before Aug
  });

  test('rowing achievements: merge never overwrites an existing unlock date',
      () async {
    expect(await repo.rowingAchievementsUnlocked(), isEmpty);
    expect(await repo.rowingAchievementsSeeded(), isFalse);

    final first = DateTime(2026, 1, 1);
    await repo.unlockRowingAchievements({'a': first, 'b': DateTime(2026, 1, 2)});
    await repo.unlockRowingAchievements(
        {'a': DateTime(2026, 6, 1), 'c': DateTime(2026, 6, 1)});

    final map = await repo.rowingAchievementsUnlocked();
    expect(map.keys.toSet(), {'a', 'b', 'c'});
    expect(map['a'], first); // not overwritten

    await repo.markRowingAchievementsSeeded();
    expect(await repo.rowingAchievementsSeeded(), isTrue);
  });

  test('rowingDragK defaults to the generic constant and round-trips', () async {
    expect(await repo.rowingDragK(), kGeneric);
    await repo.setRowingDragK(3.15);
    expect(await repo.rowingDragK(), closeTo(3.15, 0.001));
    await repo.setRowingDragK(999); // out of range → ignored on read
    expect(await repo.rowingDragK(), kGeneric);
  });
}
