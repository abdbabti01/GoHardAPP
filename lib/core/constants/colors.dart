import 'package:flutter/material.dart';

/// Premium fitness app color constants
/// Inspired by Hevy, Strong, Nike Training Club, Apple Fitness+
class AppColors {
  AppColors._(); // Private constructor to prevent instantiation

  // ============ GOHARD PREMIUM BRAND COLORS ============

  // Primary Brand - Electric Green
  static const Color goHardGreen = Color(0xFF00E676); // Vibrant electric green
  static const Color goHardGreenLight = Color(0xFF69F0AE); // Light variant
  static const Color goHardGreenDark = Color(0xFF00C853); // Dark variant

  // Secondary Brand - Electric Blue
  static const Color goHardBlue = Color(0xFF2979FF); // Electric blue
  static const Color goHardBlueLight = Color(0xFF82B1FF); // Light variant
  static const Color goHardBlueDark = Color(0xFF2962FF); // Dark variant
  static const Color goHardCyan = Color(0xFF00E5FF); // Cyan for gradients

  // Accent Colors
  static const Color goHardOrange = Color(0xFFFF6D00); // Warning/active states
  static const Color goHardAmber = Color(0xFFFFAB00); // Highlights

  // Neutral Palette
  static const Color goHardBlack = Color(0xFF000000);
  static const Color goHardDarkGray = Color(0xFF1A1A1A);
  static const Color goHardWhite = Color(0xFFFFFFFF);
  static const Color goHardSilver = Color(0xFFB0B0B0);
  static const Color goHardLightGray = Color(0xFFE5E5E5);

  // ============ PREMIUM DARK MODE SURFACES ============

  static const Color darkBackground = Color(0xFF0A0A0A); // Deep black
  static const Color darkSurface = Color(0xFF141414); // Card background
  static const Color darkSurfaceElevated = Color(0xFF1E1E1E); // Elevated cards
  static const Color darkSurfaceHighlight = Color(0xFF282828); // Hover/selected

  // ============ PREMIUM LIGHT MODE SURFACES ============

  static const Color lightBackground = Color(0xFFF8F9FA); // Soft white
  static const Color lightSurface = Color(0xFFFFFFFF); // Card background
  static const Color lightSurfaceElevated = Color(0xFFF0F2F5); // Elevated

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

  // Primary gradient - Electric Green to Cyan
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [goHardGreen, goHardCyan],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Secondary gradient - Electric Blue
  static const LinearGradient secondaryGradient = LinearGradient(
    colors: [goHardBlue, goHardCyan],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Success gradient - Green shades
  static const LinearGradient successGradient = LinearGradient(
    colors: [goHardGreen, goHardGreenLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Active/In-progress gradient - Orange/Amber
  static const LinearGradient activeGradient = LinearGradient(
    colors: [goHardOrange, goHardAmber],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Card gradient for dark mode (subtle)
  static const LinearGradient cardGradientDark = LinearGradient(
    colors: [darkSurface, darkSurfaceElevated],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Shimmer/glow effect
  static const LinearGradient glowGradient = LinearGradient(
    colors: [
      Color(0x0000E676), // transparent green
      Color(0x3300E676), // 20% green
      Color(0x0000E676), // transparent green
    ],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
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
