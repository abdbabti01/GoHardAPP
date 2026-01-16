import 'package:flutter/material.dart';
import '../constants/colors.dart';

/// Extension on BuildContext for easy theme-aware color access
/// Use this instead of hardcoding colors to ensure light/dark mode consistency
extension ThemeColors on BuildContext {
  /// Quick access to current theme's color scheme
  ColorScheme get colorScheme => Theme.of(this).colorScheme;

  /// Quick access to current theme's text theme
  TextTheme get textTheme => Theme.of(this).textTheme;

  /// Whether the current theme is dark mode
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  // ============ SURFACE COLORS ============

  /// Main scaffold/page background
  /// Dark: #121212, Light: #FFFFFF
  Color get scaffoldBackground => Theme.of(this).scaffoldBackgroundColor;

  /// Card/container surface color
  /// Dark: #1C1C1E, Light: #FFFFFF
  Color get surface => colorScheme.surface;

  /// Elevated surface (modals, dialogs, raised cards)
  /// Dark: #2C2C2E, Light: #F2F2F7
  Color get surfaceElevated => colorScheme.surfaceContainerHighest;

  /// Surface for input fields
  /// Dark: #2C2C2E, Light: #F2F2F7
  Color get inputSurface =>
      isDarkMode ? AppColors.iosDarkGray2 : AppColors.iosGray1;

  // ============ TEXT COLORS ============

  /// Primary text color (titles, important text)
  /// Dark: White, Light: Black
  Color get textPrimary => colorScheme.onSurface;

  /// Secondary text color (subtitles, descriptions)
  /// Dark: #B0B0B0, Light: #3C3C43 (60%)
  Color get textSecondary => colorScheme.onSurfaceVariant;

  /// Tertiary/hint text color (placeholders, disabled)
  /// Dark: #8E8E93, Light: #3C3C43 (30%)
  Color get textTertiary =>
      isDarkMode ? AppColors.iosGray6 : AppColors.iosTertiaryLabel;

  /// Text on primary color buttons/surfaces
  Color get textOnPrimary => colorScheme.onPrimary;

  // ============ BORDER/DIVIDER COLORS ============

  /// Border color for cards, containers
  /// Dark: #38383A, Light: #D1D1D6
  Color get border => isDarkMode ? AppColors.iosDarkGray3 : AppColors.iosGray3;

  /// Subtle border for inputs, dividers
  /// Dark: #48484A, Light: #E5E5EA
  Color get borderSubtle =>
      isDarkMode ? AppColors.iosDarkGray4 : AppColors.iosGray2;

  /// Divider color
  Color get divider => Theme.of(this).dividerTheme.color ?? border;

  // ============ INTERACTIVE COLORS ============

  /// Primary action color (buttons, links, selections)
  /// Dark: Green (#34C759), Light: Black
  Color get primary => colorScheme.primary;

  /// Secondary action color
  Color get secondary => colorScheme.secondary;

  /// Accent/highlight color (always green for GoHard brand)
  Color get accent => AppColors.iosSystemGreen;

  /// Selected/active state color
  Color get selected =>
      isDarkMode ? AppColors.iosSystemGreen : AppColors.goHardBlack;

  /// Unselected/inactive state color
  Color get unselected => textTertiary;

  // ============ STATUS COLORS ============

  /// Success color (green)
  Color get success => AppColors.successGreen;

  /// Warning color (orange)
  Color get warning => AppColors.warningOrange;

  /// Error color (red)
  Color get error => colorScheme.error;

  /// Info color (blue)
  Color get info => AppColors.infoBlue;

  // ============ NAVIGATION BAR COLORS ============

  /// Navigation bar background
  Color get navBarBackground =>
      isDarkMode ? AppColors.iosDarkGray1 : AppColors.iosSystemBackground;

  /// Navigation bar selected item color
  Color get navBarSelected =>
      isDarkMode ? AppColors.iosSystemGreen : AppColors.goHardBlack;

  /// Navigation bar unselected item color
  Color get navBarUnselected => AppColors.iosGray6;

  /// FAB/action button background in nav bar
  Color get navBarFabBackground =>
      isDarkMode ? AppColors.iosDarkGray2 : AppColors.goHardBlack;

  // ============ CHIP/TAG COLORS ============

  /// Chip background (unselected)
  Color get chipBackground =>
      isDarkMode ? AppColors.iosDarkGray2 : AppColors.iosGray1;

  /// Chip background (selected)
  Color get chipSelected =>
      isDarkMode ? AppColors.iosSystemGreen : AppColors.goHardBlack;

  /// Chip text color
  Color get chipText => textPrimary;

  // ============ MESSAGE BUBBLE COLORS ============

  /// User message bubble background
  Color get userMessageBubble => primary;

  /// User message text color
  Color get userMessageText => textOnPrimary;

  /// AI/other message bubble background
  Color get aiMessageBubble =>
      isDarkMode ? AppColors.iosDarkGray2 : AppColors.iosGray1;

  /// AI/other message text color
  Color get aiMessageText => textPrimary;

  // ============ CARD COLORS ============

  /// Card background
  Color get cardBackground => surface;

  /// Card border
  Color get cardBorder => border;

  /// Card with hover/selected state
  Color get cardSelected =>
      isDarkMode ? AppColors.iosDarkGray2 : AppColors.iosGray1;
}

/// Helper class for getting theme colors without context
/// Useful in CustomPainters and other non-widget code
class ThemeColorHelper {
  final BuildContext context;

  ThemeColorHelper(this.context);

  bool get isDarkMode => Theme.of(context).brightness == Brightness.dark;
  ColorScheme get colorScheme => Theme.of(context).colorScheme;

  Color get surface => colorScheme.surface;
  Color get surfaceElevated => colorScheme.surfaceContainerHighest;
  Color get border => isDarkMode ? AppColors.iosDarkGray3 : AppColors.iosGray3;
  Color get textPrimary => colorScheme.onSurface;
  Color get textSecondary => colorScheme.onSurfaceVariant;
}
