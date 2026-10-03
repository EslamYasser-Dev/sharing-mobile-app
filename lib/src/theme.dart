import 'package:flutter/material.dart';

/// The landing's two palettes, one per brightness.
///
/// Source of truth: `landing/app/globals.css` — the light values live on
/// `:root` and the warm dark values on `.dark-site`. Naming follows the
/// landing: `background` is `--color-void` (the page canvas), `card` is
/// `--color-abyss` (the `.panel` surface), `text` is `--color-paper` (the
/// ink). If the landing palette changes, update these to match.
///
/// This is a [ThemeExtension] rather than a set of `static const` colors so
/// that one widget tree can hold both palettes at once — `MaterialApp` builds
/// a light and a dark theme and Flutter swaps between them. Read it with
/// [SfsPalette.of].
class SfsPalette extends ThemeExtension<SfsPalette> {
  const SfsPalette({
    required this.background,
    required this.card,
    required this.rule,
    required this.border,
    required this.secondaryBorder,
    required this.surfaceOverlay,
    required this.text,
    required this.muted,
    required this.accent,
    required this.accentDim,
    required this.accentBorder,
    required this.onAccent,
    required this.warn,
    required this.danger,
    required this.dangerBorder,
  });

  // Surfaces.
  final Color background;
  final Color card;

  // Hairlines. The landing's `.rule` is paper at 12%, its `.panel` border is
  // paper at 10%, and `border-paper/25` outlines secondary controls.
  final Color rule;
  final Color border;
  final Color secondaryBorder;
  final Color surfaceOverlay;

  // Ink.
  final Color text;
  final Color muted;

  // Accent.
  final Color accent;
  final Color accentDim;
  final Color accentBorder;
  final Color onAccent;

  // Status. The landing defines `--color-warn-text` for both palettes;
  // `danger` is derived so it reads as the app's destructive red beside the
  // accent instead of the neon red the old palette used.
  final Color warn;
  final Color danger;
  final Color dangerBorder;

  /// Dark palette — `.dark-site`.
  static const SfsPalette dark = SfsPalette(
    background: Color(0xFF111110), // --color-void
    card: Color(0xFF161614), // --color-abyss / .panel
    rule: Color(0x1FF2EFE9),
    border: Color(0x1AF2EFE9),
    secondaryBorder: Color(0x40F2EFE9),
    surfaceOverlay: Color(0x0DF2EFE9),
    text: Color(0xFFF2EFE9), // --color-paper
    muted: Color(0xFF9A958C), // --color-muted
    accent: Color(0xFFD4A373), // --color-accent
    accentDim: Color(0x24D4A373), // --color-accent-dim, 14%
    accentBorder: Color(0x4DD4A373), // accent at 30%
    onAccent: Color(0xFF111110),
    warn: Color(0xFFFDE68A), // --color-warn-text
    danger: Color(0xFFE08A82),
    dangerBorder: Color(0x66E08A82),
  );

  /// Light palette — `:root`.
  ///
  /// Ink and hairlines invert with the palette: the dark hairlines are the
  /// paper ink at a fixed alpha, so the light ones are `#14161b` at the same
  /// alphas. White sits on the blue accent here; in dark the accent is the
  /// tan, which is far too light for white ink, so `onAccent` flips too.
  static const SfsPalette light = SfsPalette(
    background: Color(0xFFF5F6F8), // --color-void
    card: Color(0xFFFFFFFF), // --color-abyss / .panel
    rule: Color(0x1F14161B),
    border: Color(0x1A14161B),
    secondaryBorder: Color(0x4014161B),
    surfaceOverlay: Color(0x0D14161B),
    text: Color(0xFF14161B), // --color-paper
    muted: Color(0xFF575C66), // --color-muted
    accent: Color(0xFF0F62FE), // --color-accent
    accentDim: Color(0x170F62FE), // --color-accent-dim, 9%
    accentBorder: Color(0x4D0F62FE), // accent at 30%
    onAccent: Color(0xFFFFFFFF),
    warn: Color(0xFF7C4A03), // --color-warn-text
    danger: Color(0xFFB91C1C),
    dangerBorder: Color(0x66B91C1C),
  );

  /// The palette the current theme is using.
  static SfsPalette of(BuildContext context) =>
      Theme.of(context).extension<SfsPalette>() ?? dark;

