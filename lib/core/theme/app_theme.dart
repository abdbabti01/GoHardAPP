import 'package:flutter/material.dart';
import '../constants/colors.dart';

/// Premium fitness app theme configuration
/// Inspired by Hevy, Strong, Nike Training Club, Apple Fitness+
class AppTheme {
  AppTheme._(); // Private constructor to prevent instantiation

  /// Light theme configuration - Clean, modern, premium
  /// Neutrals dominate (90%), green accent used sparingly (10%)
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,

      // Color Scheme - Premium Neutrals with Green Accent
      colorScheme: ColorScheme.light(
        primary: AppColors.charcoal, // Neutral primary for most UI
        secondary: AppColors.slate, // Secondary surfaces
        tertiary: AppColors.accentGreen, // Green accent (sparingly)
        error: AppColors.accentRose, // Error states
        surface: AppColors.lightSurface,
        surfaceContainerHighest: AppColors.lightSurfaceElevated,
        onPrimary: AppColors.goHardWhite,
        onSecondary: AppColors.goHardWhite,
        onTertiary: AppColors.charcoal,
        onError: AppColors.goHardWhite,
        onSurface: AppColors.charcoal,
        onSurfaceVariant: AppColors.stone,
      ),

      // Scaffold - Soft white background
      scaffoldBackgroundColor: AppColors.lightBackground,

      // AppBar - Clean with bold typography
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.lightBackground,
        foregroundColor: AppColors.goHardBlack,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: AppColors.goHardBlack,
          fontSize: 32,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
      ),

      // Card - Clean with subtle shadow
      cardTheme: CardTheme(
        color: AppColors.lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.iosGray2.withValues(alpha: 0.5)),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),

      // Bottom Navigation Bar - Neutral with green accent for selected
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.lightSurface,
        selectedItemColor: AppColors.charcoal, // Neutral selected
        unselectedItemColor: AppColors.stone, // Muted unselected
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      // Floating Action Button - Primary action (green accent)
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.accentGreen, // Green for primary action
        foregroundColor: AppColors.charcoal,
        elevation: 4,
        shape: const CircleBorder(),
        extendedTextStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),

      // Input Decoration
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.lightSurfaceElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.charcoal, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.accentRose, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
      ),

      // Elevated Button - Primary action (green accent for CTAs)
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accentGreen, // Green for primary CTAs
          foregroundColor: AppColors.charcoal,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 28),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ),

      // Text Button - Neutral with subtle green for links
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.charcoal, // Neutral text buttons
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),

      // Text Theme - Bolder typography
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 40,
          fontWeight: FontWeight.w800,
          color: AppColors.goHardBlack,
          letterSpacing: -1.0,
        ),
        displayMedium: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          color: AppColors.goHardBlack,
          letterSpacing: -0.5,
        ),
        displaySmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: AppColors.goHardBlack,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.goHardBlack,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.goHardBlack,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.goHardBlack,
        ),
        bodyLarge: TextStyle(fontSize: 17, color: AppColors.goHardBlack),
        bodyMedium: TextStyle(fontSize: 15, color: AppColors.iosGray6),
        bodySmall: TextStyle(fontSize: 13, color: AppColors.iosGray5),
      ),

      // Divider
      dividerTheme: const DividerThemeData(
        color: AppColors.iosGray2,
        thickness: 0.5,
        space: 1,
      ),

      // Chip - Modern rounded with green for selected
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.lightSurfaceElevated,
        selectedColor: AppColors.accentGreen, // Green accent for selected
        labelStyle: const TextStyle(
          color: AppColors.charcoal,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide.none,
      ),

      // Dialog
      dialogTheme: DialogTheme(
        backgroundColor: AppColors.lightSurface,
        elevation: 16,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),

      // SnackBar
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.charcoal,
        contentTextStyle: const TextStyle(color: Colors.white),
        actionTextColor: AppColors.accentGreen, // Green for actions
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),

      // Progress Indicator - Green accent
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accentGreen, // Green for progress
      ),
    );
  }

  /// Dark theme configuration - Premium dark UI
  /// Neutrals dominate (90%), green accent used sparingly (10%)
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,

      // Color Scheme - Premium Neutrals with Green Accent
      colorScheme: const ColorScheme.dark(
        primary: AppColors.silver, // Light neutral for dark mode
        secondary: AppColors.pewter, // Secondary text/elements
        tertiary: AppColors.accentGreen, // Green accent (sparingly)
        error: AppColors.accentRose,
        surface: AppColors.darkSurface,
        surfaceContainerHighest: AppColors.darkSurfaceElevated,
        onPrimary: AppColors.charcoal,
        onSecondary: AppColors.charcoal,
        onTertiary: AppColors.charcoal,
        onError: Colors.white,
        onSurface: Colors.white,
        onSurfaceVariant: AppColors.silver,
      ),

      // Scaffold - Deep black background
      scaffoldBackgroundColor: AppColors.darkBackground,

      // AppBar - Bold typography
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.darkBackground,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 32,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
      ),

      // Card - Dark surface with subtle border
      cardTheme: CardTheme(
        color: AppColors.darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.glassBorder.withValues(alpha: 0.1)),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),

      // Bottom Navigation Bar - Neutral with subtle selection
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.darkSurface,
        selectedItemColor: Colors.white, // White for selected
        unselectedItemColor: AppColors.stone, // Muted for unselected
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      // Floating Action Button - Primary action (green accent)
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.accentGreen, // Green for primary action
        foregroundColor: AppColors.charcoal,
        elevation: 8,
        shape: const CircleBorder(),
        extendedTextStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),

      // Input Decoration - Dark with subtle focus
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkSurfaceElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.silver, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.accentRose, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        hintStyle: const TextStyle(color: AppColors.stone),
      ),

      // Elevated Button - Primary action (green accent for CTAs)
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accentGreen, // Green for primary CTAs
          foregroundColor: AppColors.charcoal,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 28),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ),

      // Outlined Button - Neutral outline
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: AppColors.ash, width: 2),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 28),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),

      // Text Button - Neutral
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: Colors.white, // Neutral text buttons
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),

      // Text Theme - Bold white text
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 40,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: -1.0,
        ),
        displayMedium: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: -0.5,
        ),
        displaySmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        bodyLarge: TextStyle(fontSize: 17, color: Colors.white),
        bodyMedium: TextStyle(fontSize: 15, color: Color(0xFFB0B0B0)),
        bodySmall: TextStyle(fontSize: 13, color: Color(0xFF8E8E93)),
      ),

      // Divider
      dividerTheme: const DividerThemeData(
        color: Color(0xFF2A2A2A),
        thickness: 0.5,
        space: 1,
      ),

      // Chip - Dark with green accent for selected
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.darkSurfaceElevated,
        selectedColor: AppColors.accentGreen, // Green accent for selected
        labelStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
        secondaryLabelStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide.none,
      ),

      // Dialog - Dark with subtle shadow
      dialogTheme: DialogTheme(
        backgroundColor: AppColors.darkSurface,
        elevation: 24,
        shadowColor: Colors.black.withValues(alpha: 0.3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),

      // SnackBar
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.darkSurfaceElevated,
        contentTextStyle: const TextStyle(color: Colors.white),
        actionTextColor: AppColors.accentGreen, // Green for actions
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),

      // Progress Indicator - Green accent
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accentGreen, // Green for progress
      ),
    );
  }
}
