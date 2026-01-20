import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/colors.dart';
import '../../providers/settings_provider.dart';

/// Extension on BuildContext for easy theme-aware color access
/// Premium fitness app color system - Neutrals dominate (90%), accent color (10%)
extension ThemeColors on BuildContext {
  /// Get the current accent color theme from SettingsProvider
  AccentColorTheme get _accentTheme {
    try {
      return Provider.of<SettingsProvider>(this, listen: false).accentColor;
    } catch (_) {
      return AccentColorTheme.green; // Fallback if provider not available
    }
  }

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
  Color get textTertiary => isDarkMode ? AppColors.stone : AppColors.pewter;

  /// Text on primary color buttons/surfaces
  Color get textOnPrimary => colorScheme.onPrimary;

  // ============ BORDER/DIVIDER COLORS ============

  /// Border color for cards, containers
  Color get border => isDarkMode ? AppColors.ash : AppColors.cloud;

  /// Subtle border for inputs, dividers
  Color get borderSubtle =>
      isDarkMode ? AppColors.graphite : AppColors.iosGray2;

  /// Divider color
  Color get divider => Theme.of(this).dividerTheme.color ?? border;

  // ============ INTERACTIVE COLORS ============

  /// Primary action color - Neutral (use accent for CTAs)
  Color get primary => colorScheme.primary;

  /// Secondary action color
  Color get secondary => colorScheme.secondary;

  /// Accent/highlight color - Dynamic based on user preference (use sparingly 10%)
  Color get accent => _accentTheme.primary;

  /// Accent muted variant
  Color get accentMuted => _accentTheme.muted;

  /// Accent dark variant
  Color get accentDark => _accentTheme.dark;

  /// Accent subtle variant (for backgrounds)
  Color get accentSubtle => _accentTheme.subtle;

  /// Blue accent for variety
  Color get accentBlue => AppColors.accentSky;

  /// Amber accent for streaks/highlights
  Color get accentAmber => AppColors.accentAmber;

  /// Coral accent for active states
  Color get accentCoral => AppColors.accentCoral;

  /// Selected/active state color - Dynamic accent
  Color get selected => _accentTheme.primary;

  /// Unselected/inactive state color
  Color get unselected => textTertiary;

  // ============ STATUS COLORS ============

  /// Success color (dynamic accent)
  Color get success => _accentTheme.primary;

  /// Warning color (amber)
  Color get warning => AppColors.accentAmber;

  /// Error color (rose)
  Color get error => AppColors.accentRose;

  /// Info color (sky blue)
  Color get info => AppColors.accentSky;

  // ============ NAVIGATION BAR COLORS ============

  /// Navigation bar background
  Color get navBarBackground =>
      isDarkMode ? AppColors.darkSurface : AppColors.lightSurface;

  /// Navigation bar selected item color - Neutral
  Color get navBarSelected => isDarkMode ? Colors.white : AppColors.charcoal;

  /// Navigation bar unselected item color
  Color get navBarUnselected => AppColors.stone;

  /// FAB/action button background - Dynamic accent
  Color get navBarFabBackground => _accentTheme.primary;

  /// FAB foreground color
  Color get navBarFabForeground => AppColors.charcoal;

  // ============ CHIP/TAG COLORS ============

  /// Chip background (unselected)
  Color get chipBackground =>
      isDarkMode
          ? AppColors.darkSurfaceElevated
          : AppColors.lightSurfaceElevated;

  /// Chip background (selected) - Dynamic accent
  Color get chipSelected => _accentTheme.primary;

  /// Chip text color
  Color get chipText => textPrimary;

  // ============ MESSAGE BUBBLE COLORS ============

  /// User message bubble background - Neutral slate
  Color get userMessageBubble =>
      isDarkMode ? AppColors.slate : AppColors.charcoal;

  /// User message text color
  Color get userMessageText => Colors.white;

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

  /// Primary gradient (Dynamic accent - use sparingly)
  LinearGradient get primaryGradient => _accentTheme.gradient;

  /// Secondary gradient (Neutral slate)
  LinearGradient get secondaryGradient => AppColors.secondaryGradient;

  /// Success gradient (Dynamic accent)
  LinearGradient get successGradient => _accentTheme.gradient;

  /// Active/In-progress gradient (Coral/Amber)
  LinearGradient get activeGradient => AppColors.activeGradient;

  /// Streak gradient (Amber warmth)
  LinearGradient get streakGradient => AppColors.streakGradient;

  // ============ ACHIEVEMENT TIER COLORS ============

  /// Bronze tier color
  Color get tierBronze => AppColors.tierBronze;

  /// Silver tier color
  Color get tierSilver => AppColors.tierSilver;

  /// Gold tier color
  Color get tierGold => AppColors.tierGold;

  /// Platinum tier color
  Color get tierPlatinum => AppColors.tierPlatinum;
}

/// Helper class for getting theme colors without context
/// Useful in CustomPainters and other non-widget code
class ThemeColorHelper {
  final BuildContext context;

  ThemeColorHelper(this.context);

  bool get isDarkMode => Theme.of(context).brightness == Brightness.dark;
  ColorScheme get colorScheme => Theme.of(context).colorScheme;

  AccentColorTheme get _accentTheme {
    try {
      return Provider.of<SettingsProvider>(context, listen: false).accentColor;
    } catch (_) {
      return AccentColorTheme.green;
    }
  }

  Color get surface => colorScheme.surface;
  Color get surfaceElevated => colorScheme.surfaceContainerHighest;
  Color get border => isDarkMode ? AppColors.ash : AppColors.cloud;
  Color get textPrimary => colorScheme.onSurface;
  Color get textSecondary => colorScheme.onSurfaceVariant;
  Color get accent => _accentTheme.primary;
  Color get accentMuted => _accentTheme.muted;
  Color get accentDark => _accentTheme.dark;
  Color get accentAmber => AppColors.accentAmber;
  Color get accentCoral => AppColors.accentCoral;
  Color get accentBlue => AppColors.accentSky;
}
