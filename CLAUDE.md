# Fitness Tracker — Claude notes

Native Android app (Flutter) voor krachttraining + roeitraining. Lokale opslag,
geen cloud/accounts. Live BLE-koppeling met een FTMS-roeitrainer (later).

## Stack
- Flutter 3.47 / Dart 3.13, `flutter_riverpod` (v2, geen codegen), `sqflite`,
  `go_router`, `fl_chart`, `flutter_ftms`, `flutter_foreground_task`, `audioplayers`.
- SDK op `C:\src\flutter`; Android SDK op `%LOCALAPPDATA%\Android\Sdk`; JDK 17.
- Toestel: Samsung SM-S938B (`RZCY30HVGJF`), Android 16.
- **App vastgezet op portret** (`main()`); alleen `rowing_active_screen.dart`
  draait naar landscape.

## Navigatie (sinds iteratie 5·R1b)
- `initialLocation: '/'` → `DisciplineChooserScreen` (keuze Krachttraining / Roeien).
  **Niet gepersisteerd** — elke koude start toont het keuzescherm.
- Twee `StatefulShellRoute`s: `/strength/{today,library,log}` en
  `/rowing/{today,library,log}`, elk met eigen Vandaag/Bibliotheek/Logboek(+
  progress/session). `HomeShell(discipline:)` + `DisciplineSwitchButton` (⇄ → `/`).
- Top-level (geen bottom-nav): `/settings`, `/program/builder`, `/rowing/builder`,
  `/workout/active`, `/rowing/active`.
