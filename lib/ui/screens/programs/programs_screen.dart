import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../data/models/program.dart';
import '../../../providers/programs_provider.dart';
import '../../../routes/route_names.dart';
import '../../widgets/programs/weekly_schedule_widget.dart';

class ProgramsScreen extends StatefulWidget {
  const ProgramsScreen({super.key});

  @override
  State<ProgramsScreen> createState() => _ProgramsScreenState();
}

class _ProgramsScreenState extends State<ProgramsScreen> {
  @override
  void initState() {
    super.initState();
    // Load programs when screen initializes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProgramsProvider>().loadPrograms();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ProgramsProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (provider.errorMessage != null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: context.error),
                const SizedBox(height: 16),
                Text(
                  provider.errorMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.error),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => provider.loadPrograms(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        if (provider.programs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.fitness_center,
                  size: 80,
                  color: context.textTertiary,
                ),
                const SizedBox(height: 16),
                Text(
                  'No Programs Yet',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: context.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Create a goal and generate\na workout plan to get started!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.textSecondary, fontSize: 16),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () => provider.loadPrograms(),
          child: ListView(
            padding: const EdgeInsets.symmetric(
              vertical: 20,
            ), // iOS inset group style
            children: [
              // Active Programs
              if (provider.activePrograms.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'ACTIVE PROGRAMS',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: context.textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ...provider.activePrograms.map(
                  (program) => _buildProgramCard(context, program),
                ),
                const SizedBox(height: 24),
              ],

              // Completed Programs
              if (provider.completedPrograms.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'COMPLETED PROGRAMS',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: context.textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ...provider.completedPrograms.map(
                  (program) => _buildProgramCard(context, program),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildProgramCard(BuildContext context, Program program) {
    final theme = Theme.of(context);
    final isCompleted = program.isCompleted;

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 8,
      ), // iOS inset style
      elevation: 0, // No elevation for iOS style
      shadowColor: Colors.transparent,
      color: context.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12), // iOS corner radius
        side: BorderSide(
          color: isCompleted ? theme.colorScheme.primary : context.border,
          width: isCompleted ? 1.5 : 0.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20), // Keep generous iOS padding

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Title and Icon
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isCompleted ? Icons.check_circle : Icons.fitness_center,
                    color: theme.colorScheme.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        program.title,
                        style: TextStyle(
                          fontSize: 20, // iOS title size
                          fontWeight: FontWeight.w600, // iOS semibold
                          color: context.textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (program.description != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          program.description!,
                          style: TextStyle(
                            color: context.textSecondary,
                            fontSize: 15, // iOS body size
                            fontWeight: FontWeight.w400, // iOS regular
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Progress Info
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Week ${program.currentWeek} of ${program.totalWeeks}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600, // iOS semibold
                    color: theme.primaryColor,
                    fontSize: 15,
                  ),
                ),
                Text(
                  '${program.progressPercentage.toStringAsFixed(0)}% Complete',
                  style: TextStyle(
                    fontWeight: FontWeight.w400, // iOS regular
                    color: context.textSecondary,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Progress Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: program.progressPercentage / 100,
                minHeight: 8,
                backgroundColor: context.surfaceElevated,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isCompleted ? context.success : theme.primaryColor,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Current Phase Badge
            if (!isCompleted)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: theme.primaryColor.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.trending_up,
                      size: 16,
                      color: theme.primaryColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Phase ${program.currentPhase}: ${program.phaseName}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: theme.primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),

            // Weekly Schedule
            if (!isCompleted) ...[
              const Divider(height: 32),
              WeeklyScheduleWidget(
                key: ValueKey('program_${program.id}'),
                program: program,
                onWorkoutTap: (workout) {
                  if (!workout.isRestDay) {
                    Navigator.pushNamed(
                      context,
                      RouteNames.programWorkout,
                      arguments: {
                        'workoutId': workout.id,
                        'programId': program.id,
                      },
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text(
                          'Rest day - Recovery is part of the program!',
                        ),
                        backgroundColor: context.accent,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
                // Widget now watches provider directly, no need for full reload
                onWorkoutMoved: null,
              ),
              const SizedBox(height: 16),
            ],

            // Today's Workout Section
            if (!isCompleted && program.currentWorkout != null) ...[
              Divider(height: 1, color: context.border),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.today, size: 20, color: context.textSecondary),
                  const SizedBox(width: 8),
                  Text(
                    'TODAY\'S WORKOUT',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: context.textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.primaryColor.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            program.currentWorkout!.workoutName,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: context.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              if (program.currentWorkout!.estimatedDuration !=
                                  null) ...[
                                Icon(
                                  Icons.access_time,
                                  size: 14,
                                  color: context.textSecondary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${program.currentWorkout!.estimatedDuration} min',
                                  style: TextStyle(
                                    color: context.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(width: 12),
                              ],
                              Icon(
                                Icons.fitness_center,
                                size: 14,
                                color: context.textSecondary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${program.currentWorkout!.exerciseCount} exercises',
                                style: TextStyle(
                                  color: context.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Completed Badge
            if (isCompleted) ...[
              Divider(height: 1, color: context.border),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.celebration, size: 20, color: context.success),
                  const SizedBox(width: 8),
                  Text(
                    'Program Completed!',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: context.success,
                    ),
                  ),
                  const Spacer(),
                  if (program.completedAt != null)
                    Text(
                      '${program.completedAt!.month}/${program.completedAt!.day}/${program.completedAt!.year}',
                      style: TextStyle(
                        color: context.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                ],
              ),
            ],

            // Action Buttons
            if (!isCompleted) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pushNamed(
                      context,
                      RouteNames.programDetail,
                      arguments: program.id,
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('View Program Detail'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
