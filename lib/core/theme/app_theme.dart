import 'package:flutter/material.dart';

import '../design/design_tokens.dart';
import '../viz/status_palette.dart';

/// The accents a person can pick for their own copy of the app. Values match
/// the `accent` check constraint on user_preferences.
enum AppAccent {
  indigo('indigo', 'Indigo', BrandPalette.indigo),
  green('green', 'Green', Color(0xFF2E7D32)),
  teal('teal', 'Teal', VizChrome.accentTeal),
  plum('plum', 'Plum', VizChrome.accentPlum),
  slate('slate', 'Slate', VizChrome.accentSlate);

  const AppAccent(this.id, this.label, this.seed);

  final String id;
  final String label;
  final Color seed;

  static AppAccent parse(String? value) =>
      AppAccent.values.firstWhere((a) => a.id == value, orElse: () => AppAccent.indigo);
}

/// How tightly the app packs. Compact is the original house style — a dense
/// business app where a whole category's stock should fit on one screen —
/// but it is punishing on a phone, so it is now a choice.
enum AppDensity {
  compact('compact', 'Compact', 'Most on screen'),
  standard('standard', 'Standard', 'A little more room'),
  comfortable('comfortable', 'Comfortable', 'Easiest to tap');

  const AppDensity(this.id, this.label, this.caption);

  final String id;
  final String label;
  final String caption;

  static AppDensity parse(String? value) =>
      AppDensity.values.firstWhere((d) => d.id == value, orElse: () => AppDensity.compact);

  VisualDensity get visualDensity {
    switch (this) {
      case AppDensity.compact:
        return VisualDensity.compact;
      case AppDensity.standard:
        return VisualDensity.standard;
      case AppDensity.comfortable:
        return const VisualDensity(horizontal: 1, vertical: 1);
    }
  }

  /// Row metrics scale with density too — otherwise a comfortable setting
  /// still leaves every table as tight as it was.
  double get rowHeightBonus {
    switch (this) {
      case AppDensity.compact:
        return 0;
      case AppDensity.standard:
        return 5;
      case AppDensity.comfortable:
        return 10;
    }
  }
}

class AppTheme {
  AppTheme._();

  /// The app's original text scale, and the default for anyone who has not
  /// chosen their own.
  static const double textScale = 0.88;

  static ThemeData light({
    AppAccent accent = AppAccent.indigo,
    AppDensity density = AppDensity.compact,
  }) =>
      _build(Brightness.light, accent, density);

  static ThemeData dark({
    AppAccent accent = AppAccent.indigo,
    AppDensity density = AppDensity.compact,
  }) =>
      _build(Brightness.dark, accent, density);

