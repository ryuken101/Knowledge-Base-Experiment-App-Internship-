import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// Design tokens translated from DESIGN.md (Apple "museum gallery" language):
/// a single Action Blue accent, near-black ink, white/parchment canvases,
/// hairline borders, pill CTAs, and tight display typography. No decorative
/// shadows or gradients — elevation comes from surface-color changes.

class AppColors {
  AppColors._();

  // Brand / accent — the single interactive color.
  static const primary = Color(0xFF0066CC);
  static const primaryFocus = Color(0xFF0071E3);
  static const primaryOnDark = Color(0xFF2997FF);

  // Ink / text.
  static const ink = Color(0xFF1D1D1F);
  static const inkMuted80 = Color(0xFF333333);
  static const inkMuted48 = Color(0xFF7A7A7A);
  static const onDark = Color(0xFFFFFFFF);
  static const bodyMuted = Color(0xFFCCCCCC);

  // Surfaces.
  static const canvas = Color(0xFFFFFFFF);
  static const parchment = Color(0xFFF5F5F7);
  static const pearl = Color(0xFFFAFAFC);
  static const tileDark = Color(0xFF272729);
  static const black = Color(0xFF000000);

  // Hairlines.
  static const dividerSoft = Color(0xFFF0F0F0);
  static const hairline = Color(0xFFE0E0E0);
}

class AppRadii {
  AppRadii._();
  static const double xs = 5;
  static const double sm = 8;
  static const double md = 11;
  static const double lg = 18;
  static const double pill = 9999;
}

class AppSpacing {
  AppSpacing._();
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 17;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
  static const double section = 80;
}

/// Type scale from DESIGN.md. SF Pro is Apple-proprietary; we name it first and
/// fall back to the platform system font (Segoe UI on Windows), keeping the
/// signature negative letter-spacing so the "Apple tight" cadence survives the
/// substitution.
class AppType {
  AppType._();

  static const List<String> _sans = [
    'SF Pro Display',
    'SF Pro Text',
    '-apple-system',
    'system-ui',
    'Segoe UI',
    'Helvetica Neue',
    'Arial',
  ];
  static const List<String> _mono = [
    'SF Mono',
    'Menlo',
    'Consolas',
    'Roboto Mono',
    'monospace',
  ];

  static TextStyle _base({
    required double size,
    required FontWeight weight,
    required double height,
    required double tracking,
    Color color = AppColors.ink,
  }) {
    return TextStyle(
      fontFamily: _sans.first,
      fontFamilyFallback: _sans.sublist(1),
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: tracking,
      color: color,
    );
  }

  static TextStyle heroDisplay({Color color = AppColors.ink}) => _base(
      size: 56, weight: FontWeight.w600, height: 1.07, tracking: -0.28, color: color);
  static TextStyle displayLg({Color color = AppColors.ink}) => _base(
      size: 40, weight: FontWeight.w600, height: 1.10, tracking: 0, color: color);
  static TextStyle displayMd({Color color = AppColors.ink}) => _base(
      size: 28, weight: FontWeight.w600, height: 1.2, tracking: -0.374, color: color);
  static TextStyle tagline({Color color = AppColors.ink}) => _base(
      size: 21, weight: FontWeight.w600, height: 1.19, tracking: 0.231, color: color);
  static TextStyle bodyStrong({Color color = AppColors.ink}) => _base(
      size: 17, weight: FontWeight.w600, height: 1.24, tracking: -0.374, color: color);
  static TextStyle body({Color color = AppColors.ink}) => _base(
      size: 17, weight: FontWeight.w400, height: 1.47, tracking: -0.374, color: color);
  static TextStyle caption({Color color = AppColors.inkMuted80}) => _base(
      size: 14, weight: FontWeight.w400, height: 1.43, tracking: -0.224, color: color);
  static TextStyle captionStrong({Color color = AppColors.ink}) => _base(
      size: 14, weight: FontWeight.w600, height: 1.29, tracking: -0.224, color: color);
  static TextStyle finePrint({Color color = AppColors.inkMuted48}) => _base(
      size: 12, weight: FontWeight.w400, height: 1.2, tracking: -0.12, color: color);

  static TextStyle mono({Color color = AppColors.ink, double size = 14}) =>
      TextStyle(
        fontFamily: _mono.first,
        fontFamilyFallback: _mono.sublist(1),
        fontSize: size,
        height: 1.5,
        letterSpacing: 0,
        color: color,
      );
}

/// The single Material theme used app-wide.
ThemeData buildAppTheme() {
  const colorScheme = ColorScheme.light(
    primary: AppColors.primary,
    onPrimary: AppColors.canvas,
    secondary: AppColors.primary,
    onSecondary: AppColors.canvas,
    surface: AppColors.canvas,
    onSurface: AppColors.ink,
    outline: AppColors.hairline,
    error: Color(0xFFB00020),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.canvas,
    splashFactory: NoSplash.splashFactory, // Apple UI has no ripple.
    highlightColor: Colors.transparent,
    textTheme: TextTheme(
      headlineLarge: AppType.displayLg(),
      headlineMedium: AppType.displayMd(),
      titleLarge: AppType.tagline(),
      bodyLarge: AppType.body(),
      bodyMedium: AppType.body(),
      bodySmall: AppType.caption(),
      labelLarge: AppType.captionStrong(),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.canvas,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: AppType.displayMd(),
      shape: const Border(bottom: BorderSide(color: AppColors.hairline)),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.hairline,
      thickness: 1,
      space: 1,
    ),
    iconTheme: const IconThemeData(color: AppColors.ink, size: 20),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: AppType.body(),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.canvas,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      titleTextStyle: AppType.bodyStrong(),
      contentTextStyle: AppType.body(color: AppColors.inkMuted80),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      contentTextStyle: AppType.caption(color: AppColors.onDark),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
    ),
  );
}

/// Markdown preview styling that mirrors the type scale: tight display headings,
/// 17px reading body, Action Blue links, parchment code blocks, hairline rules.
MarkdownStyleSheet buildMarkdownStyle() {
  return MarkdownStyleSheet(
    h1: AppType.displayMd(),
    h1Padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.xs),
    h2: AppType.tagline(),
    h2Padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xxs),
    h3: AppType.bodyStrong(),
    h4: AppType.bodyStrong(color: AppColors.inkMuted80),
    h5: AppType.captionStrong(),
    h6: AppType.captionStrong(color: AppColors.inkMuted48),
    p: AppType.body(),
    listBullet: AppType.body(),
    a: AppType.body(color: AppColors.primary),
    strong: AppType.bodyStrong(),
    em: AppType.body().copyWith(fontStyle: FontStyle.italic),
    code: AppType.mono(color: AppColors.inkMuted80),
    codeblockPadding: const EdgeInsets.all(AppSpacing.md),
    codeblockDecoration: BoxDecoration(
      color: AppColors.parchment,
      borderRadius: BorderRadius.circular(AppRadii.sm),
    ),
    blockquotePadding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, 0, 0),
    blockquoteDecoration: const BoxDecoration(
      border: Border(left: BorderSide(color: AppColors.hairline, width: 3)),
    ),
    blockquote: AppType.body(color: AppColors.inkMuted80),
    horizontalRuleDecoration: const BoxDecoration(
      border: Border(top: BorderSide(color: AppColors.hairline)),
    ),
    h1Align: WrapAlignment.start,
    textScaler: TextScaler.noScaling,
  );
}
