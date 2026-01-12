import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/sessions_provider.dart';
import '../../../providers/exercises_provider.dart';
import '../../../core/constants/workout_names.dart';
import '../../../data/models/exercise_template.dart';

/// Screen for creating planned workouts (future workouts)
class PlannedWorkoutFormScreen extends StatefulWidget {
  const PlannedWorkoutFormScreen({super.key});

  @override
  State<PlannedWorkoutFormScreen> createState() =>
      _PlannedWorkoutFormScreenState();
}

class _PlannedWorkoutFormScreenState extends State<PlannedWorkoutFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _notesController = TextEditingController();
  final _durationController = TextEditingController();

  DateTime? _selectedDate;
  String? _selectedType;
  List<ExerciseTemplate> _selectedExercises = [];

  final List<String> _workoutTypes = [
    'Strength',
    'Cardio',
    'Mixed',
    'Flexibility',
    'HIIT',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: today.add(const Duration(days: 1)),
      firstDate: today,
      lastDate: DateTime(now.year + 1, now.month, now.day),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            datePickerTheme: DatePickerThemeData(
              backgroundColor: Theme.of(context).cardColor,
              headerBackgroundColor: Theme.of(context).primaryColor,
              headerForegroundColor: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _selectExercises() async {
    final exercisesProvider = context.read<ExercisesProvider>();
    final buildContext = context;

    // Load exercises if not loaded
    if (exercisesProvider.filteredExercises.isEmpty) {
      await exercisesProvider.loadExercises();
    }

    final selected = await showDialog<List<ExerciseTemplate>>(
      // ignore: use_build_context_synchronously
      context: buildContext,
      builder:
          (context) => _ExerciseSelectionDialog(
            initialSelection: _selectedExercises,
            exercises: exercisesProvider.filteredExercises,
          ),
    );

    if (!mounted) return;

    if (selected != null) {
      setState(() {
        _selectedExercises = selected;
      });
    }
  }

  Future<void> _createPlannedWorkout() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a date'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final provider = context.read<SessionsProvider>();

    final session = await provider.createPlannedWorkout(
      name: _nameController.text.trim(),
      scheduledDate: _selectedDate!,
      type: _selectedType,
      notes:
          _notesController.text.trim().isNotEmpty
              ? _notesController.text.trim()
              : null,
      estimatedDuration:
          _durationController.text.isNotEmpty
              ? int.tryParse(_durationController.text)
              : null,
      exerciseTemplateIds:
          _selectedExercises.isNotEmpty
              ? _selectedExercises.map((e) => e.id).toList()
              : null,
    );

    if (session != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${session.name} scheduled for ${_formatDate(_selectedDate!)}',
          ),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(true); // Return true to indicate success
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to create planned workout'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _formatDate(DateTime date) {
    const months = [
      '',
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
    return '${months[date.month]} ${date.day}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Plan Workout'), centerTitle: true),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Info card
            Card(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.event, color: Theme.of(context).primaryColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Schedule a workout for a future date',
                        style: TextStyle(
                          color: Theme.of(context).primaryColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Date Selection (Required)
            Text(
              'Scheduled Date *',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _selectDate,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(
                    color:
                        _selectedDate == null
                            ? Colors.grey
                            : Theme.of(context).primaryColor,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      color:
                          _selectedDate == null
                              ? Colors.grey
                              : Theme.of(context).primaryColor,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _selectedDate == null
                          ? 'Select a date'
                          : _formatDate(_selectedDate!),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight:
                            _selectedDate == null
                                ? FontWeight.normal
                                : FontWeight.bold,
                        color:
                            _selectedDate == null
                                ? Colors.grey
                                : Theme.of(context).primaryColor,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.arrow_drop_down,
                      color:
                          _selectedDate == null
                              ? Colors.grey
                              : Theme.of(context).primaryColor,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Workout Name (Required, Autocomplete)
            Text(
              'Workout Name *',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Autocomplete<String>(
              optionsBuilder: (TextEditingValue textEditingValue) {
                if (textEditingValue.text.isEmpty) {
                  return WorkoutNames.allWorkoutNames;
                }
                return WorkoutNames.allWorkoutNames.where((String option) {
                  return option.toLowerCase().contains(
                    textEditingValue.text.toLowerCase(),
                  );
                });
              },
              onSelected: (String selection) {
                _nameController.text = selection;
              },
              fieldViewBuilder: (
                context,
                controller,
                focusNode,
                onFieldSubmitted,
              ) {
                // Sync with our main controller
                _nameController.text = controller.text;
                controller.addListener(() {
                  _nameController.text = controller.text;
                });

                return TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: const InputDecoration(
                    hintText: 'e.g., Leg Day, Push Day, Cardio...',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.fitness_center),
                  ),
                  textCapitalization: TextCapitalization.words,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a workout name';
                    }
                    return null;
                  },
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(8),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxHeight: 300,
                        maxWidth: 400,
                      ),
                      child: ListView.builder(
                        padding: const EdgeInsets.all(8),
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (context, index) {
                          final option = options.elementAt(index);
                          return ListTile(
                            title: Text(option),
                            onTap: () => onSelected(option),
                            dense: true,
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),

            // Workout Type (Optional)
            Text(
              'Workout Type',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedType,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Select type (optional)',
                prefixIcon: Icon(Icons.category),
              ),
              items:
                  _workoutTypes.map((type) {
                    return DropdownMenuItem(value: type, child: Text(type));
                  }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedType = value;
                });
              },
            ),
            const SizedBox(height: 24),

            // Estimated Duration (Optional)
            Text(
              'Estimated Duration (minutes)',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _durationController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'e.g., 60',
                prefixIcon: Icon(Icons.timer),
                suffixText: 'min',
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value != null && value.isNotEmpty) {
                  final duration = int.tryParse(value);
                  if (duration == null || duration <= 0) {
                    return 'Please enter a valid duration';
                  }
                }
                return null;
              },
            ),
            const SizedBox(height: 24),

            // Exercises (Optional)
            Text(
              'Exercises (Optional)',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 2,
              child: InkWell(
                onTap: _selectExercises,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.fitness_center,
                            color: Theme.of(context).primaryColor,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _selectedExercises.isEmpty
                                  ? 'Add exercises to this workout'
                                  : '${_selectedExercises.length} exercise${_selectedExercises.length == 1 ? '' : 's'} selected',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight:
                                    _selectedExercises.isEmpty
                                        ? FontWeight.normal
                                        : FontWeight.bold,
                                color:
                                    _selectedExercises.isEmpty
                                        ? Colors.grey
                                        : Theme.of(context).primaryColor,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                            color: Colors.grey,
                          ),
                        ],
                      ),
                      if (_selectedExercises.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Divider(),
                        const SizedBox(height: 8),
                        ..._selectedExercises.map((exercise) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  size: 18,
                                  color: Colors.green,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    exercise.name,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Notes (Optional)
            Text(
              'Notes',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Add notes or goals for this workout...',
                prefixIcon: Icon(Icons.notes),
              ),
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 32),

            // Create Button
            ElevatedButton.icon(
              onPressed: _createPlannedWorkout,
              icon: const Icon(Icons.add),
              label: const Text('Create Planned Workout'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog for selecting exercises to add to a planned workout
class _ExerciseSelectionDialog extends StatefulWidget {
  final List<ExerciseTemplate> initialSelection;
  final List<ExerciseTemplate> exercises;

  const _ExerciseSelectionDialog({
    required this.initialSelection,
    required this.exercises,
  });

  @override
  State<_ExerciseSelectionDialog> createState() =>
      _ExerciseSelectionDialogState();
}

class _ExerciseSelectionDialogState extends State<_ExerciseSelectionDialog> {
  late List<ExerciseTemplate> _selectedExercises;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedExercises = List.from(widget.initialSelection);
  }

  List<ExerciseTemplate> get _filteredExercises {
    if (_searchQuery.isEmpty) {
      return widget.exercises;
    }
    return widget.exercises.where((exercise) {
      return exercise.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (exercise.muscleGroup?.toLowerCase().contains(
                _searchQuery.toLowerCase(),
              ) ??
              false);
    }).toList();
  }

  void _toggleExercise(ExerciseTemplate exercise) {
    setState(() {
      if (_selectedExercises.any((e) => e.id == exercise.id)) {
        _selectedExercises.removeWhere((e) => e.id == exercise.id);
      } else {
        _selectedExercises.add(exercise);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Column(
          children: [
            // Header
            AppBar(
              title: const Text('Select Exercises'),
              automaticallyImplyLeading: false,
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                TextButton(
                  onPressed:
                      () => Navigator.of(context).pop(_selectedExercises),
                  child: Text(
                    'Done (${_selectedExercises.length})',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            // Search bar
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search exercises...',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Theme.of(context).cardColor,
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
              ),
            ),

            // Exercise list
            Expanded(
              child:
                  _filteredExercises.isEmpty
                      ? const Center(child: Text('No exercises found'))
                      : ListView.builder(
                        itemCount: _filteredExercises.length,
                        itemBuilder: (context, index) {
                          final exercise = _filteredExercises[index];
                          final isSelected = _selectedExercises.any(
                            (e) => e.id == exercise.id,
                          );

                          return CheckboxListTile(
                            title: Text(exercise.name),
                            subtitle: Text(
                              exercise.muscleGroup ?? '',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                            value: isSelected,
                            onChanged: (_) => _toggleExercise(exercise),
                            secondary: Icon(
                              Icons.fitness_center,
                              color: Theme.of(context).primaryColor,
                            ),
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
    );
  }
}
