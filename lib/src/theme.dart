import 'package:flutter/material.dart';

/// Design tokens ported from the landing site's dark palette.
///
/// Source of truth: `landing/app/globals.css` → `.dark-site`. The landing
/// ships a light palette as its site default and this warm-dark palette as
/// the opt-in variant that was written for the app clients; the mobile app is
/// dark-only, so this is the palette it uses. If the landing palette changes,
/// update these values to match.
///
/// Naming follows the landing: `background` is `--color-void` (the page
/// canvas), `card` is `--color-abyss` (the `.panel` surface), `text` is
/// `--color-paper` (the ink).
abstract final class SfsColors {
  // Surfaces.
  static const Color background = Color(0xFF111110); // --color-void
  static const Color card = Color(0xFF161614); // --color-abyss / .panel

  // Hairlines. The landing's `.rule` is paper at 12%, its `.panel` border is
  // paper at 10%, and `border-paper/25` outlines secondary controls.
  static const Color rule = Color(0x1FF2EFE9);
  static const Color border = Color(0x1AF2EFE9);
  static const Color secondaryBorder = Color(0x40F2EFE9);
  static const Color surfaceOverlay = Color(0x0DF2EFE9); // paper at 5%

  // Ink.
  static const Color text = Color(0xFFF2EFE9); // --color-paper
  static const Color muted = Color(0xFF9A958C); // --color-muted

  // Accent.
  static const Color accent = Color(0xFFD4A373); // --color-accent
  static const Color accentDim = Color(0x24D4A373); // --color-accent-dim, 14%
  static const Color accentBorder = Color(0x4DD4A373); // accent at 30%
  static const Color onAccent = Color(0xFF111110);

  // Status. The landing only defines `--color-warn-text` for dark; `danger`
  // is derived so it reads as a warm red that sits beside the tan accent
  // instead of the neon red the old palette used.
  static const Color warn = Color(0xFFFDE68A); // --color-warn-text
  static const Color danger = Color(0xFFE08A82);
  static const Color dangerBorder = Color(0x66E08A82);
}

/// The landing's type vocabulary, exposed as reusable styles.
///
/// The landing sets eyebrows and nav labels in monospace, uppercase and
/// tracked; Flutter has no `text-transform`, so labels are written uppercase
/// at the call site (or passed through `String.toUpperCase()`).
abstract final class SfsTextStyles {
  /// Landing `.eyebrow` — mono, tracked, uppercase, accent.
  static const TextStyle eyebrow = TextStyle(
    fontFamilyFallback: <String>['monospace'],
    fontSize: 11,
    height: 1.3,
    letterSpacing: 1.6,
    fontWeight: FontWeight.w500,
    color: SfsColors.accent,
  );

  /// The landing's muted mono label voice (stat labels, nav, footers).
  static const TextStyle label = TextStyle(
    fontFamilyFallback: <String>['monospace'],
    fontSize: 10,
    height: 1.3,
    letterSpacing: 1.2,
    fontWeight: FontWeight.w500,
    color: SfsColors.muted,
  );

  /// Paths and tokens read as code, the way the landing renders inline code.
  static const TextStyle path = TextStyle(
    fontFamilyFallback: <String>['monospace'],
    fontSize: 12,
    height: 1.35,
    letterSpacing: 0.4,
    color: SfsColors.muted,
  );

