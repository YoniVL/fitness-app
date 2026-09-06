import 'package:flutter/material.dart';

import '../ui/shapes.dart';

/// Flat surface palette for the "Modernist" refresh — the bespoke tokens the
/// Material [ColorScheme] doesn't name cleanly. Read via
/// `Theme.of(context).extension<AppPalette>()!` (or the [context] getter below).
///
/// - [ground]  scaffold / bottom-nav / app-bar fill
/// - [surface] card fill (one step off the ground)
/// - [surfaceAlt] nested panels, hover, pressed
/// - [ink] / [mute] primary / secondary text
/// - [line] 1px hairlines inside a card
/// - [rule] 2px rules between major sections
/// - [accent] / [accentInk] the single accent and text that sits on it
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.ground,
    required this.surface,
    required this.surfaceAlt,
    required this.ink,
    required this.mute,
    required this.line,
    required this.rule,
    required this.accent,
    required this.accentInk,
  });

  final Color ground;
  final Color surface;
  final Color surfaceAlt;
  final Color ink;
  final Color mute;
  final Color line;
  final Color rule;
  final Color accent;
  final Color accentInk;

  static const dark = AppPalette(
    ground: Color(0xFF131211),
    surface: Color(0xFF1C1A19),
    surfaceAlt: Color(0xFF282524),
    ink: Color(0xFFF5F3F2),
    mute: Color(0xFF9C9795),
    line: Color(0xFF3A3635),
    rule: Color(0xFF5A5553),
    accent: Color(0xFFFF563C),
    accentInk: Color(0xFF131211),
  );

  static const light = AppPalette(
    ground: Color(0xFFF3F2F2),
    surface: Color(0xFFEAE9E9),
    surfaceAlt: Color(0xFFDEDCDC),
    ink: Color(0xFF201E1D),
    mute: Color(0xFF6F6B6A),
    line: Color(0xFFCBC7C7),
    rule: Color(0xFF403C3B),
    accent: Color(0xFFEC3013),
    accentInk: Color(0xFFF3F2F2),
  );

  @override
  AppPalette copyWith({
    Color? ground,
    Color? surface,
    Color? surfaceAlt,
    Color? ink,
    Color? mute,
    Color? line,
    Color? rule,
    Color? accent,
    Color? accentInk,
  }) =>
      AppPalette(
        ground: ground ?? this.ground,
        surface: surface ?? this.surface,
        surfaceAlt: surfaceAlt ?? this.surfaceAlt,
        ink: ink ?? this.ink,
        mute: mute ?? this.mute,
        line: line ?? this.line,
        rule: rule ?? this.rule,
        accent: accent ?? this.accent,
        accentInk: accentInk ?? this.accentInk,
      );

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      ground: c(ground, other.ground),
      surface: c(surface, other.surface),
      surfaceAlt: c(surfaceAlt, other.surfaceAlt),
      ink: c(ink, other.ink),
      mute: c(mute, other.mute),
      line: c(line, other.line),
      rule: c(rule, other.rule),
      accent: c(accent, other.accent),
      accentInk: c(accentInk, other.accentInk),
    );
  }
}

/// The training-intensity ramp (rest → max effort) used across the rowing
/// segment. Warm greys into the accent — read via
/// `Theme.of(context).extension<RowZonePalette>()`.
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

  static const dark = RowZonePalette(
    rest: Color(0xFF56514F),
    easy: Color(0xFF9C9795),
    steady: Color(0xFFFFC4B8),
    threshold: Color(0xFFFF9783),
    hard: Color(0xFFFF563C),
    max: Color(0xFFEC3013),
  );

  static const light = RowZonePalette(
    rest: Color(0xFFBAB6B6),
    easy: Color(0xFF9B9797),
    steady: Color(0xFFFF9783),
    threshold: Color(0xFFFF563C),
    hard: Color(0xFFEC3013),
    max: Color(0xFFAE1800),
  );

  /// Const fallback for pure functions that can't reach a [BuildContext].
  static const standard = dark;

  List<Color> get ramp => [rest, easy, steady, threshold, hard, max];

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

extension PaletteAccess on BuildContext {
  /// The Modernist palette. Falls back to a brightness-matched default when the
  /// theme carries no [AppPalette] extension (e.g. an isolated widget test).
  AppPalette get palette {
    final ext = Theme.of(this).extension<AppPalette>();
    if (ext != null) return ext;
    return Theme.of(this).brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
  }

