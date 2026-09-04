import 'package:flutter/material.dart';

/// A consistent spacing scale — use these instead of ad-hoc SizedBox values.
abstract class Gap {
  static const xs = SizedBox(height: 4, width: 4);
  static const s = SizedBox(height: 8, width: 8);
  static const m = SizedBox(height: 12, width: 12);
  static const l = SizedBox(height: 16, width: 16);
  static const xl = SizedBox(height: 24, width: 24);
}

/// The training-intensity ramp (easy → max effort) used across the rowing
/// segment (interval profiles, live-screen cues, ramp-test indicator). One
/// source, read via `Theme.of(context).extension<RowZonePalette>()`.
class RowZonePalette extends ThemeExtension<RowZonePalette> {
  const RowZonePalette({
    required this.rest,
    required this.easy,
    required this.steady,
    required this.threshold,
    required this.hard,
    required this.max,
  });

  final Color rest;
  final Color easy;
  final Color steady;
  final Color threshold;
  final Color hard;
  final Color max;

  /// Same ramp in light and dark — the hues are already saturated/dark enough
  /// to read against both surface tones.
  static const RowZonePalette standard = RowZonePalette(
    rest: Color(0xFF9E9E9E),
    easy: Color(0xFF64B5F6),
    steady: Color(0xFF66BB6A),
    threshold: Color(0xFFFFCA28),
    hard: Color(0xFFFF7043),
    max: Color(0xFFEF5350),
  );

  @override
  RowZonePalette copyWith({
    Color? rest,
    Color? easy,
    Color? steady,
    Color? threshold,
    Color? hard,
    Color? max,
  }) =>
      RowZonePalette(
        rest: rest ?? this.rest,
        easy: easy ?? this.easy,
        steady: steady ?? this.steady,
        threshold: threshold ?? this.threshold,
        hard: hard ?? this.hard,
        max: max ?? this.max,
      );

  @override
  RowZonePalette lerp(ThemeExtension<RowZonePalette>? other, double t) {
    if (other is! RowZonePalette) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return RowZonePalette(
      rest: c(rest, other.rest),
      easy: c(easy, other.easy),
      steady: c(steady, other.steady),
      threshold: c(threshold, other.threshold),
      hard: c(hard, other.hard),
      max: c(max, other.max),
    );
  }
}

/// Material 3 light + dark themes from a single seed colour.
class AppTheme {
  static const seed = Color(0xFF2E7D32); // Cadans green — matches the app icon
  static const _headingFont = 'Barlow';

  // "Verzadigd" — chosen on-device via /dev/theme (fase 2 of iteration 9).
  static const _defaultVariant = DynamicSchemeVariant.fidelity;

  static ThemeData light({DynamicSchemeVariant variant = _defaultVariant}) =>
      _base(Brightness.light, variant);
  static ThemeData dark({DynamicSchemeVariant variant = _defaultVariant}) =>
      _base(Brightness.dark, variant);

  static ThemeData _base(Brightness brightness, DynamicSchemeVariant variant) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      dynamicSchemeVariant: variant,
    );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final heading = TextStyle(fontFamily: _headingFont, fontWeight: FontWeight.w700);
    return base.copyWith(
      visualDensity: VisualDensity.standard,
      scaffoldBackgroundColor: scheme.surface,
      extensions: const [RowZonePalette.standard],
      textTheme: base.textTheme.copyWith(
        displaySmall: base.textTheme.displaySmall?.merge(heading),
        headlineMedium: base.textTheme.headlineMedium?.merge(heading),
        headlineSmall: base.textTheme.headlineSmall?.merge(heading),
        titleLarge: base.textTheme.titleLarge?.merge(heading),
        titleMedium: base.textTheme.titleMedium
            ?.merge(TextStyle(fontFamily: _headingFont, fontWeight: FontWeight.w600)),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontFamily: _headingFont,
          fontWeight: FontWeight.w700,
          fontSize: 22,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerHigh,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.6),
        space: 1,
        thickness: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        selectedColor: scheme.secondaryContainer,
        labelStyle: TextStyle(color: scheme.onSurface, fontSize: 13),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        shape: const StadiumBorder(),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.secondaryContainer,
        elevation: 0,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(visualDensity: VisualDensity.standard),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: scheme.surfaceContainerHighest,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // Height floor only. Do NOT use Size.fromHeight here: that sets the
          // minimum *width* to infinity, which breaks any FilledButton placed
          // in a Row. Full-width buttons opt in via a stretched parent.
          minimumSize: const Size(0, 48),
          textStyle: const TextStyle(
              fontFamily: _headingFont,
              fontSize: 16,
              fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          side: BorderSide(color: scheme.outline),
          textStyle: const TextStyle(
              fontFamily: _headingFont,
              fontSize: 16,
              fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(
              fontFamily: _headingFont, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// Standard screen-section heading.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.padding});
  final String text;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding ?? const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}