- Schermen krijgen `discipline` via de router; sessies gefilterd per onderdeel.

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
  (bijna) fullscreen `PageView`-pagina. Rustklok = overlay bovenop de pager
  (`Stack`, pager blijft gemount → verliest z'n pagina niet). Na de rust:
  alleen vooruit naar de eerstvolgende onafgewerkte oefening vanaf je huidige
  pagina, nooit terug (`_forwardTarget`). Lijst-icoon = overzicht-sheet
  (scrollbaar, sleep-herschikken via `moveBlock`, springen, oefening toevoegen).
- **Iteratie 3 klaar** (commits a48713d…ff51f15):
  - *3a*: "Vorige keer: 9·8·8" (`lastPerformanceProvider`); rusttimer draait
    tijdens de rust in een **voorgrond-service** (`flutter_foreground_task`,
    `services/rest_foreground_service.dart`) → teller loopt door + piep hoorbaar
    op de achtergrond (alarm-stream, global `AudioContext` in `main.dart`).
    Notificatie toont de resttijd; erop tikken opent de klok
    (lifecycle-observer in `FitnessApp`). Handmatige "Pauze"-knop; oefening
    vervangen (`replaceBlock`, ⇄); notitieveld bij "Dag afronden" + potlood in
    het sessiedetail (`updateNotes`, raakt `ended_at` niet).
    **flutter_local_notifications is bewust weer verwijderd** (Samsung blokte
    achtergrond-audiofocus — daarom de FG-service).
  - *3b*: `lib/domain/progression.dart` `progressTargets()` — +1 rep/ronde tot
    +3, dan +1 set (plateau ronde 9). Toegepast in
    `active_workout_provider` (`startFromDay`/`_rehydrate`) o.b.v.
    `program_progress.round`; `ExerciseBlock.baseTarget*` → `isProgressed`.
    Setting `auto_progression` (aan). Opwarmset-tip + vinkje voor compounds
    (`ExerciseBlock.suggestsWarmup`).
  - *3c*: rode "materiaal ontbreekt"-regel; **back-up** (`features/settings/
    backup.dart`, share_plus + file_picker + path_provider — hele `.db`
    exporteren/importeren); PR-lijst + streak-kaart op Voortgang.
- **Iteratie 4 klaar** (d664fed, c43ad08):
  - *4a*: Instellingen › Back-up › "Alle gegevens wissen" (`Backup.factoryReset()`);
    opwarmset-tip is nu een setting (`warmup_suggestions`, **standaard uit**).
  - *4b*: **Barlow**-koplettertype (`assets/fonts/`, OFL); kaarten opaak +
    outline; `SectionHeader` + `Gap` in `theme.dart`; `movementPatternIcon()`
    i.p.v. de weggehaalde `muscleGroupIcon`; Vandaag-scherm gevuld (datum,
    week-strook, dag-oefeningen); oefeningpagina-header opgeschoond (⇄ + ⋮);
    Voortgang-secties in kaarten; Logboek dempt/verwijdert onafgeronde sessies.
  - Thema-/kleurkeuze bewust NIET gedaan → aparte afwerkings-iteratie.
- **Iteratie 2b klaar**: programma-editor (`program_editor_screen.dart` +
  `program_editor_widgets.dart`, gedeeld met de builder). Potlood op elk
  krachtprogramma → dagen/oefeningen/sets/reps/rust bewerken, herschikken,
  hernoemen, dag toevoegen/verwijderen. Vast schema → fork ("Opslaan als eigen
  schema"); eigen schema → in-place (`updateProgramContent`). Eigen schema's
  verwijderbaar via `...`-menu.
- **Voortgang** (`features/progress/progress_screen.dart`, grafiek-icoon in
  Logboek): streak-kaart, sets/week (fl_chart bar), sets/spiergroep 30d, beste
  set per oefening over tijd (line), persoonlijke records. Reps/sets-gebaseerd.
- **Oefening-demo's** (`features/exercises/exercise_media.dart`): 2 gebundelde
  foto's per oefening (start/eind). In de oefeningenlijst = kleine ronde
  fotothumbnail (`ExerciseThumb`, per oefening het duidelijkste frame via
  `_thumbUsesStartFrame`); in het detail = trage cross-fade (`ExerciseDemo`).
  63 oefeningen in `_photoSlugs`; assets `assets/exercise_media/<slug>_{0,1}.jpg`.
  Bron: everkinetic via github.com/yuhonas/free-exercise-db, **CC BY-SA 3.0** —
  bronvermelding in Instellingen › Credits (moet blijven staan). De
  `movementPatternIcon()`/`muscleGroupStyle()`-iconen zijn verwijderd.
- **Iteratie 5 — Roeien** (in uitvoering, commits vanaf `058b10d`):
  - *R0*: `rowing_repository.dart` + `rowing_format.dart`; roeisessie handmatig
    loggen (`log_rowing_sheet.dart`); roei-sessiedetail met tempografiek.
  - *R1*: roeiplan-generator + `rowing_builder_screen.dart`; schema v5
    (`program_row_segments.drill_key`, `programs.goal`).
  - *R2*: `rower_service.dart` (`RowerService` + `FakeRowerService` sim),
    `active_rowing_provider.dart`, `rowing_active_screen.dart` (`/rowing/active`);
    apart roei-slot (`activeRowingProgramProvider`, `advanceRowingIfCurrentDay`,
    `SettingsKeys.activeRowingProgramId`).
  - *R1b*: app-split (zie Navigatie hierboven).
  - *R2b*: **workout-catalogus** `lib/domain/rowing_workouts.dart` (~40 benoemde
    workouts: `RowWorkout`/`RowBlock`/`RowIntensity`); de generator trekt hieruit;
    sessieduur = meerkeuze-banden (`RowingPlanInput.bands`, incl. 45–60);
    ~12 preset-plannen; "Duurloop" → **"Endurance"**. Bladerbaar:
    `workout_library_screen.dart` (`/rowing/library/workouts`). Schema **v6** =
    roeisjablonen herseeden.
  - *R2c*: `interval_profile.dart` (blokjes: breedte=duur, hoogte/kleur=
    slagtempo/zone) + `week_load_chart.dart` (balk per week) in builder-preview,
    plan-detail, workout-detail, live-scherm.
  - *R2d*: `rowing_active_screen.dart` = **landscape** (`SystemChrome` in
    init/dispose); cijfers links groot, intervalprofiel + segmentbanner rechts.
  - *R4*: roei-`progress_screen.dart` (`_RowingProgress`): 30-dagen-totalen,
    afstand/week (bar), gem. tempo per sessie (line), roei-streak. Queries +
    providers in `rowing_repository.dart` (`weeklyDistance`, `paceHistory`,
    `weekStreak`, `totalsSince`; `rowingProgressProviders` om te invalideren na
    loggen). Roei-Vandaag week-strook toont sessies + afstand. Roei-sessiedetail
    (`session_detail_screen.dart`): "Geplande sessie" = `IntervalProfile` van
    `RowingSessionDetail.planSegments` + segmenttekst; sub-grafieken Slagtempo
    (`stroke_rate`) en Hartslag (`heart_rate`) naast de tempo-grafiek.
  - *R5a*: generator **geperiodiseerd** (`rowing_plan_generator.dart`): weektypes
    roteren (anker + roterende pool, geen dubbele type/week), buildcurve week 1
    → piek ~80 % → taper, deloadweek elke 4e (≥ 8 wk), sessielengte volgt de
    curve (`_targetMinutes`), benchmark-**testsessie** in week 1 + laatste week
    (`RowSessionType.test`). Volume wordt **wekelijks** gebudgetteerd: herstel/
    test hebben een vaste lengte → afgetrokken, de rest verdeeld over de "flex"-
    sessies + één correctiepass; herstel wordt endurance in zware weken. Zo volgt
    de weekbalkgrafiek de curve i.p.v. te zagen met de rotatie. Catalogus +8
    langere workouts + 5 testworkouts.
    Schema **v7**: `program_days.row_session_type`,
    `program_row_segments.zone` (intensiteit los van rauwe spm — endurance blijft
    groen), `rowing_sessions.{segments_json,kind,active_elapsed_ms}`, reseed.
  - *R5b*: live-scherm — `rowing_cues.dart` (piep 10 s vóór + bij elke
    segmentwissel, gegate op `SettingsKeys.rowingCueSound`; **enkel piep**, geen
    trilling/notificatie/achtergrondservice). `wakelock_plus` houdt het scherm
    aan; landscape herbevestigd op `resumed`. **Auto-pauze**: `PauseReason`
    `{none,user,idle,background}` — `idle` na 8 s geen trainerdata (hervat
    vanzelf bij nieuwe data), `background` bij app naar achtergrond
    (`main.dart` `didChangeAppLifecycleState`, hervat handmatig). Marker op het
    profiel volgt de segmentcursor (`ActiveRowingState.segmentProgressFraction`).
    HR als grote stat; "Laatste blok" i.p.v. "Sessie afronden".
    `FakeRowerService` valt elke ~45 s even stil voor de demo.
  - *R5c*: een losse catalogus-workout (`startWorkout`) bewaart z'n segmenten als
    JSON in `rowing_sessions.segments_json` → structuur overleeft app-kill.
    `active_elapsed_ms` wordt elke 10 s weggeschreven zodat een rehydrate niet
    de tijd-weg meetelt. `finish()` neemt `max(live, verste sample)` voor
    afstand/energie en middelt alleen `> 0`-waarden.
    `RowingSessionDetail.planSegments` leest ook uit `segments_json`.
  - *R5d*: Voortgang — tempo-trend met filter Rustig/Interval/Alles
    (`rowingPaceHistoryProvider` is nu een `.family<Set<String>?>`); sectie
    **Testen** (`benchmarkHistory` → 500/2000/5000 m, tijd-over-tijd + PR-chip).
    Handmatig loggen: "Soort"-dropdown (`kind`) + datum/tijd-kiezer (`when`).
  - *R5e*: `workout_library_screen.dart` = typefilter-chips + mini-`IntervalProfile`
    per rij. Roei-Vandaag-dagkaart toont het dagprofiel + type-chip
    (`ProgramDay.rowSessionType`). Builder dedupt de plannaam (` (2)` enz.).
    "1 blok" i.p.v. "1 blokken".
  - **R3 (BLE)** = nog te doen (op verzoek uitgesteld tot de rest zit):
    `flutter_ftms` echte koppeling. **Geen voorgrondservice** (bewuste keuze):
    sessie pauzeert bij achtergrond. Verificatie vereist de trainer (FS-057453).
- **Navigatie-valkuil**: go_router relatieve `context.push('foo')` bleek niet
  betrouwbaar te resolven binnen de shells → overal absolute paden
  (`/rowing/log/session/$id` enz.).
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
