import 'package:flutter/material.dart';
import '../constants/colors.dart';

/// Premium typography system for GoHardAPP
/// Uses SpaceGrotesk for impactful stats and Inter for body text
///
/// PREMIUM DESIGN PRINCIPLES:
/// - Strong hierarchy with dramatic size contrast
/// - Headlines: 20-28px bold for impact
/// - Body: 13-15px for readability without competing
/// - Stats: Large, bold numbers that draw the eye
class AppTypography {
  AppTypography._();

  // ============ FONT FAMILIES ============

  /// Primary font for body text - Inter
  static const String fontFamilyBody = 'Inter';

  /// Display font for stats and numbers - SpaceGrotesk
  static const String fontFamilyStats = 'SpaceGrotesk';

  // ============ STAT TYPOGRAPHY (SpaceGrotesk) ============
  // Use for big numbers, counters, timers, achievements

  /// Huge stat display - 72px (for hero numbers) - INCREASED from 64
  static const TextStyle statHero = TextStyle(
    fontFamily: fontFamilyStats,
    fontSize: 72,
    fontWeight: FontWeight.w800,
    letterSpacing: -3.0,
    height: 1.0,
  );

  /// Large stat display - 56px (for primary stats) - INCREASED from 48
  static const TextStyle statLarge = TextStyle(
    fontFamily: fontFamilyStats,
    fontSize: 56,
    fontWeight: FontWeight.w800,
    letterSpacing: -2.0,
    height: 1.0,
  );

  /// Medium stat display - 40px (for secondary stats) - INCREASED from 32
  static const TextStyle statMedium = TextStyle(
    fontFamily: fontFamilyStats,
    fontSize: 40,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.5,
    height: 1.1,
  );

  /// Small stat display - 28px (for tertiary stats) - INCREASED from 24
  static const TextStyle statSmall = TextStyle(
    fontFamily: fontFamilyStats,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.8,
    height: 1.2,
  );

  /// Tiny stat display - 20px (for inline stats) - INCREASED from 18
  static const TextStyle statTiny = TextStyle(
    fontFamily: fontFamilyStats,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    height: 1.3,
  );

  // ============ TIMER TYPOGRAPHY ============

