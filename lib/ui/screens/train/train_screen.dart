import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/sync_service.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/theme/typography.dart';
import '../../../data/models/session.dart';
import '../../../providers/programs_provider.dart';
import '../../../providers/sessions_provider.dart';
import '../../../routes/route_names.dart';
import '../../widgets/common/active_workout_banner.dart';
import '../../widgets/common/offline_banner.dart';
import '../../widgets/common/sync_issues_banner.dart';
import '../../widgets/sessions/weekly_progress_card.dart';
import '../../widgets/sessions/workout_name_dialog.dart';
import '../sessions/session_detail_screen.dart';
import 'plan_summary.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Train answers "what am I training and how am I progressing?".
/// Today owns "what should I do now?", so Train has no Start button.
class TrainScreen extends StatefulWidget {
  const TrainScreen({super.key});

  /// Where a legacy `subTab` index (the removed Workouts / Programs /
  /// Exercises tabs) now lives, or null when there is nothing to open.
  static String? routeForLegacySubTab(int? subTab) => switch (subTab) {
    0 => RouteNames.workoutHistory,
    1 => RouteNames.programs,
    2 => RouteNames.exercises,
    _ => null,
  };

  @override
  State<TrainScreen> createState() => _TrainScreenState();
}

class _TrainScreenState extends State<TrainScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SessionsProvider>().loadSessions();
      context.read<ProgramsProvider>().loadPrograms();
    });
  }

  Future<void> _handleRefresh() async {
    try {
      await context.read<SyncService>().sync();
    } catch (e) {
      debugPrint('Sync failed during refresh: $e');
    }
    if (!mounted) return;
    await Future.wait([
      context.read<SessionsProvider>().loadSessions(showLoading: false),
      context.read<ProgramsProvider>().loadPrograms(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const ActiveWorkoutBanner(),
        const OfflineBanner(),
        const SyncIssuesBanner(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _handleRefresh,
            color: context.accent,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 100),
              children: const [
                _PlanSections(),
                _ProgressSection(),
                _RecentSection(),
                _ToolsSection(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _SectionHeader(this.title, {this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: AppTypography.titleLarge.copyWith(
                  color: context.textPrimary,
                ),
              ),
            ),
          ),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  final String text;

  const _Note(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Text(
        text,
        style: AppTypography.bodyMedium.copyWith(color: context.textSecondary),
      ),
    );
  }
}

class _RetryRow extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _RetryRow(this.message, this.onRetry);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: context.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodyMedium.copyWith(
                color: context.textPrimary,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

/// My Plan + This Week: both read the same first active plan.
class _PlanSections extends StatelessWidget {
  const _PlanSections();

  @override
  Widget build(BuildContext context) {
    final programs = context.watch<ProgramsProvider>();
    final isOnline = context.select<ConnectivityService, bool>(
      (c) => c.isOnline,
    );
    void openPlan() => Navigator.pushNamed(context, RouteNames.programs);

    if (programs.activePrograms.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeader(
            'My Plan',
            actionLabel: programs.programs.isEmpty ? null : 'View plan',
            onAction: openPlan,
          ),
          _noPlanBody(context, programs, isOnline),
        ],
      );
    }

    final plan = programs.activePrograms.first;
    final summary = PlanSummary.of(
      plan,
      DateTime.now(),
      programs.scheduledDateOf,
    );
    final goal = plan.goal?.goalType;
    final progressLine = [
      'Week ${plan.currentWeek} of ${plan.totalWeeks}',
      if (summary.due > 0) '${summary.done} of ${summary.due} workouts done',
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader('My Plan', actionLabel: 'View plan', onAction: openPlan),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            plan.title,
            style: AppTypography.titleMedium.copyWith(
              color: context.textPrimary,
            ),
          ),
        ),
        if (goal != null) _Note('Goal: $goal'),
        _Note(progressLine),
        const _SectionHeader('This Week'),
        if (summary.thisWeek.isEmpty)
          const _Note('Nothing scheduled this week.')
        else
          for (final item in summary.thisWeek)
            ListTile(
              leading: SizedBox(
                width: 40,
                child: Text(
                  _weekdays[item.date.weekday - 1],
                  style: AppTypography.labelLarge.copyWith(
                    color: context.textSecondary,
                  ),
                ),
              ),
              title: Text(
                item.workout.workoutName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(
                _stateLabel(item.state),
                style: AppTypography.labelLarge.copyWith(
                  color:
                      item.state == PlanDayState.today
                          ? context.accent
                          : context.textSecondary,
                ),
              ),
              onTap:
                  () => Navigator.pushNamed(
                    context,
                    RouteNames.programWorkout,
                    arguments: {
                      'workoutId': item.workout.id,
                      'programId': plan.id,
                    },
                  ),
            ),
      ],
    );
  }

  Widget _noPlanBody(
    BuildContext context,
    ProgramsProvider programs,
    bool isOnline,
  ) {
    if (programs.isLoading && programs.programs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: LinearProgressIndicator(),
      );
    }
    if (programs.errorMessage != null && programs.programs.isEmpty) {
      return _RetryRow(
        "Couldn't load your plan.",
        () => programs.loadPrograms(),
      );
    }
    // Plans are online-only today (ProgramsRepository returns [] offline),
    // so an empty list offline means "unknown", never "no plan".
    if (!isOnline && programs.programs.isEmpty) {
      return const _Note("Your plan shows here when you're online.");
    }
    if (programs.programs.isNotEmpty) {
      return const _Note('No active plan.');
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No plan yet.',
            style: AppTypography.bodyMedium.copyWith(
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed:
                () => Navigator.pushNamed(context, RouteNames.workoutPlanForm),
            icon: const Icon(Icons.add),
            label: const Text('Create a plan'),
          ),
        ],
      ),
    );
  }

  static String _stateLabel(PlanDayState state) => switch (state) {
    PlanDayState.done => 'Done',
    PlanDayState.skipped => 'Skipped',
    PlanDayState.missed => 'Missed',
    PlanDayState.today => 'Today',
    PlanDayState.upcoming => '',
  };
}

