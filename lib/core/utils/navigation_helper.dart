import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../routes/route_names.dart';
import '../services/tab_navigation_service.dart';

/// Navigation utility class for standardized navigation patterns
class NavigationHelper {
  /// Switch to a specific tab on the main screen
  /// Uses TabNavigationService to avoid duplicate Main Screen instances
  static void switchToTab(
    BuildContext context,
    int tabIndex, {
    int? subTabIndex,
  }) {
    context.read<TabNavigationService>().switchTab(
      tabIndex,
      subTabIndex: subTabIndex,
    );
  }

  /// Navigate to main screen with specific tab and clear entire stack
  /// Use sparingly - only when you need to reset navigation completely (e.g., logout)
  static void navigateToTabAndClearStack(
    BuildContext context,
    int tabIndex, {
    int? subTabIndex,
  }) {
    Navigator.of(context).pushNamedAndRemoveUntil(
      RouteNames.main,
      (route) => false,
      arguments: {'tab': tabIndex, 'subTab': subTabIndex},
    );
  }

  /// Navigate after completing a workout
  /// Pops until we find sessions or main screen for consistent behavior
  static void navigateAfterWorkoutComplete(BuildContext context) {
    Navigator.of(context).popUntil((route) {
      return route.settings.name == RouteNames.sessions ||
          route.settings.name == RouteNames.main ||
          route.isFirst;
    });
  }

  /// Show confirmation before destructive navigation
  /// Returns true if user confirmed, false otherwise
  static Future<bool> confirmDestructiveNavigation(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = 'Leave',
    String cancelText = 'Cancel',
  }) async {
    return await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: Text(title),
                content: Text(message),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(cancelText),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    child: Text(confirmText),
                  ),
                ],
              ),
        ) ??
        false;
  }

  /// Pop back to main screen
  /// Useful when deep in navigation stack and want to return home
  static void popToMain(BuildContext context) {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// Pop back to a specific named route, or main screen if not found
  static void popToRoute(BuildContext context, String routeName) {
    Navigator.of(context).popUntil((route) {
      return route.settings.name == routeName || route.isFirst;
    });
  }

  /// Navigate to a route and remove all routes until a specific route
  /// Useful for authentication flows or major state changes
  static Future<T?> pushNamedAndRemoveUntil<T>(
    BuildContext context,
    String routeName, {
    String? removeUntilRoute,
    Object? arguments,
  }) {
    return Navigator.of(context).pushNamedAndRemoveUntil<T>(
      routeName,
      removeUntilRoute != null
          ? (route) => route.settings.name == removeUntilRoute
          : (route) => route.isFirst,
      arguments: arguments,
    );
  }

  /// Replace current route with a new route
  /// Useful for redirects or replacing forms
  static Future<T?> pushReplacementNamed<T, TO>(
    BuildContext context,
    String routeName, {
    Object? arguments,
    TO? result,
  }) {
    return Navigator.of(context).pushReplacementNamed<T, TO>(
      routeName,
      arguments: arguments,
      result: result,
    );
  }
}
