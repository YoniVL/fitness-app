import 'package:flutter/material.dart';

/// A consistent spacing scale — use these instead of ad-hoc SizedBox values.
abstract class Gap {
  static const xs = SizedBox(height: 4, width: 4);
  static const s = SizedBox(height: 8, width: 8);
  static const m = SizedBox(height: 12, width: 12);
  static const l = SizedBox(height: 16, width: 16);
  static const xl = SizedBox(height: 24, width: 24);
}

/// Material 3 light + dark themes from a single seed colour.
class AppTheme {
  static const _seed = Color(0xFF2E7D32); // fitness green
  static const _headingFont = 'Barlow';

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final heading = TextStyle(fontFamily: _headingFont, fontWeight: FontWeight.w700);
    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
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