  @override
  SfsPalette copyWith({
    Color? background,
    Color? card,
    Color? rule,
    Color? border,
    Color? secondaryBorder,
    Color? surfaceOverlay,
    Color? text,
    Color? muted,
    Color? accent,
    Color? accentDim,
    Color? accentBorder,
    Color? onAccent,
    Color? warn,
    Color? danger,
    Color? dangerBorder,
  }) {
    return SfsPalette(
      background: background ?? this.background,
      card: card ?? this.card,
      rule: rule ?? this.rule,
      border: border ?? this.border,
      secondaryBorder: secondaryBorder ?? this.secondaryBorder,
      surfaceOverlay: surfaceOverlay ?? this.surfaceOverlay,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      accent: accent ?? this.accent,
      accentDim: accentDim ?? this.accentDim,
      accentBorder: accentBorder ?? this.accentBorder,
      onAccent: onAccent ?? this.onAccent,
      warn: warn ?? this.warn,
      danger: danger ?? this.danger,
      dangerBorder: dangerBorder ?? this.dangerBorder,
    );
  }

  @override
  SfsPalette lerp(SfsPalette? other, double t) {
    if (other == null) return this;
    return SfsPalette(
      background: Color.lerp(background, other.background, t)!,
      card: Color.lerp(card, other.card, t)!,
      rule: Color.lerp(rule, other.rule, t)!,
      border: Color.lerp(border, other.border, t)!,
      secondaryBorder: Color.lerp(secondaryBorder, other.secondaryBorder, t)!,
      surfaceOverlay: Color.lerp(surfaceOverlay, other.surfaceOverlay, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentDim: Color.lerp(accentDim, other.accentDim, t)!,
      accentBorder: Color.lerp(accentBorder, other.accentBorder, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerBorder: Color.lerp(dangerBorder, other.dangerBorder, t)!,
    );
  }
}

/// The landing's type vocabulary, exposed as reusable styles.
///
/// The landing sets eyebrows and nav labels in monospace, uppercase and
/// tracked; Flutter has no `text-transform`, so labels are written uppercase
/// at the call site (or passed through `String.toUpperCase()`).
///
/// Colours come from the [SfsPalette] passed in rather than being baked in,
/// because the same style has to read differently on each palette.
abstract final class SfsTextStyles {
  /// Landing `.eyebrow` — mono, tracked, uppercase, accent.
  static TextStyle eyebrow(SfsPalette palette) => TextStyle(
    fontFamilyFallback: const <String>['monospace'],
    fontSize: 11,
    height: 1.3,
    letterSpacing: 1.6,
    fontWeight: FontWeight.w500,
    color: palette.accent,
  );

  /// The landing's muted mono label voice (stat labels, nav, footers).
  static TextStyle label(SfsPalette palette) => TextStyle(
    fontFamilyFallback: const <String>['monospace'],
    fontSize: 10,
    height: 1.3,
    letterSpacing: 1.2,
    fontWeight: FontWeight.w500,
    color: palette.muted,
  );

  /// Paths and tokens read as code, the way the landing renders inline code.
  static TextStyle path(SfsPalette palette) => TextStyle(
    fontFamilyFallback: const <String>['monospace'],
    fontSize: 12,
    height: 1.35,
    letterSpacing: 0.4,
    color: palette.muted,
  );

  /// Landing h1/h2: display face, bold (not heavy), tracking-tight.
  static TextStyle title(SfsPalette palette) => TextStyle(
    fontSize: 21,
    height: 1.15,
    letterSpacing: -0.4,
    fontWeight: FontWeight.w700,
    color: palette.text,
  );
}

/// Builds the app theme for [brightness].
///
/// Both palettes describe the same vocabulary — flat panels, hairline rules,
/// mono eyebrows, square-ish buttons — so only the colours differ between the
/// returned light and dark themes.
ThemeData buildAppTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final pal = isDark ? SfsPalette.dark : SfsPalette.light;

  final colorScheme = isDark
      ? ColorScheme.dark(
          surface: pal.card,
          primary: pal.accent,
          onPrimary: pal.onAccent,
          secondary: pal.accent,
          onSecondary: pal.onAccent,
          error: pal.danger,
          onError: pal.background,
          onSurface: pal.text,
          outline: pal.border,
          outlineVariant: pal.rule,
        )
      : ColorScheme.light(
          surface: pal.card,
          primary: pal.accent,
          onPrimary: pal.onAccent,
          secondary: pal.accent,
          onSecondary: pal.onAccent,
          error: pal.danger,
          onError: Colors.white,
          onSurface: pal.text,
          outline: pal.border,
          outlineVariant: pal.rule,
        );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: pal.background,
    canvasColor: pal.background,
    cardColor: pal.card,
    extensions: <ThemeExtension<dynamic>>[pal],
    appBarTheme: AppBarTheme(
      backgroundColor: pal.background,
      foregroundColor: pal.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        color: pal.text,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
    ),
    // The landing sets its nav in mono, uppercase and tracked.
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: pal.card,
      elevation: 0,
      selectedItemColor: pal.accent,
      unselectedItemColor: pal.muted,
      selectedIconTheme: IconThemeData(color: pal.accent, size: 22),
      unselectedIconTheme: IconThemeData(color: pal.muted, size: 22),
      type: BottomNavigationBarType.fixed,
      selectedLabelStyle: TextStyle(
        fontFamilyFallback: const <String>['monospace'],
        fontSize: 10,
        height: 1.2,
        letterSpacing: 1.1,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelStyle: TextStyle(
        fontFamilyFallback: const <String>['monospace'],
        fontSize: 10,
        height: 1.2,
        letterSpacing: 1.1,
        fontWeight: FontWeight.w500,
      ),
    ),
    // Landing `.panel`: flat, hairline-bordered, no elevation.
    dialogTheme: DialogThemeData(
      backgroundColor: pal.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        side: BorderSide(color: pal.border),
      ),
      titleTextStyle: TextStyle(
        color: pal.text,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      contentTextStyle: TextStyle(color: pal.text, fontSize: 14, height: 1.45),
    ),
    // Landing `btnPrimary`: accent fill, accent-ink, flat, square-ish.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: pal.accent,
        foregroundColor: pal.onAccent,
        disabledBackgroundColor: pal.accentDim,
        disabledForegroundColor: pal.muted,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    // Landing `btnSecondary`: text/25 outline, text ink.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: pal.text,
        side: BorderSide(color: pal.secondaryBorder),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: pal.accent,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    textTheme: TextTheme(
      headlineSmall: SfsTextStyles.title(pal),
      titleLarge: SfsTextStyles.title(pal),
      titleMedium: TextStyle(
        color: pal.text,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      titleSmall: TextStyle(
        color: pal.text,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: TextStyle(color: pal.text, fontSize: 15, height: 1.45),
      bodyMedium: TextStyle(color: pal.text, fontSize: 14, height: 1.45),
      bodySmall: TextStyle(color: pal.muted, fontSize: 12, height: 1.4),
      labelLarge: TextStyle(
        color: pal.text,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: SfsTextStyles.eyebrow(pal),
      labelSmall: SfsTextStyles.label(pal),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: pal.surfaceOverlay,
      hintStyle: TextStyle(color: pal.muted, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: pal.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: pal.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: pal.accent),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: pal.dangerBorder),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: pal.danger),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: pal.card,
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(6)),
        side: BorderSide(color: pal.border),
      ),
      contentTextStyle: TextStyle(color: pal.text, fontSize: 14),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: pal.accent,
      linearTrackColor: pal.surfaceOverlay,
      circularTrackColor: pal.surfaceOverlay,
      refreshBackgroundColor: pal.card,
    ),
    dividerTheme: DividerThemeData(color: pal.rule, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(
      iconColor: pal.muted,
      textColor: pal.text,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      minLeadingWidth: 0,
    ),
    iconTheme: IconThemeData(color: pal.muted, size: 20),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: pal.accent,
      foregroundColor: pal.onAccent,
      elevation: 0,
    ),
  );
}

