import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../data/models/run_session.dart';
import '../../../providers/shared_workout_provider.dart';

/// Dialog to share a run session with friends
class ShareRunDialog extends StatefulWidget {
  final RunSession run;

  const ShareRunDialog({super.key, required this.run});

  @override
  State<ShareRunDialog> createState() => _ShareRunDialogState();
}

class _ShareRunDialogState extends State<ShareRunDialog> {
  final _descriptionController = TextEditingController();
  bool _isSharing = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final run = widget.run;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: context.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.share, color: context.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Share Run',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: context.textPrimary,
                          ),
                        ),
                        Text(
                          'Share with your friends',
                          style: TextStyle(
                            fontSize: 13,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Run Preview
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.surfaceElevated,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.directions_run,
                          color: context.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          run.name ?? _formatDate(run.date),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: context.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildRunStat(
                          context,
                          run.formattedDistance,
                          'Distance',
                        ),
                        _buildRunStat(context, run.formattedDuration, 'Time'),
                        _buildRunStat(context, run.formattedPace, 'Pace'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Description
              Text(
                'Description (optional)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _descriptionController,
                maxLines: 3,
                maxLength: 200,
                decoration: InputDecoration(
                  hintText: 'How was your run? Any highlights?',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _isSharing ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _isSharing ? null : _shareRun,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child:
                          _isSharing
                              ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                              : const Text('Share'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRunStat(BuildContext context, String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: context.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: context.textSecondary),
        ),
      ],
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Run';
    return 'Run on ${date.day}/${date.month}/${date.year}';
  }

  Future<void> _shareRun() async {
    setState(() => _isSharing = true);

    try {
      final provider = context.read<SharedWorkoutProvider>();
      final run = widget.run;

      // Build run data as JSON
      final runData = {
        'distance': run.distance,
        'duration': run.duration,
        'pace': run.averagePace,
        'calories': run.calories,
        'routePointCount': run.route.length,
      };

      await provider.shareWorkout(
        originalId: run.id,
        type: 'run',
        workoutName: run.name ?? _formatDate(run.date),
        description:
            _descriptionController.text.trim().isEmpty
                ? null
                : _descriptionController.text.trim(),
        exercisesJson: jsonEncode(runData),
        duration: ((run.duration ?? 0) / 60).round(),
        category: 'Running',
        difficulty: _calculateDifficulty(run),
      );

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to share: $e')));
        setState(() => _isSharing = false);
      }
    }
  }

  String _calculateDifficulty(RunSession run) {
    final distance = run.distance ?? 0;
    final pace = run.averagePace ?? 0;

    // Difficulty based on distance and pace
    if (distance >= 10 || pace <= 5) {
      return 'Advanced';
    } else if (distance >= 5 || pace <= 6) {
      return 'Intermediate';
    }
    return 'Beginner';
  }
}
