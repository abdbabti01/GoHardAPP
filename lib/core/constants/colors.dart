import 'package:flutter/material.dart';

/// Premium fitness app color constants
/// Inspired by Hevy, Strong, Nike Training Club, Apple Fitness+
class AppColors {
  AppColors._(); // Private constructor to prevent instantiation

  // ============ PREMIUM NEUTRAL PALETTE (90% of UI) ============

  // Primary Surfaces
  static const Color charcoal = Color(0xFF1A1A1A); // Primary dark surfaces
  static const Color slate = Color(0xFF2D3436); // Secondary surfaces
  static const Color stone = Color(0xFF636E72); // Muted text
  static const Color silver = Color(0xFFB2BEC3); // Light text

  // Extended Neutrals
  static const Color obsidian = Color(0xFF0D0D0D); // Deepest black
  static const Color graphite = Color(0xFF242424); // Elevated dark surface
  static const Color ash = Color(0xFF3D4449); // Tertiary surface
  static const Color pewter = Color(0xFF8B959B); // Secondary text dark
  static const Color cloud = Color(0xFFDFE6E9); // Light mode surface
  static const Color snow = Color(0xFFF7F9FA); // Light mode background

  // ============ PREMIUM ACCENT - VIBRANT GREEN (10% of UI) ============

  // Use sparingly: buttons, progress, selected states, success indicators
  static const Color accentGreen = Color(0xFF4ADE80); // Vibrant green
  static const Color accentGreenMuted = Color(
    0xFF86EFAC,
  ); // Light green variant
  static const Color accentGreenDark = Color(0xFF22C55E); // Dark green variant
  static const Color accentGreenSubtle = Color(
    0xFF166534,
  ); // Very dark for backgrounds

  // ============ STATUS ACCENT COLORS ============

  static const Color accentAmber = Color(
    0xFFF59E0B,
  ); // Streaks, warnings, highlights
  static const Color accentCoral = Color(0xFFF97316); // Active workouts, energy
  static const Color accentRose = Color(
    0xFFF43F5E,
  ); // Errors, destructive actions
  static const Color accentSky = Color(
    0xFF0EA5E9,
  ); // Info, links, secondary accent

  // ============ THEME ACCENT - BLUE PALETTE (Sky Blue) ============

  static const Color accentBlue = Color(0xFF3B82F6); // Vibrant blue
  static const Color accentBlueMuted = Color(0xFF60A5FA); // Light blue variant
  static const Color accentBlueDark = Color(0xFF2563EB); // Dark blue variant
  static const Color accentBlueSubtle = Color(
    0xFF1D4ED8,
  ); // Very dark for backgrounds

  // ============ THEME ACCENT - YELLOW PALETTE (Light/Warm) ============

  static const Color accentYellow = Color(0xFFFBBF24); // Vibrant yellow/amber
  static const Color accentYellowMuted = Color(
    0xFFFCD34D,
  ); // Light yellow variant
  static const Color accentYellowDark = Color(0xFFF59E0B); // Dark amber variant
  static const Color accentYellowSubtle = Color(
    0xFFD97706,
  ); // Dark amber for backgrounds

  // ============ THEME ACCENT - PINK PALETTE (Rose) ============

  static const Color accentPink = Color(0xFFF472B6); // Vibrant pink/rose
  static const Color accentPinkMuted = Color(0xFFF9A8D4); // Light pink variant
  static const Color accentPinkDark = Color(0xFFEC4899); // Dark pink variant
  static const Color accentPinkSubtle = Color(
    0xFFBE185D,
  ); // Dark pink for backgrounds

  // ============ ACHIEVEMENT TIER COLORS ============

  static const Color tierBronze = Color(0xFFCD7F32);
  static const Color tierSilver = Color(0xFFC0C0C0);
  static const Color tierGold = Color(0xFFFFD700);
  static const Color tierPlatinum = Color(0xFFE5E4E2);

  // ============ LEGACY GOHARD BRAND COLORS (for compatibility) ============

  // Primary Brand - Electric Green (now used sparingly)
  static const Color goHardGreen = accentGreen; // Mapped to new accent
  static const Color goHardGreenLight = accentGreenMuted;
  static const Color goHardGreenDark = accentGreenDark;

  // Secondary Brand - Electric Blue
  static const Color goHardBlue = Color(0xFF2979FF); // Electric blue
  static const Color goHardBlueLight = Color(0xFF82B1FF); // Light variant
  static const Color goHardBlueDark = Color(0xFF2962FF); // Dark variant
  static const Color goHardCyan = Color(0xFF00E5FF); // Cyan for gradients

  // Accent Colors
  static const Color goHardOrange = accentCoral; // Mapped to new accent
  static const Color goHardAmber = accentAmber; // Mapped to new accent

  // Neutral Palette (legacy mappings)
  static const Color goHardBlack = Color(0xFF000000);
  static const Color goHardDarkGray = charcoal;
  static const Color goHardWhite = Color(0xFFFFFFFF);
  static const Color goHardSilver = silver;
  static const Color goHardLightGray = cloud;

