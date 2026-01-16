import 'package:flutter/material.dart';
import '../constants/colors.dart';

/// App theme configuration matching MAUI app design
class AppTheme {
  AppTheme._(); // Private constructor to prevent instantiation

  /// Light theme configuration
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,

      // Color Scheme - GoHard Brand
      colorScheme: ColorScheme.light(
        primary: AppColors.goHardBlack,
        secondary: AppColors.iosSystemGreen,
        tertiary: AppColors.goHardDarkGray,
        error: AppColors.errorRed,
        surface: AppColors.iosSystemBackground,
        surfaceContainerHighest: AppColors.iosGray1,
        onPrimary: AppColors.goHardWhite,
        onSecondary: AppColors.goHardWhite,
        onTertiary: AppColors.goHardWhite,
        onError: AppColors.goHardWhite,
        onSurface: AppColors.goHardBlack,
        onSurfaceVariant: AppColors.goHardDarkGray,
      ),

      // Scaffold
      scaffoldBackgroundColor: AppColors.iosSystemBackground,

      // AppBar
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.iosSystemBackground,
        foregroundColor: AppColors.iosLabel,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.iosLabel,
          fontSize: 34,
          fontWeight: FontWeight.bold,
        ),
      ),

      // Card
      cardTheme: CardTheme(
        color: AppColors.cardBackgroundLight,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      ),

      // Bottom Navigation Bar
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.iosSystemBackground,
        selectedItemColor: AppColors.goHardBlack,
        unselectedItemColor: AppColors.iosGray6,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      // Floating Action Button
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.goHardBlack,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: CircleBorder(),
      ),

      // Input Decoration
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.iosGray1,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.goHardBlack, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.errorRed, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),

      // Elevated Button
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.goHardBlack,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),

      // Text Button
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.goHardBlack,
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),

      // Text Theme
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.bold,
          color: AppColors.iosLabel,
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: AppColors.iosLabel,
        ),
        displaySmall: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: AppColors.iosLabel,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.iosLabel,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppColors.iosLabel,
        ),
        bodyLarge: TextStyle(fontSize: 17, color: AppColors.iosLabel),
        bodyMedium: TextStyle(fontSize: 15, color: AppColors.iosSecondaryLabel),
        bodySmall: TextStyle(fontSize: 13, color: AppColors.iosTertiaryLabel),
      ),

      // Divider
      dividerTheme: const DividerThemeData(
        color: AppColors.iosGray3,
        thickness: 0.5,
        space: 1,
      ),

      // Chip
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.iosGray1,
        selectedColor: AppColors.goHardBlack,
        labelStyle: const TextStyle(color: AppColors.iosLabel),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  /// Dark theme configuration - Smooth dark UI with soft elevation
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,

      // Color Scheme - Dark with green accents matching nav bar
      colorScheme: const ColorScheme.dark(
        primary: AppColors.iosSystemGreen, // Green accent color
        secondary: AppColors.iosSystemGreen,
        tertiary: AppColors.gray400,
        error: AppColors.errorRed,
        surface: Color(
          0xFF1C1C1E,
        ), // Dark grey for cards (grey.shade900 equivalent)
        surfaceContainerHighest: Color(
          0xFF2C2C2E,
        ), // Darker grey for elevated cards
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onTertiary: Colors.white,
        onError: Colors.white,
        onSurface: Colors.white,
        onSurfaceVariant: Color(0xFFB0B0B0), // Light grey text
      ),

      // Scaffold - Very dark background
      scaffoldBackgroundColor: const Color(
        0xFF121212,
      ), // Almost black background
      // AppBar - Matches scaffold with no elevation
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF121212),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0, // No elevation when scrolled
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 32,
          fontWeight: FontWeight.bold,
        ),
      ),

      // Card - Dark grey with soft elevation
      cardTheme: CardTheme(
        color: const Color(0xFF1C1C1E), // grey.shade900 equivalent
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),

      // Bottom Navigation Bar - Transparent (custom implementation in main_screen.dart)
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        selectedItemColor: AppColors.iosSystemGreen,
        unselectedItemColor: Color(0xFF9E9E9E),
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      // Floating Action Button - Green with soft elevation
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.iosSystemGreen,
        foregroundColor: Colors.white,
        elevation: 6,
        shape: CircleBorder(),
      ),

      // Input Decoration - Dark inputs with green focus
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF2C2C2E),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: AppColors.iosSystemGreen,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.errorRed, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        hintStyle: const TextStyle(color: Color(0xFF8E8E93)),
      ),

      // Elevated Button - Green buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.iosSystemGreen,
          foregroundColor: Colors.white,
          elevation: 2,
          shadowColor: Colors.black.withValues(alpha: 0.2),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),

      // Outlined Button - Green outline
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.iosSystemGreen,
          side: const BorderSide(color: AppColors.iosSystemGreen, width: 2),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),

      // Text Button - Green text
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.iosSystemGreen,
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),

      // Text Theme - White/grey text on dark background
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        displaySmall: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        bodyLarge: TextStyle(fontSize: 17, color: Colors.white),
        bodyMedium: TextStyle(
          fontSize: 15,
          color: Color(0xFFB0B0B0), // Light grey
        ),
        bodySmall: TextStyle(
          fontSize: 13,
          color: Color(0xFF8E8E93), // Medium grey
        ),
      ),

      // Divider - Subtle dark dividers
      dividerTheme: const DividerThemeData(
        color: Color(0xFF38383A),
        thickness: 0.5,
        space: 1,
      ),

      // Chip - Dark chips with green selection
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF2C2C2E),
        selectedColor: AppColors.iosSystemGreen,
        labelStyle: const TextStyle(color: Colors.white),
        secondaryLabelStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide.none,
      ),

      // Dialog - Dark dialogs with soft elevation
      dialogTheme: DialogTheme(
        backgroundColor: const Color(0xFF1C1C1E),
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      // SnackBar - Dark with green action
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF2C2C2E),
        contentTextStyle: const TextStyle(color: Colors.white),
        actionTextColor: AppColors.iosSystemGreen,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),

      // Progress Indicator - Green
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.iosSystemGreen,
      ),
    );
  }
}
