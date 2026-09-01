# Fitness Tracker — Claude notes

Native Android app (Flutter) voor krachttraining + roeitraining. Lokale opslag,
geen cloud/accounts. Live BLE-koppeling met een FTMS-roeitrainer (later).

## Stack
- Flutter 3.47 / Dart 3.13, `flutter_riverpod` (v2, geen codegen), `sqflite`,
  `go_router` (StatefulShellRoute, 3 tabs), `fl_chart`, `flutter_ftms`.
- SDK op `C:\src\flutter`; Android SDK op `%LOCALAPPDATA%\Android\Sdk`; JDK 17.
- Toestel: Samsung SM-S938B (`RZCY30HVGJF`), Android 16.

## Architectuur
- `lib/domain/models/` — plain Dart models met `fromMap`/`toMap`.
- `lib/data/database/app_database.dart` — sqflite singleton, schema v1 **volledig**
  aangelegd in `onCreate` (ook roei-/programmatabellen) + `seed_data.dart`.
  Test-hook: `AppDatabase.instance.openAt(inMemoryDatabasePath, factory: ...)`.
- `lib/data/repositories/` — elk met een Riverpod `Provider`; repos gebruiken
  `AppDatabase.instance` direct.
- `lib/features/<feature>/` — schermen + `state/` notifiers.

## Status
- **Iteratie 1 klaar**: krachtsessie loggen (template of leeg, per-sessie doelen
  overschrijven, sets/reps/gewicht, pauzetimer, logboek + sessiedetail).
  Elke set direct gepersisteerd; sessie hervat na herstart.
- **Roeien/BLE**: alleen schema + `lib/features/rowing/ble/ftms_rower_service.dart`
  stub met de bevestigde FTMS-specs. UI = volgende iteratie.
- Plan: `C:\Users\figo_\.claude\plans\soft-leaping-goblet.md`.

## Valkuilen (echt gebeurd)
- **Niet in OneDrive zetten.** Project stond in `OneDrive\...\Fitnessapp`; OneDrive
  + achtergebleven Gradle/Kotlin-daemons locken `build/` → `Unable to delete
  directory`. Verplaatst naar `C:\dev\Fitnessapp`. Oude map mag weg.
- `flutter build` draait een `build.gradle.kts`-migratie die handmatige
  `minSdk`/`ndkVersion`-edits terugzet naar de Flutter-defaults. Defaults volstaan
  voorlopig.
- **Buttonthema nooit `Size.fromHeight` gebruiken**: dat zet min-breedte op
  oneindig → een `FilledButton` in een `Row` klapt z'n parent naar hoogte 0
  (geen foutmelding). Gebruik `Size(0, 48)` en zet volle-breedte knoppen in een
  gestrekte parent.
- `sqflite_common_ffi` voltooit niet binnen de `testWidgets` async-zone → widget-
  tests van DB-gedreven schermen gebruiken een fake notifier (zie
  `test/active_workout_screen_test.dart`).
- `adb screencap` geeft met Impeller/Vulkan soms zwarte frames — niet vertrouwen
  op één screenshot om een render-bug te bevestigen.

## Commando's
```
cd C:\dev\Fitnessapp
C:\src\flutter\bin\flutter.exe run          # of: flutter test / flutter analyze
C:\src\flutter\bin\flutter.exe build apk --debug
adb -s RZCY30HVGJF install -r build\app\outputs\flutter-apk\app-debug.apk
```
