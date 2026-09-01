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
- **Iteratie 1 klaar**: krachtsessie loggen, pauzetimer, logboek. Elke set direct
  gepersisteerd; sessie hervat na herstart.
- **Iteratie 2a klaar** (schema v2): equipment-tags + bewegingspatronen op
  oefeningen; niveaus + materiaal-filter op programma's; **generator**
  (`lib/features/program_builder/program_generator.dart`, pure logica);
  **actief programma + dag-cursor** (`program_progress`); geen gewicht meer in de
  UI; **dubbele rusttijd** (tussen sets / na oefening, ±15s); geleide
  stap-voor-stap flow + **dagsamenvatting** met spierchips; instellingenscherm.
  v1→v2 migratie doet een **volledige data-reset** behalve `app_settings`.
- Schema v3: `exercises.is_unilateral`. Schema v4: oefeningen hernoemd naar
  canoniek Engels (`Barbell bench press`, `Dumbbell incline press`, …); rename-map
  in `seed_data.dart` (`exerciseRenamesV3toV4`).
- Builder-editor: gegenereerde dagen zijn tikbaar → sheet met slepen om te
  herschikken, sets/reps, oefening verwijderen/vervangen/toevoegen (nog vóór
  opslaan). Rusttijden per oefening bewerken = nog niet (iteratie 2b).
- Rust = fullscreen (`rest_fullscreen.dart`) voor elke rust, met aftel-piep de
  laatste 5s (`assets/audio/beep*.wav`, audioplayers, key `rest_timer_sound`) +
  demofoto van de volgende oefening.
- **Trainingsflow = pager** (`active_workout_screen.dart`): één oefening per
  (bijna) fullscreen `PageView`-pagina (naam, demofoto, gedane sets, reps-stepper,
  "Klaar"). Set gedaan → fullscreen rustklok → na de rust springt de pager auto
  naar de eerstvolgende onafgewerkte oefening (`ref.listen(restTimerProvider)`).
  Lijst-icoon = overzicht/springen/oefening toevoegen. Alles klaar → "Dag afronden".
- **Iteratie 2b klaar**: programma-editor (`program_editor_screen.dart` +
  `program_editor_widgets.dart`, gedeeld met de builder). Potlood op elk
  krachtprogramma → dagen/oefeningen/sets/reps/rust bewerken, herschikken,
  hernoemen, dag toevoegen/verwijderen. Vast schema → fork ("Opslaan als eigen
  schema"); eigen schema → in-place (`updateProgramContent`). Eigen schema's
  verwijderbaar via `...`-menu.
- **Voortgang** (`features/progress/progress_screen.dart`, grafiek-icoon in
  Logboek): sets/week (fl_chart bar), sets/spiergroep 30d, beste set per oefening
  over tijd (line). Reps/sets-gebaseerd.
- **Oefening-demo's** (`features/exercises/exercise_media.dart`): 2 gebundelde
  foto's per oefening (start/eind), langzame cross-fade = de beweging
  (`ExerciseDemo`). ~63 oefeningen gemapt in `_photoSlugs`; assets in
  `assets/exercise_media/<slug>_{0,1}.jpg` (~3,8 MB, downscaled naar 560px).
  Bron: everkinetic via github.com/yuhonas/free-exercise-db, **CC BY-SA 3.0** —
  bronvermelding staat in Instellingen › Credits (moet blijven staan). Oefeningen
  zonder foto: geen demo (fallback = dumbbell-icoon in de pager). Eerdere
  zelf-getekende stick-figuur/silhouet-pogingen zijn verworpen en verwijderd.
- **Roeien/BLE**: alleen schema + `lib/features/rowing/ble/ftms_rower_service.dart`
  stub. UI = latere iteratie — het grootste openstaande stuk.
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
