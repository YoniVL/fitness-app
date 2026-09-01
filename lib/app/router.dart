import 'package:go_router/go_router.dart';

import '../features/library/exercise_list_screen.dart';
import '../features/library/library_screen.dart';
import '../features/library/program_detail_screen.dart';
import '../features/log/log_screen.dart';
import '../features/log/session_detail_screen.dart';
import '../features/program_builder/builder_screen.dart';
import '../features/program_builder/program_editor_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/strength/active_workout_screen.dart';
import '../features/today/today_screen.dart';
import 'home_shell.dart';

final appRouter = GoRouter(
  initialLocation: '/today',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          HomeShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/today',
              builder: (context, state) => const TodayScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/library',
              builder: (context, state) => const LibraryScreen(),
              routes: [
                GoRoute(
                  path: 'exercises',
                  builder: (context, state) => const ExerciseListScreen(),
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
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/log',
              builder: (context, state) => const LogScreen(),
              routes: [
                GoRoute(
                  path: 'session/:id',
                  builder: (context, state) => SessionDetailScreen(
                    sessionId: int.parse(state.pathParameters['id']!),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/program/builder',
      builder: (context, state) => const BuilderScreen(),
    ),
    GoRoute(
      path: '/workout/active',
      builder: (context, state) => const ActiveWorkoutScreen(),
    ),
  ],
);
