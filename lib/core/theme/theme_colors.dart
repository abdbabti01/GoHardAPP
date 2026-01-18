import 'package:flutter/material.dart';
import '../constants/colors.dart';

/// Extension on BuildContext for easy theme-aware color access
/// Premium fitness app color system
extension ThemeColors on BuildContext {
  /// Quick access to current theme's color scheme
  ColorScheme get colorScheme => Theme.of(this).colorScheme;

  /// Quick access to current theme's text theme
  TextTheme get textTheme => Theme.of(this).textTheme;

  /// Whether the current theme is dark mode
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  // ============ SURFACE COLORS ============

  /// Main scaffold/page background
  Color get scaffoldBackground => Theme.of(this).scaffoldBackgroundColor;

  /// Card/container surface color
  Color get surface => colorScheme.surface;

  /// Elevated surface (modals, dialogs, raised cards)
  Color get surfaceElevated => colorScheme.surfaceContainerHighest;

  /// Surface for input fields
  Color get inputSurface =>
      isDarkMode
          ? AppColors.darkSurfaceElevated
          : AppColors.lightSurfaceElevated;

  /// Highlighted/hover surface
  Color get surfaceHighlight =>
      isDarkMode
          ? AppColors.darkSurfaceHighlight
          : AppColors.lightSurfaceElevated;

  // ============ TEXT COLORS ============

  /// Primary text color (titles, important text)
  Color get textPrimary => colorScheme.onSurface;

  /// Secondary text color (subtitles, descriptions)
  Color get textSecondary => colorScheme.onSurfaceVariant;

  /// Tertiary/hint text color (placeholders, disabled)
  Color get textTertiary =>
      isDarkMode ? const Color(0xFF6B6B6B) : AppColors.iosGray5;

  /// Text on primary color buttons/surfaces
  Color get textOnPrimary => colorScheme.onPrimary;

  // ============ BORDER/DIVIDER COLORS ============

  /// Border color for cards, containers
  Color get border => isDarkMode ? const Color(0xFF2A2A2A) : AppColors.iosGray3;

  /// Subtle border for inputs, dividers
  Color get borderSubtle =>
      isDarkMode ? const Color(0xFF1E1E1E) : AppColors.iosGray2;

  /// Divider color
  Color get divider => Theme.of(this).dividerTheme.color ?? border;

  // ============ INTERACTIVE COLORS ============

  /// Primary action color - Electric Green
  Color get primary => colorScheme.primary;

  /// Secondary action color - Electric Blue
  Color get secondary => colorScheme.secondary;

  /// Accent/highlight color - Always Electric Green
  Color get accent => AppColors.goHardGreen;

  /// Blue accent for variety
  Color get accentBlue => AppColors.goHardBlue;

  /// Cyan accent for gradients
  Color get accentCyan => AppColors.goHardCyan;

  /// Selected/active state color
  Color get selected => AppColors.goHardGreen;

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
      isDarkMode ? AppColors.darkSurface : AppColors.lightSurface;

  /// Navigation bar selected item color - Electric Green
  Color get navBarSelected => AppColors.goHardGreen;

  /// Navigation bar unselected item color
  Color get navBarUnselected =>
      isDarkMode ? const Color(0xFF6B6B6B) : AppColors.iosGray6;

  /// FAB/action button background in nav bar - Electric Green
  Color get navBarFabBackground => AppColors.goHardGreen;

  /// FAB foreground color
  Color get navBarFabForeground => AppColors.goHardBlack;

  // ============ CHIP/TAG COLORS ============

  /// Chip background (unselected)
  Color get chipBackground =>
      isDarkMode
          ? AppColors.darkSurfaceElevated
          : AppColors.lightSurfaceElevated;

  /// Chip background (selected) - Electric Green
  Color get chipSelected => AppColors.goHardGreen;

  /// Chip text color
  Color get chipText => textPrimary;

  // ============ MESSAGE BUBBLE COLORS ============

  /// User message bubble background - Electric Green
  Color get userMessageBubble => AppColors.goHardGreen;

  /// User message text color
  Color get userMessageText => AppColors.goHardBlack;

  /// AI/other message bubble background
  Color get aiMessageBubble =>
      isDarkMode
          ? AppColors.darkSurfaceElevated
          : AppColors.lightSurfaceElevated;

  /// AI/other message text color
  Color get aiMessageText => textPrimary;

  // ============ CARD COLORS ============

  /// Card background
  Color get cardBackground => surface;

  /// Card border
  Color get cardBorder => border;

  /// Card with hover/selected state
  Color get cardSelected => surfaceHighlight;

  // ============ GRADIENT COLORS ============

  /// Primary gradient (Green to Cyan)
  LinearGradient get primaryGradient => AppColors.primaryGradient;

  /// Secondary gradient (Blue to Cyan)
  LinearGradient get secondaryGradient => AppColors.secondaryGradient;

  /// Success gradient
  LinearGradient get successGradient => AppColors.successGradient;

  /// Active/In-progress gradient
  LinearGradient get activeGradient => AppColors.activeGradient;
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
  Color get border => isDarkMode ? const Color(0xFF2A2A2A) : AppColors.iosGray3;
  Color get textPrimary => colorScheme.onSurface;
  Color get textSecondary => colorScheme.onSurfaceVariant;
  Color get accent => AppColors.goHardGreen;
  Color get accentBlue => AppColors.goHardBlue;
}