  /// Timer large - 56px (for active workout timer)
  static const TextStyle timerLarge = TextStyle(
    fontFamily: fontFamilyStats,
    fontSize: 56,
    fontWeight: FontWeight.w700,
    letterSpacing: 2.0,
    height: 1.0,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Timer medium - 40px (for rest timer)
  static const TextStyle timerMedium = TextStyle(
    fontFamily: fontFamilyStats,
    fontSize: 40,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.5,
    height: 1.0,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// Timer small - 28px (for inline timers)
  static const TextStyle timerSmall = TextStyle(
    fontFamily: fontFamilyStats,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.0,
    height: 1.0,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  // ============ BODY TYPOGRAPHY (Inter) ============
  // PREMIUM: Strong contrast between headlines and body text

  /// Display large - 36px (hero titles)
  static const TextStyle displayLarge = TextStyle(
    fontFamily: fontFamilyBody,
    fontSize: 36,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.2,
    height: 1.1,
  );

  /// Display medium - 28px (section titles)
  static const TextStyle displayMedium = TextStyle(
    fontFamily: fontFamilyBody,
    fontSize: 28,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.8,
    height: 1.2,
  );

  /// Display small - 22px (card titles)
  static const TextStyle displaySmall = TextStyle(
    fontFamily: fontFamilyBody,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    height: 1.25,
  );

  /// Headline - 20px (list item titles)
  static const TextStyle headline = TextStyle(
    fontFamily: fontFamilyBody,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    height: 1.3,
  );

  /// Title large - 17px (card subtitles, prominent text)
  static const TextStyle titleLarge = TextStyle(
    fontFamily: fontFamilyBody,
    fontSize: 17,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    height: 1.35,
  );

  /// Title medium - 15px (secondary titles)
  static const TextStyle titleMedium = TextStyle(
    fontFamily: fontFamilyBody,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
    height: 1.4,
  );

  /// Body large - 15px (primary body text)
  static const TextStyle bodyLarge = TextStyle(
    fontFamily: fontFamilyBody,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    height: 1.5,
  );

  /// Body medium - 14px (standard body text) - DECREASED from 15
  static const TextStyle bodyMedium = TextStyle(
    fontFamily: fontFamilyBody,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    height: 1.5,
  );

  /// Body small - 12px (secondary body text) - DECREASED from 13
  static const TextStyle bodySmall = TextStyle(
    fontFamily: fontFamilyBody,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
    height: 1.5,
  );

  /// Label large - 13px semibold (button text, emphasis)
  static const TextStyle labelLarge = TextStyle(
    fontFamily: fontFamilyBody,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
    height: 1.4,
  );

  /// Label medium - 11px medium (badges, chips)
  static const TextStyle labelMedium = TextStyle(
    fontFamily: fontFamilyBody,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.3,
    height: 1.4,
  );

  /// Label small - 10px (captions, metadata)
  static const TextStyle labelSmall = TextStyle(
    fontFamily: fontFamilyBody,
    fontSize: 10,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.4,
    height: 1.4,
  );

  // ============ PREMIUM CARD TYPOGRAPHY ============
  // Specifically designed for card layouts with strong hierarchy

  /// Card title - bold, attention-grabbing
  static const TextStyle cardTitle = TextStyle(
    fontFamily: fontFamilyBody,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    height: 1.3,
  );

  /// Card subtitle - secondary info
  static const TextStyle cardSubtitle = TextStyle(
    fontFamily: fontFamilyBody,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    height: 1.4,
  );

  /// Card meta - tertiary info (dates, counts)
  static const TextStyle cardMeta = TextStyle(
    fontFamily: fontFamilyBody,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
    height: 1.4,
  );

  // ============ ACHIEVEMENT TYPOGRAPHY ============

  /// Achievement title
  static const TextStyle achievementTitle = TextStyle(
    fontFamily: fontFamilyStats,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    height: 1.2,
  );

  /// Achievement description
  static const TextStyle achievementDescription = TextStyle(
    fontFamily: fontFamilyBody,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    height: 1.4,
  );

  // ============ STREAK TYPOGRAPHY ============

  /// Streak number
  static const TextStyle streakNumber = TextStyle(
    fontFamily: fontFamilyStats,
    fontSize: 48,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.0,
    height: 1.0,
  );

  /// Streak label
  static const TextStyle streakLabel = TextStyle(
    fontFamily: fontFamilyBody,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
    height: 1.3,
  );
}

/// Extension for easy typography access with theme colors
extension AppTypographyExtension on BuildContext {
  /// Get stat typography with current theme's text color
  TextStyle get statHero => AppTypography.statHero.copyWith(
    color: Theme.of(this).colorScheme.onSurface,
  );

  TextStyle get statLarge => AppTypography.statLarge.copyWith(
    color: Theme.of(this).colorScheme.onSurface,
  );

  TextStyle get statMedium => AppTypography.statMedium.copyWith(
    color: Theme.of(this).colorScheme.onSurface,
  );

  TextStyle get statSmall => AppTypography.statSmall.copyWith(
    color: Theme.of(this).colorScheme.onSurface,
  );

  TextStyle get statTiny => AppTypography.statTiny.copyWith(
    color: Theme.of(this).colorScheme.onSurface,
  );

  /// Get timer typography
  TextStyle get timerLarge => AppTypography.timerLarge.copyWith(
    color: Theme.of(this).colorScheme.onSurface,
  );

  TextStyle get timerMedium => AppTypography.timerMedium.copyWith(
    color: Theme.of(this).colorScheme.onSurface,
  );

  TextStyle get timerSmall => AppTypography.timerSmall.copyWith(
    color: Theme.of(this).colorScheme.onSurface,
  );

  /// Get streak typography with amber accent
  TextStyle get streakNumber =>
      AppTypography.streakNumber.copyWith(color: AppColors.accentAmber);

  TextStyle get streakLabel => AppTypography.streakLabel.copyWith(
    color:
        Theme.of(this).brightness == Brightness.dark
            ? AppColors.silver
            : AppColors.stone,
  );

  /// Get achievement typography
  TextStyle get achievementTitle => AppTypography.achievementTitle.copyWith(
    color: Theme.of(this).colorScheme.onSurface,
  );

  TextStyle get achievementDescription =>
      AppTypography.achievementDescription.copyWith(
        color:
            Theme.of(this).brightness == Brightness.dark
                ? AppColors.silver
                : AppColors.stone,
      );

  /// Stat with accent color (green)
  TextStyle get statAccent =>
      AppTypography.statLarge.copyWith(color: AppColors.accentGreen);

  /// Stat with amber color (streaks, highlights)
  TextStyle get statAmber =>
      AppTypography.statLarge.copyWith(color: AppColors.accentAmber);

  /// Stat with coral color (active workouts)
  TextStyle get statCoral =>
      AppTypography.statLarge.copyWith(color: AppColors.accentCoral);
}
