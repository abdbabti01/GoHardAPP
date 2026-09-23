// QA pass 2 (complete-app-testing), Phase 5 - Accessibility.
//
// Uses Flutter's own accessibility guideline checkers (not Maestro, which
// cannot see the Flutter semantics tree in this project - see
// maestro/README.md) against representative screens: touch-target size,
// text contrast, and that every tappable target has a semantic label.
// This is a real, evidence-based accessibility check (not a TalkBack manual
// pass, which is NOT TESTED in this cycle - see the QA report).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/models/workout_stats.dart';
import 'package:go_hard_app/providers/account_deletion_provider.dart';
import 'package:go_hard_app/providers/body_metrics_provider.dart';
import 'package:go_hard_app/ui/screens/auth/login_screen.dart';
import 'package:go_hard_app/ui/screens/auth/signup_screen.dart';
import 'package:go_hard_app/ui/screens/body_metrics/body_metrics_screen.dart';
import 'package:go_hard_app/ui/screens/onboarding/pages/welcome_page.dart';
import 'package:go_hard_app/ui/screens/settings/delete_account_screen.dart';
import 'package:go_hard_app/ui/widgets/charts/progress_line_chart.dart';
import 'package:go_hard_app/ui/widgets/charts/volume_chart.dart';
import 'package:go_hard_app/ui/widgets/common/error_state.dart';
import 'package:go_hard_app/ui/widgets/sessions/status_badge.dart';
import 'package:go_hard_app/providers/auth_provider.dart';
import 'package:go_hard_app/core/theme/app_theme.dart';

import '../providers/body_metrics_provider_session_ownership_test.mocks.dart';
import '../ui/screens/auth/login_screen_test.mocks.dart';
import '../ui/screens/settings/delete_account_screen_test.mocks.dart';

void main() {
  group('Accessibility guidelines', () {
    // Dark is the app's default theme (ProfileProvider.themeMode), light is
    // the alternative users can pick - both must meet the guidelines.
    final themes = {'light': AppTheme.lightTheme, 'dark': AppTheme.darkTheme};
    final authScreens = <String, Widget Function()>{
      'LoginScreen': () => const LoginScreen(),
      'SignupScreen': () => const SignupScreen(),
    };

    for (final theme in themes.entries) {
      for (final screen in authScreens.entries) {
        testWidgets(
          '${screen.key} (${theme.key} theme) meets tap-target, contrast, '
          'and label guidelines',
          (tester) async {
            final mockAuthProvider = MockAuthProvider();
            when(mockAuthProvider.isLoading).thenReturn(false);
            when(mockAuthProvider.errorMessage).thenReturn('');

            final handle = tester.ensureSemantics();
            await tester.pumpWidget(
              MaterialApp(
                theme: theme.value,
                home: ChangeNotifierProvider<AuthProvider>.value(
                  value: mockAuthProvider,
                  child: screen.value(),
                ),
              ),
            );
            await tester.pumpAndSettle();

            await expectLater(tester, meetsGuideline(textContrastGuideline));
            await expectLater(
              tester,
              meetsGuideline(androidTapTargetGuideline),
            );
            await expectLater(
              tester,
              meetsGuideline(labeledTapTargetGuideline),
            );
            handle.dispose();
          },
        );
      }
    }

    testWidgets('Onboarding WelcomePage meets contrast and label guidelines', (
      tester,
    ) async {
      // Default test surface (~800x600) is smaller than any real phone and
      // clips this page; use a realistic phone viewport instead.
      tester.view.physicalSize = const Size(1080, 2280);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          darkTheme: AppTheme.darkTheme,
          home: const Scaffold(body: WelcomePage()),
        ),
      );
      // WelcomePage staggers entrance animations with delayed timers; flush
      // them all so none are left pending when the test tears down.
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    for (final theme
        in {'light': AppTheme.lightTheme, 'dark': AppTheme.darkTheme}.entries) {
      testWidgets('DeleteAccountScreen (${theme.key} theme) meets tap-target, '
          'contrast, and label guidelines', (tester) async {
        final mockProvider = MockAccountDeletionProvider();
        when(mockProvider.isDeleting).thenReturn(false);
        when(mockProvider.errorMessage).thenReturn(null);

        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          MaterialApp(
            theme: theme.value,
            home: ChangeNotifierProvider<AccountDeletionProvider>.value(
              value: mockProvider,
              child: const DeleteAccountScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        handle.dispose();
      });
    }

    // Regression coverage for the Colors.grey contrast audit: error_state.dart
    // and status_badge.dart's "draft"/unknown-status badge used a bare
    // Colors.grey that measured below the 4.5:1 AA threshold against their
    // backgrounds - fixed to context.textSecondary / Colors.grey.shade700
    // respectively.
    for (final theme in themes.entries) {
      testWidgets('ErrorState (${theme.key} theme) meets contrast '
          'guidelines', (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          MaterialApp(
            theme: theme.value,
            home: const Scaffold(
              body: ErrorState(message: 'Something went wrong'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });

      testWidgets('StatusBadge draft/unknown status (${theme.key} theme) meets '
          'contrast guidelines', (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          MaterialApp(
            theme: theme.value,
            home: const Scaffold(
              body: Column(
                children: [
                  StatusBadge(status: 'draft'),
                  StatusBadge(status: 'unknown'),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });

      testWidgets('BodyMetricsScreen empty state (${theme.key} theme) meets '
          'contrast guidelines', (tester) async {
        final repo = MockBodyMetricsRepository();
        when(
          repo.getBodyMetrics(days: anyNamed('days')),
        ).thenAnswer((_) async => []);
        when(repo.getLatestMetric()).thenAnswer((_) async => null);
        final epoch = UserSessionEpoch()..activate(1);
        final provider = BodyMetricsProvider(repo, epoch);

        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          MaterialApp(
            theme: theme.value,
            home: ChangeNotifierProvider<BodyMetricsProvider>.value(
              value: provider,
              child: const BodyMetricsScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });

      testWidgets(
        'ProgressLineChart and VolumeChart captions (${theme.key} theme) '
        'meet contrast guidelines',
        (tester) async {
          final points = [
            ProgressDataPoint(date: DateTime(2026, 1, 1), value: 10),
            ProgressDataPoint(date: DateTime(2026, 1, 2), value: 20),
          ];

          final handle = tester.ensureSemantics();
          await tester.pumpWidget(
            MaterialApp(
              theme: theme.value,
              home: Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      ProgressLineChart(data: points),
                      VolumeChart(data: points),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          await expectLater(tester, meetsGuideline(textContrastGuideline));
          handle.dispose();
        },
      );
    }
  });
}
