import 'package:flutter/material.dart';

/// Preview card for displaying AI-generated workout plans in chat
/// Shows structured workout data with expandable days and action buttons
class WorkoutPlanPreviewCard extends StatefulWidget {
  final Map<String, dynamic> planData;
  final VoidCallback onCreateProgram;
  final VoidCallback? onEdit;
  final VoidCallback? onRegenerate;

  const WorkoutPlanPreviewCard({
    super.key,
    required this.planData,
    required this.onCreateProgram,
    this.onEdit,
    this.onRegenerate,
  });

  @override
  State<WorkoutPlanPreviewCard> createState() => _WorkoutPlanPreviewCardState();
}

class _WorkoutPlanPreviewCardState extends State<WorkoutPlanPreviewCard> {
  bool _isExpanded = false;

  List<dynamic> get sessions => (widget.planData['sessions'] as List?) ?? [];

  String get programName =>
      widget.planData['programName'] as String? ?? 'Workout Plan';

  String get splitType =>
      widget.planData['splitType'] as String? ?? _inferSplitType();

  int get totalWeeks => widget.planData['totalWeeks'] as int? ?? 12;

  String _inferSplitType() {
    if (sessions.isEmpty) return 'Custom';

    final names =
        sessions
            .map((s) => (s['name'] as String? ?? '').toLowerCase())
            .toList();

    if (names.any((n) => n.contains('push')) &&
        names.any((n) => n.contains('pull'))) {
      return 'Push/Pull/Legs';
    } else if (names.any((n) => n.contains('upper')) &&
        names.any((n) => n.contains('lower'))) {
      return 'Upper/Lower';
    } else if (names.any((n) => n.contains('full body'))) {
      return 'Full Body';
    }

    return '${sessions.length}-Day Split';
  }

  int _countTotalExercises() {
    int total = 0;
    for (final session in sessions) {
      final exercises = (session['exercises'] as List?) ?? [];
      total += exercises.length;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          _buildHeader(context),

          // Quick stats
          _buildQuickStats(context),

          // Expandable workout days
          _buildWorkoutsList(context),

          // Action buttons
          _buildActionButtons(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.fitness_center,
              color: Colors.blue,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Workout Plan Ready',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${sessions.length}-Day $splitType',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          if (widget.onEdit != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: widget.onEdit,
              tooltip: 'Edit Plan',
              color: Colors.blue,
            ),
        ],
      ),
    );
  }

  Widget _buildQuickStats(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _buildStatChip(
            icon: Icons.calendar_today,
            label: '$totalWeeks weeks',
            color: Colors.purple,
          ),
          const SizedBox(width: 8),
          _buildStatChip(
            icon: Icons.fitness_center,
            label: '${sessions.length} days/week',
            color: Colors.blue,
          ),
          const SizedBox(width: 8),
          _buildStatChip(
            icon: Icons.list,
            label: '${_countTotalExercises()} exercises',
            color: Colors.orange,
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkoutsList(BuildContext context) {
    return Column(
      children: [
        // Toggle expand button
        InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(
                  _isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 8),
                Text(
                  _isExpanded ? 'Hide Workouts' : 'View Workouts',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Expanded workout list
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Column(
            children:
                sessions.asMap().entries.map((entry) {
                  return _buildSessionTile(
                    entry.key + 1,
                    entry.value as Map<String, dynamic>,
                  );
                }).toList(),
          ),
          crossFadeState:
              _isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }

  Widget _buildSessionTile(int dayNumber, Map<String, dynamic> session) {
    final name = session['name'] as String? ?? 'Day $dayNumber';
    final type = session['type'] as String? ?? 'Strength';
    final exercises = (session['exercises'] as List?) ?? [];
    final notes = session['notes'] as String?;

    return ExpansionTile(
      leading: CircleAvatar(
        backgroundColor: Colors.blue.withValues(alpha: 0.2),
        radius: 18,
        child: Text(
          'D$dayNumber',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: Colors.blue,
          ),
        ),
      ),
      title: Text(
        name,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Text(
        '${exercises.length} exercises${type.isNotEmpty ? ' • $type' : ''}',
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      ),
      children: [
        if (notes != null && notes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    notes,
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ...exercises.map(
          (exercise) => _buildExerciseTile(exercise as Map<String, dynamic>),
        ),
      ],
    );
  }

  Widget _buildExerciseTile(Map<String, dynamic> exercise) {
    final name = exercise['name'] as String? ?? 'Unknown Exercise';
    final sets = exercise['sets'];
    final reps = exercise['reps'];
    final restTime = exercise['restTime'];
    final notes = exercise['notes'] as String?;

    String details = '';
    if (sets != null) details += '$sets sets';
    if (reps != null) details += details.isNotEmpty ? ' x $reps' : '$reps reps';
    if (restTime != null) {
      details +=
          details.isNotEmpty ? ' • ${restTime}s rest' : '${restTime}s rest';
    }

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      leading: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(Icons.fitness_center, size: 16, color: Colors.grey),
      ),
      title: Text(
        name,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (details.isNotEmpty)
            Text(
              details,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          if (notes != null && notes.isNotEmpty)
            Text(
              notes,
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: Colors.blue.shade600,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Row(
        children: [
          if (widget.onRegenerate != null) ...[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: widget.onRegenerate,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Regenerate'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey.shade700,
                  side: BorderSide(color: Colors.grey.shade300),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: widget.onCreateProgram,
              icon: const Icon(Icons.add_circle_outline, size: 18),
              label: const Text('Create Program'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
