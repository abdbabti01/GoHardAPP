import 'dart:collection';

import 'package:flutter/foundation.dart';
import '../core/services/user_session_epoch.dart';
import '../data/models/exercise_set.dart';
import '../data/repositories/exercise_repository.dart';

/// Provider for logging exercise sets.
/// Replaces LogSetsViewModel from MAUI app.
///
/// ## Session ownership
///
/// App-scoped provider: a single instance created with `previous ??`
/// outlives logout/login, so a continuation started under user A must
/// never publish into the state user B now sees through this same
/// instance. Every async method captures `_sessionEpoch.capture()` before
/// its first `await` and rechecks ownership after every `await` - in
/// success, `catch`, and `finally` - before touching `_sets`, a flag, the
/// error, or calling `notifyListeners()`. A `null` capture (logged out)
/// returns immediately using each method's existing return convention
/// without starting work.
///
/// ## Same-session ordering
///
/// - [_loadGen] - identifies the most recent [loadSets] request. Bumped
///   only by [loadSets] (and invalidation), so an A->B->A
///   exercise-navigation race resolves by generation identity rather than
///   by exercise-id equality, and a superseded load still owns - and
///   clears - its own spinner in `finally`.
/// - [_setsRev] - bumped by every mutation that edits `_sets`. A [loadSets]
///   captures it before its `await` and refuses to publish a list fetched
///   before a mutation landed, so a slow load can never drop a newer
///   add/complete/delete. It does NOT gate the spinner, so a mutation
///   cannot strand a concurrent load's `_isLoading`.
/// - [_addGens] - keyed by exerciseId. A superseded add for a target
///   writes nothing (not its list edit, not its error); an add for a
///   different exercise is never superseded by it.
/// - [_setMutationGens] - keyed by set id, SHARED by [completeSet] and
///   [deleteSet] so a complete and a delete targeting the same set order
///   deterministically: an update that resolves after a newer delete for
///   the same set fails its ownership check and cannot resurrect it.
///
/// [clear] and [dispose] bump every generation BEFORE resetting state, so
/// an in-flight continuation cannot repopulate cleared state - even when
/// [clear] is called without a preceding `UserSessionEpoch.invalidate()`.
///
/// ## `_sets` list identity
///
/// [_sets] is a single `final` list that is only ever mutated in place -
/// never reassigned. [sets] hands out an [UnmodifiableListView] over it, so
/// a caller cannot mutate provider state through the getter AND a reference
/// obtained before [clear] reflects the emptying (it is a live view, and
/// [clear] empties the backing list rather than swapping in a new one).
class LogSetsProvider extends ChangeNotifier {
  final ExerciseRepository _exerciseRepository;
  final UserSessionEpoch _sessionEpoch;

  final List<ExerciseSet> _sets = [];
  bool _isLoading = false;
  String? _errorMessage;

  // Identifies the most recent loadSets request - see the class doc.
  int _loadGen = 0;

  // Bumped by every mutation that edits `_sets`. A loadSets captures this
  // before its await and refuses to publish a list fetched before a
  // mutation landed. It deliberately does NOT gate the load spinner.
  int _setsRev = 0;

  // Per-target mutation generations. A superseded (stale) mutation to a
  // target never writes state; a mutation to a different target never
  // supersedes it.
  final Map<int, int> _addGens = {}; // keyed by exerciseId
  final Map<int, int> _setMutationGens = {}; // keyed by set id

  LogSetsProvider(this._exerciseRepository, this._sessionEpoch);

