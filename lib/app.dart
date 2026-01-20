import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'routes/app_router.dart';
import 'providers/auth_provider.dart';
import 'providers/profile_provider.dart';
import 'providers/onboarding_provider.dart';
import 'providers/settings_provider.dart';
import 'ui/screens/main_screen.dart';
import 'ui/screens/auth/login_screen.dart';
import 'ui/screens/onboarding/onboarding_screen.dart';

/// Root application widget
/// Configures navigation, theming, and auth guard
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer4<
      AuthProvider,
      ProfileProvider,
      OnboardingProvider,
      SettingsProvider
    >(
      builder: (
        context,
        authProvider,
        profileProvider,
        onboardingProvider,
        settingsProvider,
        child,
      ) {
        // Get current accent color for theme customization
        final accentColor = settingsProvider.accentColor;

        return MaterialApp(
          title: 'GoHard - Workout Tracker',
          debugShowCheckedModeBanner: false,

          // Theme configuration - uses user preference and accent color
          theme: AppTheme.lightTheme.copyWith(
            colorScheme: AppTheme.lightTheme.colorScheme.copyWith(
              tertiary: accentColor.primary,
            ),
            floatingActionButtonTheme: FloatingActionButtonThemeData(
              backgroundColor: accentColor.primary,
              foregroundColor: Colors.white,
              elevation: 4,
              shape: const CircleBorder(),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 28,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            progressIndicatorTheme: ProgressIndicatorThemeData(
              color: accentColor.primary,
            ),
            chipTheme: AppTheme.lightTheme.chipTheme.copyWith(
              selectedColor: accentColor.primary,
            ),
            snackBarTheme: AppTheme.lightTheme.snackBarTheme.copyWith(
              actionTextColor: accentColor.primary,
            ),
          ),
          darkTheme: AppTheme.darkTheme.copyWith(
            colorScheme: AppTheme.darkTheme.colorScheme.copyWith(
              tertiary: accentColor.primary,
            ),
            floatingActionButtonTheme: FloatingActionButtonThemeData(
              backgroundColor: accentColor.primary,
              foregroundColor: Colors.white,
              elevation: 8,
              shape: const CircleBorder(),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 28,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            progressIndicatorTheme: ProgressIndicatorThemeData(
              color: accentColor.primary,
            ),
            chipTheme: AppTheme.darkTheme.chipTheme.copyWith(
              selectedColor: accentColor.primary,
            ),
            snackBarTheme: AppTheme.darkTheme.snackBarTheme.copyWith(
              actionTextColor: accentColor.primary,
            ),
          ),
          themeMode: profileProvider.themeMode,

          // Use home with conditional rendering instead of initialRoute
          home: _buildHome(authProvider, onboardingProvider),

          // Route generator for named navigation
          onGenerateRoute: AppRouter.generateRoute,

          // Navigator observers for debugging (can be removed in production)
          navigatorObservers: [_RouteObserver()],
        );
      },
    );
  }

  /// Build the appropriate home screen based on auth and onboarding state
  Widget _buildHome(
    AuthProvider authProvider,
    OnboardingProvider onboardingProvider,
  ) {
    // Show splash screen while checking authentication or onboarding
    if (authProvider.isInitializing || onboardingProvider.isLoading) {
      return const _SplashScreen();
    }

    // Show onboarding if not completed
    if (!onboardingProvider.hasCompletedOnboarding) {
      return OnboardingScreen(
        onComplete: () {
          // Trigger rebuild by notifying listeners (already done in provider)
        },
      );
    }

    // Navigate to main or login based on authentication status
    if (authProvider.isAuthenticated) {
      return const MainScreen();
    }

    return const LoginScreen();
  }
}

/// Splash screen shown while checking authentication status
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // App logo
            Image.asset('assets/logo.png', width: 120, height: 120),
            const SizedBox(height: 24),
            // App name
            Text(
              'GoHard',
              style: Theme.of(
                context,
              ).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 48),
            // Loading indicator
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

/// Route observer for debugging navigation
/// Can be removed in production builds
class _RouteObserver extends RouteObserver<PageRoute<dynamic>> {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    debugPrint('📍 Navigated to: ${route.settings.name}');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    debugPrint('📍 Popped from: ${route.settings.name}');
  }
}
