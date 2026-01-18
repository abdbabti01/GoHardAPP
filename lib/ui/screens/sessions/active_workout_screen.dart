import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/colors.dart';
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
            'Your workout is still in progress. If you leave now, the timer will be lost.',
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
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.goHardGreen.withValues(alpha: 0.3),
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
                    gradient: AppColors.primaryGradient,
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
                  gradient: AppColors.primaryGradient,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.goHardGreen.withValues(alpha: 0.4),
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
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.goHardGreen.withValues(alpha: 0.3),
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

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient:
            isRunning ? AppColors.activeGradient : AppColors.secondaryGradient,
        boxShadow: [
          BoxShadow(
            color: (isRunning ? AppColors.goHardOrange : AppColors.goHardBlue)
                .withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Background pattern
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: CustomPaint(painter: _TimerPatternPainter()),
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
            child: Column(
              children: [
                // Timer icon with pulse
                _buildTimerIcon(isRunning),
                const SizedBox(height: 16),
                // Timer display
                Text(
                  _formatElapsedTime(provider.elapsedTime),
                  style: const TextStyle(
                    fontSize: 56,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -2,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isRunning ? 'WORKOUT IN PROGRESS' : 'PAUSED',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.8),
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                // Control button
                _buildControlButton(provider, isDraft, isRunning),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimerIcon(bool isRunning) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      child:
          isRunning
              ? PulseAnimation(
                child: Icon(Icons.timer_rounded, size: 32, color: Colors.white),
              )
              : const Icon(
                Icons.timer_off_rounded,
                size: 32,
                color: Colors.white,
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

    return ScaleTapAnimation(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              buttonIcon,
              size: 24,
              color: isRunning ? AppColors.goHardOrange : AppColors.goHardBlue,
            ),
            const SizedBox(width: 10),
            Text(
              buttonLabel,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color:
                    isRunning ? AppColors.goHardOrange : AppColors.goHardBlue,
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
                        ? AppColors.goHardGreen.withValues(alpha: 0.3)
                        : context.border,
                width: hasLoggedSets ? 1.5 : 0.5,
              ),
              boxShadow:
                  hasLoggedSets
                      ? [
                        BoxShadow(
                          color: AppColors.goHardGreen.withValues(alpha: 0.1),
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
                                  ? AppColors.goHardGreen
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
                                      color: AppColors.goHardGreen.withValues(
                                        alpha: 0.15,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.check_circle_rounded,
                                          size: 12,
                                          color: AppColors.goHardGreen,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '$setsCount set${setsCount == 1 ? '' : 's'}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.goHardGreen,
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

/// Custom painter for timer card background pattern
class _TimerPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = Colors.white.withValues(alpha: 0.05)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;

    // Draw concentric circles
    final center = Offset(size.width * 0.8, size.height * 0.2);
    for (int i = 1; i <= 4; i++) {
      canvas.drawCircle(center, i * 40.0, paint);
    }

    // Draw diagonal lines
    for (int i = 0; i < 5; i++) {
      final startX = -50.0 + i * 80;
      canvas.drawLine(
        Offset(startX, size.height + 50),
        Offset(startX + 150, -50),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