  // Getters
  List<ExerciseSet> get sets => UnmodifiableListView(_sets);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Load sets for an exercise
  Future<void> loadSets(int exerciseId) async {
    final token = _sessionEpoch.capture();
    if (token == null) return;
    final gen = ++_loadGen;
    final rev = _setsRev;

    // True while this is still the newest loadSets request for the current
    // session - owns the spinner and the error slot.
    bool ownsRequest() => _sessionEpoch.isCurrent(token) && gen == _loadGen;
    // Additionally requires that no mutation has edited `_sets` since this
    // load started - only then may it publish the fetched list.
    bool canPublishList() => ownsRequest() && rev == _setsRev;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final sets = await _exerciseRepository.getExerciseSets(exerciseId);
      if (!canPublishList()) return;
      // Sort by set number
      sets.sort((a, b) => a.setNumber.compareTo(b.setNumber));
      _sets
        ..clear()
        ..addAll(sets);
    } catch (e) {
      if (!ownsRequest()) return;
      _errorMessage =
          'Failed to load sets: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Load sets error: $e');
    } finally {
      if (ownsRequest()) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Add a new set
  Future<bool> addSet({
    required int exerciseId,
    required int reps,
    required double weight,
  }) async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;
    final myGen = (_addGens[exerciseId] ?? 0) + 1;
    _addGens[exerciseId] = myGen;

    bool owns() =>
        _sessionEpoch.isCurrent(token) && _addGens[exerciseId] == myGen;

    try {
      // Calculate next set number
      final setNumber =
          _sets.isEmpty
              ? 1
              : _sets.map((s) => s.setNumber).reduce((a, b) => a > b ? a : b) +
                  1;

      final newSet = ExerciseSet(
        id: 0, // Will be assigned by server
        exerciseId: exerciseId,
        setNumber: setNumber,
        reps: reps,
        weight: weight,
        isCompleted: false,
      );

      final createdSet = await _exerciseRepository.createExerciseSet(newSet);
      if (!owns()) return false;

      // Supersede any in-flight list load so it cannot drop this new set.
      _setsRev++;
      _sets
        ..add(createdSet)
        ..sort((a, b) => a.setNumber.compareTo(b.setNumber));
      notifyListeners();
      return true;
    } catch (e) {
      if (!owns()) return false;
      _errorMessage =
          'Failed to add set: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Add set error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Mark set as complete
  Future<void> completeSet(ExerciseSet set) async {
    final token = _sessionEpoch.capture();
    if (token == null) return;
    final setId = set.id;
    final myGen = (_setMutationGens[setId] ?? 0) + 1;
    _setMutationGens[setId] = myGen;

    bool owns() =>
        _sessionEpoch.isCurrent(token) && _setMutationGens[setId] == myGen;

    try {
      final updatedSet = await _exerciseRepository.completeExerciseSet(setId);
      if (!owns()) return;

      // Update in list
      final index = _sets.indexWhere((s) => s.id == setId);
      if (index != -1) {
        _setsRev++;
        _sets[index] = updatedSet;
        notifyListeners();
      }
    } catch (e) {
      if (!owns()) return;
      _errorMessage =
          'Failed to complete set: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Complete set error: $e');
      notifyListeners();
    }
  }

  /// Delete a set
  Future<bool> deleteSet(ExerciseSet set) async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;
    final setId = set.id;
    final myGen = (_setMutationGens[setId] ?? 0) + 1;
    _setMutationGens[setId] = myGen;

    bool owns() =>
        _sessionEpoch.isCurrent(token) && _setMutationGens[setId] == myGen;

    try {
      final success = await _exerciseRepository.deleteExerciseSet(setId);
      if (!owns()) return false;
      if (!success) return false;

      // Supersede any in-flight list load so it cannot resurrect the set.
      _setsRev++;
      final remaining = _sets.where((s) => s.id != setId).toList();

      // Renumber remaining sets
      for (int i = 0; i < remaining.length; i++) {
        remaining[i] = ExerciseSet(
          id: remaining[i].id,
          exerciseId: remaining[i].exerciseId,
          setNumber: i + 1,
          reps: remaining[i].reps,
          weight: remaining[i].weight,
          duration: remaining[i].duration,
          isCompleted: remaining[i].isCompleted,
          completedAt: remaining[i].completedAt,
          notes: remaining[i].notes,
        );
      }

      _sets
        ..clear()
        ..addAll(remaining);
      notifyListeners();
      return true;
    } catch (e) {
      if (!owns()) return false;
      _errorMessage =
          'Failed to delete set: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Delete set error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Invalidate every generation so no in-flight continuation or mutation
  /// can publish after this returns.
  void _invalidateGenerations() {
    _loadGen++;
    _setsRev++;
    _addGens.updateAll((_, value) => value + 1);
    _setMutationGens.updateAll((_, value) => value + 1);
  }

  /// Clear all logged-set state (called on logout via
  /// [SessionCleanupCoordinator]).
  ///
  /// Every generation is bumped BEFORE any state is reset, so a load or
  /// mutation continuation that resolves after this returns fails its
  /// ownership check and can neither repopulate the cleared list nor
  /// re-expose the previous user's error. In the live logout path
  /// `UserSessionEpoch.invalidate()` has already run, so `isCurrent(token)`
  /// is also false; the generation bumps make this correct even when
  /// `clear()` is called on its own.
  ///
  /// [_sets] is emptied in place (not reassigned), so any [sets] view a
  /// caller obtained before this call also becomes empty - the previous
  /// user's set data is not retained behind a stale reference.
  void clear() {
    _invalidateGenerations();

    _sets.clear();
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
    debugPrint('🧹 LogSetsProvider cleared');
  }

  @override
  void dispose() {
    _invalidateGenerations();
    super.dispose();
  }
}