  RowZonePalette get zones {
    final ext = Theme.of(this).extension<RowZonePalette>();
    if (ext != null) return ext;
    return Theme.of(this).brightness == Brightness.dark
        ? RowZonePalette.dark
        : RowZonePalette.light;
  }
}

/// Modernist: flat, architectural, set in Archivo. Zero corner radius, 2px
/// rules instead of elevation, one chamfered card corner, flush-left labels,
/// metrics in extra-bold tabular figures. Dark is the primary mode.
class AppTheme {
  static const fontFamily = 'Archivo';

  /// The card motif: square but for one sliced corner, top-right.
  static const cardShape = ChamferBorder(cut: 16);

  /// Extra-bold tabular figures with tight tracking — for the big numbers.
  static TextStyle numeric({
    required double size,
    Color? color,
    FontWeight weight = FontWeight.w900,
  }) =>
      TextStyle(
        fontFamily: fontFamily,
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: size * -0.04,
        height: 1.0,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final p = dark ? AppPalette.dark : AppPalette.light;
    final zones = dark ? RowZonePalette.dark : RowZonePalette.light;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: p.accent,
      onPrimary: p.accentInk,
      primaryContainer: p.accent,
      onPrimaryContainer: p.accentInk,
      secondary: p.ink,
      onSecondary: p.ground,
      secondaryContainer: p.surfaceAlt,
      onSecondaryContainer: p.ink,
      tertiary: p.accent,
      onTertiary: p.accentInk,
      error: zones.max,
      onError: p.accentInk,
      surface: p.ground,
      onSurface: p.ink,
      surfaceContainerLowest: p.ground,
      surfaceContainerLow: p.surface,
      surfaceContainer: p.surface,
      surfaceContainerHigh: p.surface,
      surfaceContainerHighest: p.surfaceAlt,
      surfaceDim: p.ground,
      surfaceBright: p.surfaceAlt,
      onSurfaceVariant: p.mute,
      outline: p.line,
      outlineVariant: p.line,
      inverseSurface: p.ink,
      onInverseSurface: p.ground,
      inversePrimary: p.accent,
      shadow: const Color(0xFF000000),
      scrim: const Color(0xFF000000),
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final t = base.textTheme;

    TextStyle head(TextStyle? s, double ls) => (s ?? const TextStyle()).copyWith(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w800,
          letterSpacing: ls,
          color: p.ink,
        );
    TextStyle body(TextStyle? s) => (s ?? const TextStyle()).copyWith(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w400,
          color: p.ink,
        );
    TextStyle label(TextStyle? s, FontWeight w) =>
        (s ?? const TextStyle()).copyWith(
          fontFamily: fontFamily,
          fontWeight: w,
          letterSpacing: 0.5,
        );

    final textTheme = t.copyWith(
      displayLarge: head(t.displayLarge, -2.0),
      displayMedium: head(t.displayMedium, -1.6),
      displaySmall: head(t.displaySmall, -1.2),
      headlineLarge: head(t.headlineLarge, -1.0),
      headlineMedium: head(t.headlineMedium, -0.8),
      headlineSmall: head(t.headlineSmall, -0.6),
      titleLarge: head(t.titleLarge, -0.3),
      titleMedium: (t.titleMedium ?? const TextStyle()).copyWith(
        fontFamily: fontFamily,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.1,
        color: p.ink,
      ),
      titleSmall: (t.titleSmall ?? const TextStyle()).copyWith(
        fontFamily: fontFamily,
        fontWeight: FontWeight.w700,
        color: p.ink,
      ),
      bodyLarge: body(t.bodyLarge),
      bodyMedium: body(t.bodyMedium),
      bodySmall: body(t.bodySmall).copyWith(color: p.mute),
      labelLarge: label(t.labelLarge, FontWeight.w800),
      labelMedium: label(t.labelMedium, FontWeight.w700).copyWith(color: p.mute),
      labelSmall: label(t.labelSmall, FontWeight.w700).copyWith(color: p.mute),
    );

    final squareButton = ButtonStyle(
      shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.zero)),
      alignment: Alignment.centerLeft,
      elevation: const WidgetStatePropertyAll(0),
      textStyle: WidgetStatePropertyAll(TextStyle(
        fontFamily: fontFamily,
        fontWeight: FontWeight.w800,
        fontSize: 14,
        letterSpacing: 0.4,
      )),
      minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
      padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
    );

    return base.copyWith(
      scaffoldBackgroundColor: p.ground,
      canvasColor: p.ground,
      visualDensity: VisualDensity.standard,
      splashFactory: InkRipple.splashFactory,
      extensions: [p, zones],
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        titleSpacing: 16,
        backgroundColor: p.ground,
        foregroundColor: p.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: Border(bottom: BorderSide(color: p.rule, width: 2)),
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w800,
          fontSize: 20,
          letterSpacing: -0.2,
          color: p.ink,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: cardShape,
        clipBehavior: Clip.antiAlias,
      ),
      dividerTheme: DividerThemeData(color: p.line, space: 1, thickness: 1),
      listTileTheme: ListTileThemeData(
        iconColor: p.mute,
        textColor: p.ink,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surface,
        selectedColor: p.accent,
        secondarySelectedColor: p.accent,
        checkmarkColor: p.accentInk,
        labelStyle: TextStyle(
          color: p.ink,
          fontFamily: fontFamily,
          fontWeight: FontWeight.w700,
          fontSize: 11,
          letterSpacing: 0.4,
        ),
        secondaryLabelStyle: TextStyle(color: p.accentInk, fontSize: 11),
        side: BorderSide(color: p.line),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.surfaceAlt,
        contentTextStyle: TextStyle(color: p.ink, fontFamily: fontFamily),
        actionTextColor: p.accent,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const ChamferBorder(cut: 16),
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w800,
          fontSize: 20,
          color: p.ink,
        ),
        contentTextStyle: TextStyle(
            fontFamily: fontFamily, fontSize: 14, color: p.ink),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        dragHandleColor: p.line,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.ground,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        indicatorShape:
            const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        elevation: 0,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            size: 22,
            color: s.contains(WidgetState.selected) ? p.accent : p.mute)),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
              fontFamily: fontFamily,
              fontSize: 10,
              fontWeight: s.contains(WidgetState.selected)
                  ? FontWeight.w800
                  : FontWeight.w600,
              letterSpacing: 0.3,
              color: s.contains(WidgetState.selected) ? p.accent : p.mute,
            )),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: p.surface,
          foregroundColor: p.ink,
          selectedBackgroundColor: p.accent,
          selectedForegroundColor: p.accentInk,
          side: BorderSide(color: p.line),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          visualDensity: VisualDensity.standard,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.accent,
        linearTrackColor: p.line,
        circularTrackColor: p.line,
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: p.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: p.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: p.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: p.accent, width: 2),
        ),
        labelStyle: TextStyle(color: p.mute, fontFamily: fontFamily),
        hintStyle: TextStyle(color: p.mute, fontFamily: fontFamily),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: squareButton.copyWith(
          backgroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.disabled)
                  ? p.surfaceAlt
                  : s.contains(WidgetState.pressed)
                      ? zones.max
                      : p.accent),
          foregroundColor: WidgetStatePropertyAll(p.accentInk),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: squareButton.copyWith(
          foregroundColor: WidgetStatePropertyAll(p.ink),
          side: WidgetStatePropertyAll(BorderSide(color: p.line)),
          overlayColor: WidgetStatePropertyAll(p.surfaceAlt),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: squareButton.copyWith(
          foregroundColor: WidgetStatePropertyAll(p.accent),
          minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
          padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 8)),
          alignment: Alignment.center,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: p.ink,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.accent,
        foregroundColor: p.accentInk,
        elevation: 6,
        focusElevation: 6,
        hoverElevation: 6,
        highlightElevation: 6,
        shape: const ChamferBorder(cut: 14),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: p.surfaceAlt),
        textStyle: TextStyle(color: p.ink, fontFamily: fontFamily, fontSize: 12),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        side: BorderSide(color: p.mute, width: 2),
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? p.accent : Colors.transparent),
        checkColor: WidgetStatePropertyAll(p.accentInk),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? p.accentInk : p.mute),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? p.accent : p.surfaceAlt),
        trackOutlineColor: WidgetStatePropertyAll(p.line),
        trackOutlineWidth: const WidgetStatePropertyAll(1),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? p.accent : p.mute),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.accent,
        inactiveTrackColor: p.line,
        thumbColor: p.accent,
        overlayColor: p.accent.withValues(alpha: 0.15),
      ),
    );
  }
}
