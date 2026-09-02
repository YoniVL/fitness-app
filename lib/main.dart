import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'data/database/app_database.dart';
import 'features/rowing/state/active_rowing_provider.dart';
import 'features/strength/state/rest_timer_notifier.dart';
import 'services/rest_foreground_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  RestForegroundService.instance.init();
  await initializeDateFormatting('nl');
  // Route all app audio (the rest-timer beeps) to the alarm stream so it is
  // audible even when the phone is on vibrate.
  AudioPlayer.global
      .setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: false,
          stayAwake: true,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.alarm,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {},
        ),
      ))
      .catchError((_) {});
  // Open (and, first run, create + seed) the local database up front so the
  // first screen doesn't flash a loader.
  await AppDatabase.instance.database;
  runApp(const ProviderScope(child: FitnessApp()));
}

class FitnessApp extends ConsumerStatefulWidget {
  const FitnessApp({super.key});

  @override
  ConsumerState<FitnessApp> createState() => _FitnessAppState();
}

class _FitnessAppState extends ConsumerState<FitnessApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final here = appRouter.routerDelegate.currentConfiguration.uri.path;

    // Coming back while a rest is counting down (e.g. tapped the "Rustpauze"
    // notification) → land on the workout, not wherever the app last was.
    if (ref.read(restTimerProvider).active) {
      if (here != '/workout/active') appRouter.go('/workout/active');
      return;
    }
    // Coming back mid-row → land on the live rowing screen.
    if (ref.read(activeRowingProvider).valueOrNull != null &&
        here != '/rowing/active') {
      appRouter.go('/rowing/active');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Fitness Tracker',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
    );
  }
}