  /// Landing h1/h2: display face, bold (not heavy), tracking-tight.
  static const TextStyle title = TextStyle(
    fontSize: 21,
    height: 1.15,
    letterSpacing: -0.4,
    fontWeight: FontWeight.w700,
    color: SfsColors.text,
  );
}

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: SfsColors.background,
    canvasColor: SfsColors.background,
    cardColor: SfsColors.card,
    colorScheme: const ColorScheme.dark(
      surface: SfsColors.card,
      primary: SfsColors.accent,
      onPrimary: SfsColors.onAccent,
      secondary: SfsColors.accent,
      onSecondary: SfsColors.onAccent,
      error: SfsColors.danger,
      onError: SfsColors.background,
      onSurface: SfsColors.text,
      outline: SfsColors.border,
      outlineVariant: SfsColors.rule,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: SfsColors.background,
      foregroundColor: SfsColors.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        color: SfsColors.text,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
    ),
    // The landing sets its nav in mono, uppercase and tracked.
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: SfsColors.card,
      elevation: 0,
      selectedItemColor: SfsColors.accent,
      unselectedItemColor: SfsColors.muted,
      selectedIconTheme: IconThemeData(color: SfsColors.accent, size: 22),
      unselectedIconTheme: IconThemeData(color: SfsColors.muted, size: 22),
      type: BottomNavigationBarType.fixed,
      selectedLabelStyle: TextStyle(
        fontFamilyFallback: <String>['monospace'],
        fontSize: 10,
        height: 1.2,
        letterSpacing: 1.1,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelStyle: TextStyle(
        fontFamilyFallback: <String>['monospace'],
        fontSize: 10,
        height: 1.2,
        letterSpacing: 1.1,
        fontWeight: FontWeight.w500,
      ),
    ),
    // Landing `.panel`: flat, hairline-bordered, no elevation.
    dialogTheme: const DialogThemeData(
      backgroundColor: SfsColors.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        side: BorderSide(color: SfsColors.border),
      ),
      titleTextStyle: TextStyle(
        color: SfsColors.text,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      contentTextStyle: TextStyle(
        color: SfsColors.text,
        fontSize: 14,
        height: 1.45,
      ),
    ),
    // Landing `btnPrimary`: accent fill, dark ink, flat, square-ish.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: SfsColors.accent,
        foregroundColor: SfsColors.onAccent,
        disabledBackgroundColor: SfsColors.accentDim,
        disabledForegroundColor: SfsColors.muted,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    ),
    // Landing `btnSecondary`: paper/25 outline, paper ink.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: SfsColors.text,
        side: const BorderSide(color: SfsColors.secondaryBorder),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: SfsColors.accent,
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    ),
    textTheme: const TextTheme(
      headlineSmall: SfsTextStyles.title,
      titleLarge: SfsTextStyles.title,
      titleMedium: TextStyle(
        color: SfsColors.text,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      titleSmall: TextStyle(
        color: SfsColors.text,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: TextStyle(color: SfsColors.text, fontSize: 15, height: 1.45),
      bodyMedium: TextStyle(color: SfsColors.text, fontSize: 14, height: 1.45),
      bodySmall: TextStyle(color: SfsColors.muted, fontSize: 12, height: 1.4),
      labelLarge: TextStyle(
        color: SfsColors.text,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: SfsTextStyles.eyebrow,
      labelSmall: SfsTextStyles.label,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: SfsColors.surfaceOverlay,
      hintStyle: const TextStyle(color: SfsColors.muted, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: SfsColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: SfsColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: SfsColors.accent),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: SfsColors.dangerBorder),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: SfsColors.danger),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: SfsColors.card,
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
        side: BorderSide(color: SfsColors.border),
      ),
      contentTextStyle: TextStyle(color: SfsColors.text, fontSize: 14),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: SfsColors.accent,
      linearTrackColor: SfsColors.surfaceOverlay,
      circularTrackColor: SfsColors.surfaceOverlay,
      refreshBackgroundColor: SfsColors.card,
    ),
    dividerTheme: const DividerThemeData(
      color: SfsColors.rule,
      thickness: 1,
      space: 1,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: SfsColors.muted,
      textColor: SfsColors.text,
      contentPadding: EdgeInsets.symmetric(horizontal: 16),
      minLeadingWidth: 0,
    ),
    iconTheme: const IconThemeData(color: SfsColors.muted, size: 20),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: SfsColors.accent,
      foregroundColor: SfsColors.onAccent,
      elevation: 0,
    ),
  );
}
