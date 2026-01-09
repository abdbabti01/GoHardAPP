import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/models/program.dart';
import '../../../providers/programs_provider.dart';
import '../../../routes/route_names.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Training Programs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              // TODO: Navigate to create program screen
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Create program - Coming soon!')),
              );
            },
          ),
        ],
      ),
      body: Consumer<ProgramsProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.errorMessage != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    provider.errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
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
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No Programs Yet',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create a goal and generate\na workout plan to get started!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => provider.loadPrograms(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Active Programs
                if (provider.activePrograms.isNotEmpty) ...[
                  Text(
                    'Active Programs',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),
                  ...provider.activePrograms
                      .map((program) => _buildProgramCard(context, program)),
                  const SizedBox(height: 24),
                ],

                // Completed Programs
                if (provider.completedPrograms.isNotEmpty) ...[
                  Text(
                    'Completed Programs',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade600,
                        ),
                  ),
                  const SizedBox(height: 12),
                  ...provider.completedPrograms
                      .map((program) => _buildProgramCard(context, program)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildProgramCard(BuildContext context, Program program) {
    final theme = Theme.of(context);
    final isCompleted = program.isCompleted;
    final cardColor = isCompleted ? Colors.grey.shade50 : Colors.white;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isCompleted
            ? BorderSide(color: Colors.green.shade200, width: 2)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Title and Icon
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isCompleted ? Icons.check_circle : Icons.fitness_center,
                    color: isCompleted ? Colors.green : theme.primaryColor,
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
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (program.description != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          program.description!,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
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
                    fontWeight: FontWeight.w600,
                    color: theme.primaryColor,
                    fontSize: 15,
                  ),
                ),
                Text(
                  '${program.progressPercentage.toStringAsFixed(0)}% Complete',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
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
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isCompleted ? Colors.green : theme.primaryColor,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Current Phase Badge
            if (!isCompleted)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                    Icon(Icons.trending_up,
                        size: 16, color: theme.primaryColor),
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

            // Today's Workout Section
            if (!isCompleted && program.todaysWorkout != null) ...[
              const Divider(height: 1),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.today, size: 20, color: Colors.grey.shade600),
                  const SizedBox(width: 8),
                  Text(
                    'TODAY\'S WORKOUT',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade600,
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
                            program.todaysWorkout!.workoutName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              if (program.todaysWorkout!.estimatedDuration !=
                                  null) ...[
                                Icon(Icons.access_time,
                                    size: 14, color: Colors.grey.shade600),
                                const SizedBox(width: 4),
                                Text(
                                  '${program.todaysWorkout!.estimatedDuration} min',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(width: 12),
                              ],
                              Icon(Icons.fitness_center,
                                  size: 14, color: Colors.grey.shade600),
                              const SizedBox(width: 4),
                              Text(
                                '${program.todaysWorkout!.exerciseCount} exercises',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
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
              const Divider(height: 1),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.celebration, size: 20, color: Colors.green.shade700),
                  const SizedBox(width: 8),
                  Text(
                    'Program Completed!',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade700,
                    ),
                  ),
                  const Spacer(),
                  if (program.completedAt != null)
                    Text(
                      '${program.completedAt!.month}/${program.completedAt!.day}/${program.completedAt!.year}',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                ],
              ),
            ],

            // Action Buttons
            if (!isCompleted) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        // TODO: Navigate to workout screen
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Start workout - Coming soon!')),
                        );
                      },
                      icon: const Icon(Icons.play_arrow, size: 20),
                      label: const Text('Start Workout'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
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
                      child: const Text('View'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