/// Futuristic surface language layered on the landing vocabulary.
///
/// Palette values are untouched (they mirror `landing/app/globals.css`);
/// these helpers only add depth: soft neon glows, gradient hero washes and
/// rounder panels. All glow alphas stay low so light mode stays calm.
///
/// NOTE (neon-glass direction): the app now leads the design language and may
/// diverge from the landing. [SfsGlass] carries the divergence: frosted
/// surfaces, aurora washes, and stronger glows. The base palette still backs
/// every token, so light/dark keep working and the landing can adopt the
/// language later.
abstract final class SfsRadii {
  static const double card = 16;
  static const double sheet = 20;
  static const double pill = 999;
}

abstract final class SfsShadows {
  static List<BoxShadow> glow(SfsPalette pal, Color color) => [
        BoxShadow(
          color: color.withValues(alpha: 0.22),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ];

  static List<BoxShadow> card(SfsPalette pal) => [
        BoxShadow(
          color: pal.text.withValues(alpha: 0.06),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];
}

abstract final class SfsDecor {
  /// Flat landing panel with a soft lift shadow.
  static BoxDecoration panel(SfsPalette pal, {double radius = SfsRadii.card}) =>
      BoxDecoration(
        color: pal.card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: pal.border),
        boxShadow: SfsShadows.card(pal),
      );

  /// Hero wash used behind screen titles: accent glow fading into the
  /// background, the way the landing fades its hero into the page.
  static BoxDecoration hero(SfsPalette pal) => BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [pal.accentDim, pal.accentDim.withValues(alpha: 0.02)],
        ),
        borderRadius: BorderRadius.circular(SfsRadii.card),
        border: Border.all(color: pal.accentBorder),
      );

  /// Active-transfer card: landing panel plus a neon accent edge.
  static BoxDecoration liveCard(SfsPalette pal, {bool failed = false}) =>
      BoxDecoration(
        color: pal.card,
        borderRadius: BorderRadius.circular(SfsRadii.card),
        border: Border.all(
          color: failed ? pal.dangerBorder : pal.accentBorder,
        ),
        boxShadow: SfsShadows.glow(
          pal,
          failed ? pal.danger : pal.accent,
        ),
      );

  /// Frosted-glass card: translucent surface + hairline border + soft lift.
  /// Layer over [AuroraBackground] (or any wash) with a [BackdropFilter]
  /// handled by [GlassCard] — this is just the paint.
  static BoxDecoration glass(SfsPalette pal, {double radius = SfsRadii.card}) {
    final glass = SfsGlass.of(pal);
    return BoxDecoration(
      color: glass.tint,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: glass.border),
      boxShadow: SfsShadows.card(pal),
    );
  }

  /// Frosted-glass card with a neon accent edge for live/active content.
  static BoxDecoration liveGlass(
    SfsPalette pal, {
    bool failed = false,
    double radius = SfsRadii.card,
  }) {
    final glass = SfsGlass.of(pal);
    return BoxDecoration(
      color: glass.tint,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: failed ? pal.dangerBorder : pal.accentBorder,
      ),
      boxShadow: SfsShadows.glow(pal, failed ? pal.danger : pal.accent),
    );
  }
}

