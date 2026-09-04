import 'package:fitnesstracker/data/database/app_database.dart';
import 'package:fitnesstracker/data/repositories/settings_repository.dart';
import 'package:fitnesstracker/domain/models/program.dart';
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
}