class _ProgressSection extends StatelessWidget {
  const _ProgressSection();

  @override
  Widget build(BuildContext context) {
    final sessions = context.watch<SessionsProvider>().sessions;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final thisWeek = _between(
      sessions,
      weekStart,
      weekStart.add(const Duration(days: 7)),
    );
    final thisMonth = _between(
      sessions,
      DateTime(today.year, today.month),
      DateTime(today.year, today.month + 1),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          'Progress',
          actionLabel: 'View progress',
          onAction: () => Navigator.pushNamed(context, RouteNames.analytics),
        ),
        if (thisWeek.isEmpty && thisMonth.isEmpty)
          const _Note('Finish a workout to see your progress here.')
        else
          WeeklyProgressCard(
            thisWeekSessions: thisWeek,
            thisMonthSessions: thisMonth,
          ),
      ],
    );
  }

  static List<Session> _between(
    List<Session> sessions,
    DateTime start,
    DateTime end,
  ) =>
      sessions.where((s) {
        final day = DateTime(s.date.year, s.date.month, s.date.day);
        return !day.isBefore(start) && day.isBefore(end);
      }).toList();
}

class _RecentSection extends StatelessWidget {
  const _RecentSection();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SessionsProvider>();
    final recent =
        provider.sessions.where((s) => s.status == 'completed').toList()
          ..sort((a, b) => b.date.compareTo(a.date));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          'Recent',
          actionLabel: 'History',
          onAction:
              () => Navigator.pushNamed(context, RouteNames.workoutHistory),
        ),
        if (provider.isLoading && provider.sessions.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(),
          )
        else if (provider.errorMessage != null && provider.sessions.isEmpty)
          _RetryRow(
            "Couldn't load your workouts.",
            () => provider.loadSessions(),
          )
        else if (recent.isEmpty)
          const _Note('No finished workouts yet.')
        else
          for (final s in recent.take(3))
            ListTile(
              title: Text(
                s.name ?? 'Workout',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(_subtitle(s)),
              trailing: const Icon(Icons.chevron_right),
              onTap:
                  () => Navigator.pushNamed(
                    context,
                    RouteNames.sessionDetail,
                    arguments: SessionDetailArgs(
                      sessionId: s.id,
                      localId: provider.localIdFor(s),
                    ),
                  ),
            ),
      ],
    );
  }

  static String _subtitle(Session s) {
    final day =
        '${_weekdays[s.date.weekday - 1]} ${s.date.day} ${_months[s.date.month - 1]}';
    return s.duration == null ? day : '$day · ${s.duration} min';
  }
}

class _ToolsSection extends StatelessWidget {
  const _ToolsSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader('Tools'),
        ListTile(
          leading: const Icon(Icons.menu_book_outlined),
          title: const Text('Exercise library'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.pushNamed(context, RouteNames.exercises),
        ),
        ListTile(
          leading: const Icon(Icons.add),
          title: const Text('Custom workout'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => startCustomWorkout(context),
        ),
      ],
    );
  }
}