  // ============ PREMIUM DARK MODE SURFACES ============

  static const Color darkBackground = obsidian; // Deep black background
  static const Color darkSurface = charcoal; // Card/container background
  static const Color darkSurfaceElevated = graphite; // Elevated cards, modals
  static const Color darkSurfaceHighlight = ash; // Hover/selected states

  // ============ PREMIUM LIGHT MODE SURFACES ============

  static const Color lightBackground = snow; // Soft white background
  static const Color lightSurface = Color(0xFFFFFFFF); // Card background
  static const Color lightSurfaceElevated = cloud; // Elevated surfaces

  // ============ GLASSMORPHISM ============

  static const Color glassWhite = Color(0x1AFFFFFF); // 10% white
  static const Color glassBorder = Color(0x33FFFFFF); // 20% white
  static const Color glassBlack = Color(0x1A000000); // 10% black

  // iOS System Colors (for compatibility)
  static const Color iosSystemBlue = Color(0xFF007AFF);
  static const Color iosSystemBlueLight = Color(0xFF5AC8FA);
  static const Color iosSystemBlueDark = Color(0xFF0051D5);

  static const Color iosSystemGreen = Color(0xFF34C759);
  static const Color iosSystemYellow = Color(0xFFFFCC00);
  static const Color iosSystemOrange = Color(0xFFFF9500);
  static const Color iosSystemRed = Color(0xFFFF3B30);
  static const Color iosSystemPurple = Color(0xFFAF52DE);

  // iOS Gray Scale (Light Mode)
  static const Color iosGray1 = Color(0xFFF2F2F7); // Background Secondary
  static const Color iosGray2 = Color(0xFFE5E5EA); // Separator Light
  static const Color iosGray3 = Color(0xFFD1D1D6); // Separator
  static const Color iosGray4 = Color(0xFFC7C7CC); // Border
  static const Color iosGray5 = Color(0xFFAEAEB2); // Tertiary Label
  static const Color iosGray6 = Color(0xFF8E8E93); // Secondary Label

  // iOS Label Colors (Light Mode)
  static const Color iosLabel = Color(0xFF000000);
  static const Color iosSecondaryLabel = Color(0x993C3C43); // 60% opacity
  static const Color iosTertiaryLabel = Color(0x4D3C3C43); // 30% opacity

  // iOS Backgrounds (Light Mode)
  static const Color iosSystemBackground = Color(0xFFFFFFFF);
  static const Color iosSecondarySystemBackground = Color(0xFFF2F2F7);
  static const Color iosGroupedBackground = Color(0xFFF2F2F7);

  // iOS Dark Mode Colors
  static const Color iosDarkLabel = Color(0xFFFFFFFF);
  static const Color iosDarkSecondaryLabel = Color(0x99EBEBF5);
  static const Color iosDarkTertiaryLabel = Color(0x4DEBEBF5);
  static const Color iosDarkSystemBackground = Color(0xFF000000);
  static const Color iosDarkSecondaryBackground = Color(0xFF1C1C1E);
  static const Color iosDarkGroupedBackground = Color(0xFF000000);
  static const Color iosDarkGray1 = Color(0xFF1C1C1E);
  static const Color iosDarkGray2 = Color(0xFF2C2C2E);
  static const Color iosDarkGray3 = Color(0xFF38383A);
  static const Color iosDarkGray4 = Color(0xFF48484A);

  // Primary Colors - GoHard Brand (Monochrome from logo)
  static const Color primary =
      goHardBlack; // Black for light mode (matches logo background)
  static const Color primaryDark =
      goHardWhite; // White for dark mode (matches logo text)
  static const Color secondary = goHardSilver; // Silver/gray accent
  static const Color accent = goHardDarkGray; // Dark gray for accents

  // Basic Colors
  static const Color white = Colors.white;
  static const Color black = Colors.black;
  static const Color magenta = Color(0xFFD600AA);
  static const Color midnightBlue = Color(0xFF190649);
  static const Color offBlack = Color(0xFF1F1F1F);

  // Gray Scale (Legacy compatibility)
  static const Color gray100 = Color(0xFFE1E1E1);
  static const Color gray200 = Color(0xFFC8C8C8);
  static const Color gray300 = Color(0xFFACACAC);
  static const Color gray400 = Color(0xFF919191);
  static const Color gray500 = Color(0xFF6E6E6E);
  static const Color gray600 = Color(0xFF404040);
  static const Color gray900 = Color(0xFF212121);
  static const Color gray950 = Color(0xFF141414);

  // Apple Fitness-Inspired Gradients
  static const Color fitnessGradientStart = Color(0xFFFA5A7D);
  static const Color fitnessGradientEnd = Color(0xFFFF8A5C);
  static const Color activityGradientStart = Color(0xFF7AFA4D);
  static const Color activityGradientEnd = Color(0xFF39E66B);