/// Neon-glass tokens derived from the base palette.
///
/// Everything derives from [SfsPalette] (never hardcoded), so both
/// brightnesses keep working: dark gets warm-tan aurora + deep tints, light
/// gets blue aurora + white tints with stronger borders to avoid washout.
class SfsGlass {
  const SfsGlass({
    required this.tint,
    required this.border,
    required this.scrim,
    required this.blur,
    required this.auroraA,
    required this.auroraB,
    required this.auroraC,
    required this.glowAlpha,
  });

  /// Frosted surface tint painted under the blur.
  final Color tint;

  /// Hairline border for glass edges.
  final Color border;

  /// Bottom scrim behind scrolling content / nav.
  final Color scrim;

  /// Backdrop blur sigma for cards and sheets.
  final double blur;

  /// Aurora wash stops: accent, violet, cyan derivations.
  final Color auroraA;
  final Color auroraB;
  final Color auroraC;

  /// Alpha multiplier for neon glows (stronger in dark).
  final double glowAlpha;

  factory SfsGlass.of(SfsPalette pal) {
    final isDark =
        pal.background.computeLuminance() < pal.text.computeLuminance();
    if (isDark) {
      return SfsGlass(
        tint: pal.card.withValues(alpha: 0.62),
        border: const Color(0x33F2EFE9),
        scrim: pal.background.withValues(alpha: 0.78),
        blur: 18,
        auroraA: pal.accent.withValues(alpha: 0.34),
        auroraB: const Color(0xFF8B7CF6).withValues(alpha: 0.26),
        auroraC: const Color(0xFF4FD8E8).withValues(alpha: 0.20),
        glowAlpha: 1,
      );
    }
    return SfsGlass(
      tint: const Color(0xFFFFFFFF).withValues(alpha: 0.66),
      border: const Color(0xFF14161B).withValues(alpha: 0.12),
      scrim: pal.background.withValues(alpha: 0.82),
      blur: 14,
      auroraA: pal.accent.withValues(alpha: 0.20),
      auroraB: const Color(0xFF7C6CF6).withValues(alpha: 0.14),
      auroraC: const Color(0xFF2FB9D4).withValues(alpha: 0.12),
      glowAlpha: 0.55,
    );
  }
}