  /// Everything is deliberately tighter than Material's defaults — this is a
  /// dense business app where an Owner wants a whole category's stock, or a
  /// salesman a whole route's order, on screen at once rather than scrolling
  /// past generous padding. Paired with a text scale at the app root.
  static ThemeData _build(Brightness brightness, AppAccent accent, AppDensity density) {
    final isDark = brightness == Brightness.dark;
    final generated = ColorScheme.fromSeed(seedColor: accent.seed, brightness: brightness);
    // Material's generated dark surfaces are a near-black neutral (#141218),
    // which reads as a black screen rather than as this app's dark mode. Tint
    // the whole dark surface ramp toward the brand indigo so it looks
    // deliberate — and stays clearly a colour, not an absence of one.
    final scheme = isDark
        ? generated.copyWith(
            surface: const Color(0xFF1A1736),
            surfaceContainerLowest: const Color(0xFF15132E),
            surfaceContainerLow: const Color(0xFF1F1C40),
            surfaceContainer: const Color(0xFF232048),
            surfaceContainerHigh: const Color(0xFF282450),
            surfaceContainerHighest: const Color(0xFF2E2958),
            onSurface: const Color(0xFFE9E7F4),
            onSurfaceVariant: const Color(0xFFB6B2CE),
            outlineVariant: const Color(0xFF3A3568),
          )
        // A warm off-white page with near-white cards on it, rather than the
        // faintly tinted white Material derives from the accent — this is the
        // paper tone the app has always had, and it matches the cream the
        // tables already use for their headers.
        : generated.copyWith(
            surface: const Color(0xFFF8F6F0),
            surfaceContainerLowest: const Color(0xFFFFFFFF),
            surfaceContainerLow: const Color(0xFFFCFAF5),
            surfaceContainer: const Color(0xFFFBF9F4),
            surfaceContainerHigh: const Color(0xFFF5F1E8),
            surfaceContainerHighest: VizChrome.tableHeader,
            onSurface: const Color(0xFF26233F),
            onSurfaceVariant: VizChrome.secondaryInk,
            outlineVariant: VizChrome.track,
          );
    final bonus = density.rowHeightBonus;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      visualDensity: density.visualDensity,
      appBarTheme: const AppBarTheme(centerTitle: false, toolbarHeight: 48),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      dataTableTheme: DataTableThemeData(
        columnSpacing: 18,
        horizontalMargin: 12,
        headingRowHeight: 40 + bonus,
        dataRowMinHeight: 36 + bonus,
        dataRowMaxHeight: 44 + bonus,
        // Set centrally so every table's header follows the chosen theme —
        // screens no longer hardcode a cream that only works on a light page.
        headingRowColor: WidgetStateProperty.all(
          isDark ? scheme.surfaceContainerHighest : VizChrome.tableHeader,
        ),
        headingTextStyle: AppType.label.copyWith(color: scheme.onSurfaceVariant),
        dataTextStyle: AppType.body.copyWith(color: scheme.onSurface),
        // Rows light up under the pointer. Set here rather than at each of the
        // app's 21 DataTables — and it is the only signal that a row is
        // clickable, since DataRow draws no ink.
        dataRowColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) {
            return scheme.primary.withValues(alpha: isDark ? 0.10 : 0.05);
          }
          return null;
        }),
      ),
      cardTheme: CardThemeData(
        margin: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xs),
        elevation: 0,
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.rLg,
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: isDark ? 0.5 : 0.7)),
        ),
      ),
      listTileTheme: ListTileThemeData(dense: density == AppDensity.compact),
      chipTheme: ChipThemeData(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 2),
        labelStyle: AppType.label,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.rSm),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      textTheme: _textTheme(scheme),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          textStyle: AppType.titleS,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.rMd),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          textStyle: AppType.titleS,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.rMd),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: AppType.label,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.rSm),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          textStyle: AppType.label,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.rMd),
        ),
      ),
      dividerTheme: DividerThemeData(
        space: 1,
        thickness: 1,
        color: scheme.outlineVariant.withValues(alpha: isDark ? 0.5 : 0.8),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.rMd),
        contentTextStyle: AppType.body.copyWith(color: scheme.onInverseSurface),
      ),
      dialogTheme: DialogThemeData(
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.rLg),
        titleTextStyle: AppType.titleM.copyWith(color: scheme.onSurface),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface.withValues(alpha: 0.94),
          borderRadius: AppRadius.rSm,
        ),
        textStyle: AppType.caption.copyWith(color: scheme.onInverseSurface),
      ),
    );
  }

  /// The one type scale, so a screen never has to invent a font size.
  static TextTheme _textTheme(ColorScheme scheme) {
    final ink = scheme.onSurface;
    final soft = scheme.onSurfaceVariant;
    return TextTheme(
      displaySmall: AppType.display.copyWith(color: ink),
      headlineSmall: AppType.titleL.copyWith(color: ink),
      titleLarge: AppType.titleL.copyWith(color: ink),
      titleMedium: AppType.titleM.copyWith(color: ink),
      titleSmall: AppType.titleS.copyWith(color: ink),
      bodyLarge: AppType.body.copyWith(color: ink),
      bodyMedium: AppType.body.copyWith(color: ink),
      bodySmall: AppType.bodyS.copyWith(color: soft),
      labelLarge: AppType.label.copyWith(color: ink),
      labelMedium: AppType.label.copyWith(color: soft),
      labelSmall: AppType.caption.copyWith(color: soft),
    );
  }
}