  // Surface Colors
  static const Color surfaceLight = Color(0xFFF2F2F7);
  static const Color surfaceDark = Color(0xFF1C1C1E);
  static const Color cardBackgroundLight = Color(0xFFFFFFFF);
  static const Color cardBackgroundDark = Color(0xFF2C2C2E);

  // Semantic Status Colors
  static const Color successGreen = Color(0xFF34C759);
  static const Color warningOrange = Color(0xFFFF9F0A);
  static const Color errorRed = Color(0xFFFF3B30);
  static const Color infoBlue = Color(0xFF007AFF);

  // Exercise Category Colors (from CategoryToColorConverter)
  static const Color strengthRed = Color(0xFFE53935);
  static const Color cardioBlue = Color(0xFF1E88E5);
  static const Color flexibilityGreen = Color(0xFF43A047);
  static const Color coreOrange = Color(0xFFFB8C00);
  static const Color defaultCategory = Color(0xFF9E9E9E);

  // ============ PREMIUM GRADIENT DEFINITIONS ============

  // Primary gradient - Subtle green accent (use sparingly)
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [accentGreenDark, accentGreen],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Secondary gradient - Neutral slate (for most UI)
  static const LinearGradient secondaryGradient = LinearGradient(
    colors: [slate, ash],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Success gradient - Green shades
  static const LinearGradient successGradient = LinearGradient(
    colors: [accentGreenDark, accentGreen],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Blue primary gradient
  static const LinearGradient blueGradient = LinearGradient(
    colors: [accentBlueDark, accentBlue],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Yellow primary gradient
  static const LinearGradient yellowGradient = LinearGradient(
    colors: [accentYellowDark, accentYellow],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Pink primary gradient
  static const LinearGradient pinkGradient = LinearGradient(
    colors: [accentPinkDark, accentPink],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Active/In-progress gradient - Coral/Amber energy
  static const LinearGradient activeGradient = LinearGradient(
    colors: [accentCoral, accentAmber],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Streak gradient - Amber warmth
  static const LinearGradient streakGradient = LinearGradient(
    colors: [accentAmber, Color(0xFFFBBF24)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Card gradient for dark mode (subtle)
  static const LinearGradient cardGradientDark = LinearGradient(
    colors: [charcoal, graphite],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Premium surface gradient (very subtle)
  static const LinearGradient surfaceGradient = LinearGradient(
    colors: [charcoal, Color(0xFF1F1F1F)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Shimmer/glow effect (muted green)
  static const LinearGradient glowGradient = LinearGradient(
    colors: [
      Color(0x004ADE80), // transparent green
      Color(0x334ADE80), // 20% green
      Color(0x004ADE80), // transparent green
    ],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  // Achievement tier gradients
  static const LinearGradient bronzeGradient = LinearGradient(
    colors: [Color(0xFFCD7F32), Color(0xFFB87333)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient silverGradient = LinearGradient(
    colors: [Color(0xFFE8E8E8), Color(0xFFC0C0C0)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient goldGradient = LinearGradient(
    colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient platinumGradient = LinearGradient(
    colors: [Color(0xFFE5E4E2), Color(0xFFD1D0CE)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Legacy gradients (for compatibility)
  static const LinearGradient fitnessGradient = LinearGradient(
    colors: [fitnessGradientStart, fitnessGradientEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient activityGradient = LinearGradient(
    colors: [activityGradientStart, activityGradientEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// Accent color theme options for the app
enum AccentColorTheme {
  green(
    name: 'Green',
    primary: AppColors.accentGreen,
    muted: AppColors.accentGreenMuted,
    dark: AppColors.accentGreenDark,
    subtle: AppColors.accentGreenSubtle,
  ),
  blue(
    name: 'Blue',
    primary: AppColors.accentBlue,
    muted: AppColors.accentBlueMuted,
    dark: AppColors.accentBlueDark,
    subtle: AppColors.accentBlueSubtle,
  ),
  yellow(
    name: 'Yellow',
    primary: AppColors.accentYellow,
    muted: AppColors.accentYellowMuted,
    dark: AppColors.accentYellowDark,
    subtle: AppColors.accentYellowSubtle,
  ),
  pink(
    name: 'Pink',
    primary: AppColors.accentPink,
    muted: AppColors.accentPinkMuted,
    dark: AppColors.accentPinkDark,
    subtle: AppColors.accentPinkSubtle,
  );

  const AccentColorTheme({
    required this.name,
    required this.primary,
    required this.muted,
    required this.dark,
    required this.subtle,
  });

  final String name;
  final Color primary;
  final Color muted;
  final Color dark;
  final Color subtle;

  /// Get the gradient for this accent color
  LinearGradient get gradient => LinearGradient(
    colors: [dark, primary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Parse from string (for storage)
  static AccentColorTheme fromString(String? value) {
    return AccentColorTheme.values.firstWhere(
      (e) => e.name.toLowerCase() == value?.toLowerCase(),
      orElse: () => AccentColorTheme.green,
    );
  }
}
