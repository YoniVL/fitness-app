import 'package:go_router/go_router.dart';

import '../domain/models/program.dart';
import '../features/home/discipline_chooser_screen.dart';
import '../features/library/exercise_list_screen.dart';
import '../features/library/library_screen.dart';
import '../features/library/program_detail_screen.dart';
import '../features/log/log_screen.dart';
import '../features/log/session_detail_screen.dart';
import '../features/program_builder/builder_screen.dart';
import '../features/program_builder/program_editor_screen.dart';
import '../features/progress/progress_screen.dart';
import '../features/rowing/ftp_result_screen.dart';
import '../features/rowing/ftp_screen.dart';
import '../features/rowing/ramp_test_screen.dart';
import '../features/rowing/rowing_active_screen.dart';
import '../features/rowing/rowing_builder_screen.dart';
import '../features/rowing/workout_library_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/strength/active_workout_screen.dart';
import '../features/today/today_screen.dart';
import 'home_shell.dart';

/// The three-tab shell for one discipline. [prefix] is `/strength` or `/rowing`.
StatefulShellRoute _disciplineShell(Discipline discipline) {
  final prefix = discipline == Discipline.rowing ? '/rowing' : '/strength';
  return StatefulShellRoute.indexedStack(
    builder: (context, state, navigationShell) =>
        HomeShell(navigationShell: navigationShell, discipline: discipline),
    branches: [
      StatefulShellBranch(routes: [
        GoRoute(
          path: '$prefix/today',
          builder: (context, state) => TodayScreen(discipline: discipline),
        ),
      ]),
      StatefulShellBranch(routes: [
        GoRoute(
          path: '$prefix/library',
          builder: (context, state) => LibraryScreen(discipline: discipline),
          routes: [
            if (discipline == Discipline.strength)
              GoRoute(
                path: 'exercises',
                builder: (context, state) => const ExerciseListScreen(),
              ),
            if (discipline == Discipline.rowing)
              GoRoute(
                path: 'workouts',
                builder: (context, state) => const WorkoutLibraryScreen(),
              ),
            GoRoute(
              path: 'program/:id',
              builder: (context, state) => ProgramDetailScreen(
                programId: int.parse(state.pathParameters['id']!),
              ),
              routes: [
                GoRoute(
                  path: 'edit',
                  builder: (context, state) => ProgramEditorScreen(
                    programId: int.parse(state.pathParameters['id']!),
                  ),
                ),
              ],
            ),
          ],
        ),
      ]),
      StatefulShellBranch(routes: [
        GoRoute(
          path: '$prefix/log',
          builder: (context, state) => LogScreen(discipline: discipline),
          routes: [
            GoRoute(
              path: 'progress',
              builder: (context, state) =>
                  ProgressScreen(discipline: discipline),
            ),
            GoRoute(
              path: 'session/:id',
              builder: (context, state) => SessionDetailScreen(
                sessionId: int.parse(state.pathParameters['id']!),
              ),
            ),
          ],
        ),
      ]),
    ],
  );
}

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const DisciplineChooserScreen(),
    ),
    _disciplineShell(Discipline.strength),
    _disciplineShell(Discipline.rowing),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/program/builder',
      builder: (context, state) => const BuilderScreen(),
    ),
    GoRoute(
      path: '/rowing/builder',
      builder: (context, state) => const RowingBuilderScreen(),
    ),
    GoRoute(
      path: '/rowing/ftp',
      builder: (context, state) => const FtpScreen(),
    ),
    GoRoute(
      path: '/rowing/ftp/result/:id',
      builder: (context, state) => FtpResultScreen(
        sessionId: int.parse(state.pathParameters['id']!),
      ),
    ),
    GoRoute(
      path: '/rowing/ramp-test',
      builder: (context, state) => const RampTestScreen(),
    ),
    GoRoute(
      path: '/workout/active',
      builder: (context, state) => const ActiveWorkoutScreen(),
    ),
    GoRoute(
      path: '/rowing/active',
      builder: (context, state) => const RowingActiveScreen(),
    ),
  ],
);
