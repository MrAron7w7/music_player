import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const blue = Color(0xFF2563EB);
  static final themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);

  static int? _lightKey;
  static int? _darkKey;
  static ThemeData? _lightTheme;
  static ThemeData? _darkTheme;

  static final Map<Brightness, TextTheme> _baseTextThemes = {
    Brightness.light: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
    Brightness.dark: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
  };

  static ThemeData light([Color? albumColor]) {
    final key = albumColor?.toARGB32() ?? -1;
    if (_lightTheme != null && _lightKey == key) return _lightTheme!;
    final theme = _build(Brightness.light, albumColor);
    _lightKey = key;
    _lightTheme = theme;
    return theme;
  }

  static ThemeData dark([Color? albumColor]) {
    final key = albumColor?.toARGB32() ?? -1;
    if (_darkTheme != null && _darkKey == key) return _darkTheme!;
    final theme = _build(Brightness.dark, albumColor);
    _darkKey = key;
    _darkTheme = theme;
    return theme;
  }

  static ThemeData _build(Brightness brightness, Color? albumColor) {
    final dark = brightness == Brightness.dark;
    final accent = _normalizeAccent(albumColor ?? blue, brightness);
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    );
    // Blue-gray surfaces keep depth and contrast without using pure black.
    final background = dark ? const Color(0xFF10151D) : const Color(0xFFF6F8FC);
    final surface = dark ? const Color(0xFF171E28) : Colors.white;
    final surfaceHigh = dark
        ? const Color(0xFF202A36)
        : const Color(0xFFEDF1F7);
    final textTheme = _baseTextThemes[brightness]!;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme.copyWith(
        primary: accent,
        secondary: Color.lerp(accent, scheme.tertiary, .28)!,
        surface: surface,
        surfaceContainerLowest: background,
        surfaceContainerLow: surface,
        surfaceContainer: surfaceHigh,
        surfaceContainerHigh: surfaceHigh,
        surfaceContainerHighest: dark
            ? const Color(0xFF2A3543)
            : const Color(0xFFE2E8F0),
      ),
      scaffoldBackgroundColor: background,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: dark ? 0 : 1,
        shadowColor: Colors.black.withValues(alpha: .05),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: surface,
        indicatorColor: accent.withValues(alpha: dark ? .24 : .12),
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => textTheme.labelSmall?.copyWith(
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: accent,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorColor: accent,
        dividerColor: Colors.transparent,
        labelStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        unselectedLabelStyle: textTheme.labelLarge,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHigh,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: accent, width: 1.4),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        showDragHandle: true,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: scheme.onSurface.withValues(alpha: .14),
        thumbColor: accent,
        overlayColor: accent.withValues(alpha: .12),
        trackHeight: 3,
        showValueIndicator: ShowValueIndicator.never,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
      ),
      splashFactory: InkRipple.splashFactory,
      visualDensity: VisualDensity.standard,
    );
  }

  static Color _normalizeAccent(Color source, Brightness brightness) {
    final hsl = HSLColor.fromColor(source);
    return hsl
        .withSaturation(hsl.saturation.clamp(.38, .72).toDouble())
        .withLightness(brightness == Brightness.dark ? .68 : .48)
        .toColor();
  }
}
