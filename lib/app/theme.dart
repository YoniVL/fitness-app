import 'package:flutter/material.dart';

/// Material 3 light + dark themes from a single seed colour.
class AppTheme {
  static const _seed = Color(0xFF2E7D32); // fitness green

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// Maps a muscle-group `icon_key` to an icon (placeholder for exercise media).
IconData muscleGroupIcon(String iconKey) {
  switch (iconKey) {
    case 'chest':
      return Icons.fitness_center;
    case 'back':
      return Icons.airline_seat_recline_normal;
    case 'legs':
      return Icons.directions_walk;
    case 'shoulders':
      return Icons.accessibility_new;
    case 'biceps':
      return Icons.sports_martial_arts;
    case 'triceps':
      return Icons.sports_handball;
    case 'core':
      return Icons.self_improvement;
    case 'glutes':
      return Icons.airline_seat_legroom_extra;
    case 'calves':
      return Icons.directions_run;
    default:
      return Icons.fitness_center;
  }
}
