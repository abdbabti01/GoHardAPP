import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/colors.dart';
import '../../../core/services/haptic_service.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../providers/active_workout_provider.dart';
import '../../../providers/music_player_provider.dart';
import '../../../routes/route_names.dart';
import '../../widgets/common/animations.dart';
import '../../widgets/common/celebration.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../widgets/common/offline_banner.dart';
import '../../widgets/common/premium_bottom_sheet.dart';
import '../../widgets/music/music_control_widget.dart';

/// Active workout screen with timer and exercise management
/// Matches ActiveWorkoutPage.xaml from MAUI app
class ActiveWorkoutScreen extends StatefulWidget {
  final int sessionId;

  const ActiveWorkoutScreen({super.key, required this.sessionId});

  @override
  State<ActiveWorkoutScreen> createState() => _ActiveWorkoutScreenState();
}

class _ActiveWorkoutScreenState extends State<ActiveWorkoutScreen> {
  // Debug toggle for timer investigation
  bool _showDebugInfo = false;

  @override
  void initState() {
    super.initState();
    // Load session (timer will auto-start if in_progress)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<ActiveWorkoutProvider>();
      provider.loadSession(widget.sessionId);

      // Initialize music player for workout
      final musicProvider = context.read<MusicPlayerProvider>();
      if (!musicProvider.isInitialized) {
        musicProvider.initialize();
      }
    });
  }

  Future<void> _handleAddExercise() async {
    final result = await Navigator.of(
      context,
    ).pushNamed(RouteNames.addExercise, arguments: widget.sessionId);

    // Reload session if exercise was added
    if (result == true && mounted) {
      context.read<ActiveWorkoutProvider>().loadSession(widget.sessionId);
    }
  }

  Future<void> _handleFinishWorkout() async {
    final confirmed = await ConfirmationBottomSheet.show(
      context: context,
      title: 'Finish Workout',
      message: 'Great job! Ready to wrap up this workout session?',
      confirmLabel: 'Finish',
      cancelLabel: 'Keep Going',
      icon: Icons.check_circle_outline_rounded,
    );

    if (confirmed == true && mounted) {
      final provider = context.read<ActiveWorkoutProvider>();
      final session = provider.currentSession;
      final exerciseCount = provider.exercises.length;
      final setCount = provider.exercises.fold<int>(
        0,
        (sum, e) => sum + e.exerciseSets.length,
      );
      final duration = provider.elapsedTime.inMinutes;

      final success = await provider.finishWorkout();

      if (success && mounted) {
        // Trigger celebration haptic feedback
        HapticService.workoutComplete();

        // Show celebration
        await Navigator.of(context).push(
          PageRouteBuilder(
            opaque: false,
            pageBuilder:
                (context, _, __) => WorkoutCompleteCelebration(
                  workoutName: session?.name,
                  duration: duration,
                  exerciseCount: exerciseCount,
                  setCount: setCount,
                  onContinue: () {
                    Navigator.of(context).popUntil((route) {
                      return route.settings.name == RouteNames.sessions ||
                          route.settings.name == RouteNames.main ||
                          route.isFirst;
                    });
                  },
                ),
          ),
        );
      }
    }
  }

  Future<bool> _handleBackPressed() async {
    // Capture provider before async gap to avoid lint warning
    final provider = context.read<ActiveWorkoutProvider>();
    final result = await PremiumBottomSheet.show<String>(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.goHardOrange.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              size: 32,
              color: AppColors.goHardOrange,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Leave Workout?',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Your workout is still in progress. If you leave, the timer will be paused and you can resume later.',
            style: TextStyle(
              fontSize: 15,
              color: context.textSecondary,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          // Finish workout button
          _buildActionButton(
            context,
            label: 'Finish Workout',
            icon: Icons.check_circle_rounded,
            isPrimary: true,
            onTap: () => Navigator.pop(context, 'finish'),
          ),
          const SizedBox(height: 12),
          // Stay button
          _buildActionButton(
            context,
            label: 'Keep Going',
            icon: Icons.play_arrow_rounded,
            isPrimary: false,
            onTap: () => Navigator.pop(context, 'stay'),
          ),
          const SizedBox(height: 12),
          // Leave anyway
          TextButton(
            onPressed: () => Navigator.pop(context, 'leave'),
            child: Text(
              'Leave Anyway',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.errorRed,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (result == 'finish') {
      _handleFinishWorkout();
      return false;
    } else if (result == 'leave') {
      // Auto-pause timer before leaving to preserve elapsed time
      if (provider.isTimerRunning) {
        await provider.pauseTimer();
      }
      return true;
    }
    return false;
  }

  Widget _buildActionButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool isPrimary,
    required VoidCallback onTap,
  }) {
    if (isPrimary) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: context.primaryGradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: context.accent.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 20, color: AppColors.goHardBlack),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.goHardBlack,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: context.textPrimary),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleEditWorkoutName() async {
    final provider = context.read<ActiveWorkoutProvider>();
    final currentName = provider.currentSession?.name;
    final controller = TextEditingController(text: currentName);

    final newName = await PremiumBottomSheet.show<String>(
      context: context,
      title: 'Edit Workout Name',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: context.surfaceElevated,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.border),
            ),
            child: TextField(
              autofocus: true,
              controller: controller,
              textCapitalization: TextCapitalization.words,
              style: TextStyle(
                fontSize: 16,
                color: context.textPrimary,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: 'e.g., Push Day, Leg Day',
                hintStyle: TextStyle(color: context.textTertiary),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                border: InputBorder.none,
                prefixIcon: Icon(
                  Icons.edit_rounded,
                  color: context.accent,
                  size: 22,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: context.surfaceElevated,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: context.border),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        controller.dispose();
                        Navigator.pop(context);
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: context.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: context.primaryGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        final text = controller.text;
                        controller.dispose();
                        Navigator.pop(context, text);
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: Text(
                            'Save',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.goHardBlack,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (newName != null && newName.trim().isNotEmpty && mounted) {
      await provider.updateWorkoutName(newName.trim());
    }
  }

  void _handleExerciseTap(int exerciseId) {
    Navigator.of(context).pushNamed(RouteNames.logSets, arguments: exerciseId);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;

        final navigator = Navigator.of(context);
        final shouldLeave = await _handleBackPressed();
        if (shouldLeave && mounted) {
          navigator.pop();
        }
      },
      child: Consumer<ActiveWorkoutProvider>(
        builder: (context, provider, child) {
          return Scaffold(
            backgroundColor: context.scaffoldBackground,
            appBar: _buildPremiumAppBar(context, provider),
            body: Column(
              children: [
                const OfflineBanner(),
                Expanded(child: _buildBody(provider)),
              ],
            ),
            floatingActionButton: ScaleTapAnimation(
              onTap: _handleAddExercise,
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: context.primaryGradient,
                  boxShadow: [
                    BoxShadow(
                      color: context.accent.withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.add_rounded,
                        color: AppColors.goHardBlack,
                        size: 24,
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Add Exercise',
                        style: TextStyle(
                          color: AppColors.goHardBlack,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildPremiumAppBar(
    BuildContext context,
    ActiveWorkoutProvider provider,
  ) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: context.surfaceElevated,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 18,
            color: context.textPrimary,
          ),
        ),
        onPressed: () async {
          final navigator = Navigator.of(context);
          final shouldLeave = await _handleBackPressed();
          if (shouldLeave && mounted) {
            navigator.pop();
          }
        },
      ),
      title: GestureDetector(
        onTap: _handleEditWorkoutName,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                provider.currentSession?.name ?? 'Active Workout',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: context.textPrimary,
                  letterSpacing: -0.5,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.edit_rounded, size: 16, color: context.textTertiary),
          ],
        ),
      ),
      centerTitle: true,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ScaleTapAnimation(
            onTap: _handleFinishWorkout,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                gradient: context.primaryGradient,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: context.accent.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: AppColors.goHardBlack,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Finish',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.goHardBlack,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(ActiveWorkoutProvider provider) {
    if (provider.isLoading) {
      return const Center(child: PremiumLoader());
    }

    if (provider.errorMessage != null && provider.errorMessage!.isNotEmpty) {
      return EmptyState(
        icon: Icons.error_outline_rounded,
        title: 'Something went wrong',
        message: provider.errorMessage!,
        iconColor: AppColors.errorRed,
      );
    }

    return Column(
      children: [
        // Music player controls
        const MusicControlWidget(),

        // Timer card
        FadeSlideAnimation(child: _buildTimerCard(provider)),

        // Exercises list
        Expanded(
          child:
              provider.exercises.isEmpty
                  ? _buildEmptyState()
                  : _buildExercisesList(provider),
        ),
      ],
    );
  }

  Widget _buildTimerCard(ActiveWorkoutProvider provider) {
    final isDraft = provider.currentSession?.status == 'draft';
    final isRunning = provider.isTimerRunning;

    // PREMIUM: Cleaner timer card without noisy patterns
    // Focus on the number, minimal status indicators
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient:
            isRunning
                ? const LinearGradient(
                  colors: [Color(0xFFFF6B35), Color(0xFFFF8C42)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
                : LinearGradient(
                  colors: [AppColors.charcoal, AppColors.slate],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
        boxShadow: [
          BoxShadow(
            color: (isRunning ? AppColors.accentCoral : AppColors.charcoal)
                .withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 32),
        child: Column(
          children: [
            // CLEAN: Just the timer, massive and centered
            Text(
              _formatElapsedTime(provider.elapsedTime),
              style: const TextStyle(
                fontFamily: 'SpaceGrotesk',
                fontSize: 64,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -3,
                height: 1.0,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 8),
            // Status indicated by subtle text, not labels
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Row(
                key: ValueKey(isRunning),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color:
                          isRunning
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                      boxShadow:
                          isRunning
                              ? [
                                BoxShadow(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  blurRadius: 6,
                                ),
                              ]
                              : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isRunning ? 'Active' : 'Paused',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.9),
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            // Control button
            _buildControlButton(provider, isDraft, isRunning),
            // DEBUG: Timer debug info (tap to toggle)
            const SizedBox(height: 16),
            _buildDebugToggle(provider),
          ],
        ),
      ),
    );
  }

  Widget _buildDebugToggle(ActiveWorkoutProvider provider) {
    return Column(
      children: [
        GestureDetector(
          onTap: () {
            setState(() {
              _showDebugInfo = !_showDebugInfo;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _showDebugInfo ? Icons.bug_report : Icons.bug_report_outlined,
                  size: 14,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
                const SizedBox(width: 6),
                Text(
                  _showDebugInfo ? 'Hide Debug' : 'Show Debug',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_showDebugInfo) ...[
          const SizedBox(height: 12),
          _buildDebugInfo(provider),
        ],
      ],
    );
  }

  Widget _buildDebugInfo(ActiveWorkoutProvider provider) {
    final session = provider.currentSession;
    final now = DateTime.now();
    final nowUtc = now.toUtc();
    final offset = now.timeZoneOffset;

    // Calculate what the elapsed time should be
    Duration? calculatedElapsed;
    if (session?.startedAt != null) {
      if (session?.pausedAt != null) {
        calculatedElapsed = session!.pausedAt!.difference(session.startedAt!);
      } else {
        calculatedElapsed = nowUtc.difference(session!.startedAt!);
      }
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _debugRow('Session ID', '${session?.id ?? "null"}'),
          _debugRow('Status', session?.status ?? 'null'),
          const Divider(color: Colors.white24, height: 16),
          _debugRow(
            'startedAt',
            session?.startedAt?.toIso8601String() ?? 'null',
          ),
          _debugRow(
            'startedAt.isUtc',
            '${session?.startedAt?.isUtc ?? "n/a"}',
            highlight: session?.startedAt != null && !session!.startedAt!.isUtc,
          ),
          _debugRow('startedAt.hour', '${session?.startedAt?.hour ?? "n/a"}'),
          const Divider(color: Colors.white24, height: 16),
          _debugRow('pausedAt', session?.pausedAt?.toIso8601String() ?? 'null'),
          _debugRow(
            'pausedAt.isUtc',
            '${session?.pausedAt?.isUtc ?? "n/a"}',
            highlight: session?.pausedAt != null && !session!.pausedAt!.isUtc,
          ),
          const Divider(color: Colors.white24, height: 16),
          _debugRow('Now (local)', now.toIso8601String()),
          _debugRow('Now (UTC)', nowUtc.toIso8601String()),
          _debugRow(
            'Timezone Offset',
            '${offset.inHours}h ${offset.inMinutes.remainder(60)}m',
          ),
          const Divider(color: Colors.white24, height: 16),
          _debugRow(
            'Calculated Elapsed',
            calculatedElapsed != null
                ? '${calculatedElapsed.inHours}h ${calculatedElapsed.inMinutes.remainder(60)}m ${calculatedElapsed.inSeconds.remainder(60)}s'
                : 'n/a',
          ),
          _debugRow(
            'Provider Elapsed',
            '${provider.elapsedTime.inHours}h ${provider.elapsedTime.inMinutes.remainder(60)}m ${provider.elapsedTime.inSeconds.remainder(60)}s',
          ),
          if (calculatedElapsed != null && calculatedElapsed.inHours >= 5)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '⚠️ BUG DETECTED: Elapsed > 5 hours!\nThis may indicate a UTC conversion issue.',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _debugRow(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Colors.white.withValues(alpha: 0.6),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 10,
                color: highlight ? Colors.red : Colors.white,
                fontWeight: highlight ? FontWeight.bold : FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton(
    ActiveWorkoutProvider provider,
    bool isDraft,
    bool isRunning,
  ) {
    final buttonLabel =
        isDraft
            ? 'Start Workout'
            : isRunning
            ? 'Pause'
            : 'Resume';
    final buttonIcon =
        isDraft
            ? Icons.play_arrow_rounded
            : isRunning
            ? Icons.pause_rounded
            : Icons.play_arrow_rounded;
    final onPressed =
        isDraft
            ? provider.startWorkout
            : isRunning
            ? provider.pauseTimer
            : provider.resumeTimer;

    // PREMIUM: Cleaner control button
    return ScaleTapAnimation(
      onTap: () {
        HapticService.buttonTap();
        onPressed();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(buttonIcon, size: 22, color: AppColors.charcoal),
            const SizedBox(width: 10),
            Text(
              buttonLabel,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.charcoal,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return FadeSlideAnimation(
      child: EmptyStateIllustrated(
        fallbackIcon: Icons.fitness_center_rounded,
        title: 'No Exercises Yet',
        message: 'Add exercises to your workout using the button below',
        action: EmptyStateAction(
          label: 'Add Exercise',
          icon: Icons.add_rounded,
          onPressed: _handleAddExercise,
        ),
      ),
    );
  }

  Widget _buildExercisesList(ActiveWorkoutProvider provider) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100, left: 16, right: 16, top: 8),
      itemCount: provider.exercises.length,
      itemBuilder: (context, index) {
        final exercise = provider.exercises[index];
        final setsCount = exercise.exerciseSets.length;
        final hasLoggedSets = setsCount > 0;

        return FadeSlideAnimation(
          delay: Duration(milliseconds: index * 50),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: context.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color:
                    hasLoggedSets
                        ? context.accent.withValues(alpha: 0.3)
                        : context.border,
                width: hasLoggedSets ? 1.5 : 0.5,
              ),
              boxShadow:
                  hasLoggedSets
                      ? [
                        BoxShadow(
                          color: context.accent.withValues(alpha: 0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                      : null,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _handleExerciseTap(exercise.id),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      // Color indicator
                      Container(
                        width: 4,
                        height: 48,
                        decoration: BoxDecoration(
                          color:
                              hasLoggedSets
                                  ? context.accent
                                  : AppColors.goHardBlue,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 14),
                      // Icon container
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.goHardBlue.withValues(alpha: 0.2),
                              AppColors.goHardBlue.withValues(alpha: 0.1),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.fitness_center_rounded,
                          size: 24,
                          color: AppColors.goHardBlue,
                        ),
                      ),
                      const SizedBox(width: 14),
                      // Exercise details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              exercise.name,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: context.textPrimary,
                                letterSpacing: -0.3,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                if (hasLoggedSets) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: context.accent.withValues(
                                        alpha: 0.15,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.check_circle_rounded,
                                          size: 12,
                                          color: context.accent,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '$setsCount set${setsCount == 1 ? '' : 's'}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: context.accent,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ] else ...[
                                  Text(
                                    'Tap to log sets',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: context.textTertiary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: context.textTertiary,
                        size: 22,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatElapsedTime(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
}
