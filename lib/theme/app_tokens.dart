import 'package:flutter/material.dart';

/// Premium dark design tokens for MarketCoach.
///
/// Centralises colors, spacing, radius, and typography so every screen
/// consumes a single source of truth. The redesign targets a tighter
/// teal/green accent on a near-black canvas with semantic bull/bear/caution
/// signal colors and a soft glow on the primary accent.
///
/// Usage:
///   Container(color: AppColors.bg)
///   BorderRadius.circular(AppRadius.card)
///   Text('LIVE', style: AppText.micro)
class AppColors {
  AppColors._();

  // Canvas ------------------------------------------------------------------
  /// Primary app background — near-black with a hint of blue so the teal
  /// accent feels grounded rather than floating.
  static const Color bg = Color(0xFF080C12);

  /// Slightly elevated canvas used behind hero cards for a soft vignette.
  static const Color bgElevated = Color(0xFF0C121A);

  // Surfaces ----------------------------------------------------------------
  /// Default card fill.
  static const Color card = Color(0xFF111A22);

  /// Inner tile / nested card fill.
  static const Color cardInner = Color(0xFF162029);

  /// Hairline border between cards and canvas.
  static const Color border = Color(0xFF1C2732);

  /// Subtle divider inside cards.
  static const Color divider = Color(0xFF1F2A36);

  // Accent ------------------------------------------------------------------
  /// Brand primary — muted teal for surfaces and fills.
  static const Color accent = Color(0xFF12A28C);

  /// Brighter teal used for hover / glow / highlight states.
  static const Color accentBright = Color(0xFF00D4AA);

  /// Very faint accent wash for backgrounds of teal-accented panels.
  static const Color accentWash = Color(0x1412A28C);

  // Signals -----------------------------------------------------------------
  static const Color bullish = Color(0xFF00D88F);
  static const Color bullishBg = Color(0x2600D88F);
  static const Color bearish = Color(0xFFEF4E4E);
  static const Color bearishBg = Color(0x26EF4E4E);
  static const Color neutral = Color(0xFF8A97A8);
  static const Color neutralBg = Color(0x268A97A8);
  static const Color caution = Color(0xFFF5A623);
  static const Color cautionBg = Color(0x26F5A623);

  // Text --------------------------------------------------------------------
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB3BDCC);
  static const Color textMuted = Color(0xFF6A7689);
  static const Color textFaint = Color(0xFF475161);
}

/// Consistent spacing scale. 4pt base grid.
class AppSpacing {
  AppSpacing._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double screenPad = 20;
}

/// Corner radii.
class AppRadius {
  AppRadius._();

  static const double chip = 999; // fully rounded pill
  static const double tile = 12;
  static const double card = 20;
  static const double hero = 24;
  static const double nav = 28;
}

/// Typography scale. Uses system sans-serif with tightened letter-spacing
/// to approximate the Inter / SF Pro look used in the mocks.
class AppText {
  AppText._();

  static const TextStyle display = TextStyle(
    fontSize: 44,
    fontWeight: FontWeight.w300,
    color: AppColors.textPrimary,
    letterSpacing: -1.2,
    height: 1.05,
  );

  static const TextStyle h1 = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.8,
    height: 1.1,
  );

  static const TextStyle h2 = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.4,
  );

  static const TextStyle h3 = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: -0.2,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.4,
  );

  static const TextStyle bodyStrong = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.textMuted,
  );

  /// Small, uppercase, tracked — "PAPER ACCOUNT · VIRTUAL $1M" style labels.
  static const TextStyle overline = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: AppColors.textMuted,
    letterSpacing: 1.1,
  );

  /// "LIVE", "CAUTION" badge text.
  static const TextStyle micro = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
  );

  /// Large monetary numerals — thin weight with negative tracking for the
  /// premium "terminal" feel.
  static const TextStyle numeralXL = TextStyle(
    fontSize: 44,
    fontWeight: FontWeight.w300,
    color: AppColors.textPrimary,
    letterSpacing: -1.5,
    height: 1,
  );

  static const TextStyle numeralL = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: -0.6,
    height: 1,
  );

  static const TextStyle numeralM = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.3,
  );
}

/// Reusable shadows.
class AppShadow {
  AppShadow._();

  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x66000000),
      blurRadius: 20,
      offset: Offset(0, 8),
    ),
  ];

  static const List<BoxShadow> accentGlow = [
    BoxShadow(
      color: Color(0x3312A28C),
      blurRadius: 24,
      offset: Offset(0, 6),
    ),
  ];

  static const List<BoxShadow> navFloat = [
    BoxShadow(
      color: Color(0x99000000),
      blurRadius: 24,
      offset: Offset(0, -8),
    ),
  ];
}
