import 'package:flutter/material.dart';

import 'tokens.dart';

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final c = dark ? PaisaColors.dark : PaisaColors.light;
  final primary = dark ? const Color(0xff8ccaa7) : const Color(0xff1e5c45);
  final onPrimary = dark ? const Color(0xff0c1a13) : Colors.white;
  final error = dark ? const Color(0xfff2a28c) : const Color(0xffb4472c);

  final scheme = ColorScheme(
    brightness: brightness,
    primary: primary,
    onPrimary: onPrimary,
    secondary: dark ? const Color(0xff6db38f) : const Color(0xff2e7255),
    onSecondary: dark ? const Color(0xff0c1a13) : Colors.white,
    error: error,
    onError: dark ? const Color(0xff2b1006) : Colors.white,
    surface: c.paper,
    onSurface: c.ink,
    onSurfaceVariant: c.muted,
    outline: c.line,
    outlineVariant: c.line,
    surfaceContainerLowest: c.paper,
    surfaceContainerLow: c.cream,
    surfaceContainer: c.paper,
    surfaceContainerHigh: c.paper,
    primaryContainer: dark ? const Color(0xff1f3a2e) : c.lime,
    onPrimaryContainer: dark ? const Color(0xffcfe9da) : const Color(0xff1c3b2f),
  );

  // Headings are a serif and everything scanned is a sans, as on the web. The
  // generic 'serif' resolves to the system serif; swap for a bundled font if
  // the look needs to be exact. Sizes are phone sizes: the web's 10-12px body
  // is unreadable on a handset, so the floor here is 12sp and body is 14sp.
  const serif = 'serif';
  final text = TextTheme(
    displaySmall: TextStyle(fontFamily: serif, fontSize: 30, fontWeight: FontWeight.w500, letterSpacing: -0.5, color: c.ink),
    headlineMedium: TextStyle(fontFamily: serif, fontSize: 24, fontWeight: FontWeight.w500, letterSpacing: -0.3, color: c.ink),
    headlineSmall: TextStyle(fontFamily: serif, fontSize: 20, fontWeight: FontWeight.w500, color: c.ink),
    titleLarge: TextStyle(fontFamily: serif, fontSize: 18, fontWeight: FontWeight.w500, color: c.ink),
    titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.ink),
    titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.ink),
    bodyLarge: TextStyle(fontSize: 16, color: c.ink),
    bodyMedium: TextStyle(fontSize: 14, height: 1.35, color: c.ink),
    bodySmall: TextStyle(fontSize: 12, height: 1.3, color: c.muted),
    labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.ink),
    labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.muted),
    labelSmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.9, color: c.muted),
  );

  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.cream,
    textTheme: text,
    extensions: [c],
    appBarTheme: AppBarTheme(
      backgroundColor: c.cream,
      surfaceTintColor: Colors.transparent,
      foregroundColor: c.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: text.titleLarge,
    ),
    cardTheme: CardThemeData(
      color: c.paper,
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: c.line)),
    ),
    dividerTheme: DividerThemeData(color: c.line, space: 1, thickness: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(48, 48), shape: shape, textStyle: text.labelLarge),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48), shape: shape, side: BorderSide(color: c.line), foregroundColor: primary, textStyle: text.labelLarge),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: primary, textStyle: text.labelLarge),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.paper,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: primary, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: error)),
      labelStyle: text.bodyMedium?.copyWith(color: c.muted),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.paper,
      surfaceTintColor: Colors.transparent,
      indicatorColor: dark ? const Color(0xff1f3a2e) : c.lime,
      labelTextStyle: WidgetStatePropertyAll(text.labelMedium),
    ),
  );
}
