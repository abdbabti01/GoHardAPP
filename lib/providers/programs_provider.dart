import 'dart:async';
import 'package:flutter/material.dart';
import '../core/services/user_session_epoch.dart';
import '../data/models/program.dart';
import '../data/models/program_workout.dart';
import '../data/repositories/programs_repository.dart';
import '../data/services/session_request_exceptions.dart';
import '../core/services/connectivity_service.dart';

/// Provider for programs management.
///
/// ## Session ownership
///
/// App-scoped provider: a single instance created with `previous ??`
/// outlives logout/login (see main.dart), so a continuation started under
/// user A must never publish into the state user B now sees through this
/// same instance. Every async method captures `_sessionEpoch.capture()`
/// before its first `await` and rechecks ownership after every `await` - in
/// the success path, `catch`, and `finally` - before it touches `_programs`,
/// the derived `_activePrograms` / `_completedPrograms` lists, any nested
/// `workouts`, the loading / creating / updating flags, `_errorMessage`, or
/// `notifyListeners()`. A `null` capture (logged out) returns immediately
/// using each method's existing return convention without starting work.
///
/// [SessionStaleException] / [RequestCancelledException] raised by the
/// repository are expected lifecycle outcomes, not failures: every method
/// intercepts both before its generic `catch`, so a session ending mid-flight
/// is dropped silently rather than surfaced as a user-visible error.
///
/// ## No optimistic mutations
///
/// Every mutation in this provider (program-level and nested-workout) issues
/// its HTTP call FIRST and only edits `_programs` AFTER an owned success -
/// exactly as the pre-PR code did. Nothing is applied before the `await`, so
/// there is no optimistic placeholder, no rollback, and no temporary id
/// anywhere. This PR deliberately does not introduce optimistic behaviour
/// (there is none to protect). The post-success edit doubles as the
/// Order-B convergence step: it is applied by stable id after `if (!owns())
/// return`, so a slower `loadPrograms()` that already republished a
/// pre-mutation server list cannot leave the mutation's effect lost.
///
/// ## Same-session ordering and resource identity
///
/// Session identity alone cannot order two requests within one session, so
/// each independently-refreshable resource carries a monotonically
/// increasing generation:
///
/// - [_listGen] - the programs list. Bumped by [loadPrograms] AND by every
///   successful program / nested-workout mutation, so a slower in-flight list
///   load can neither resurrect a program a newer mutation removed nor
///   overwrite a newer mutation's list edit (Order A). [recalibrateProgram]
///   refreshes by awaiting [loadPrograms] itself, so it inherits that
///   ordering.
/// - [_programMutationGens] - keyed by program id, SHARED by
///   [updateProgram], [deleteProgram], [completeProgram], [advanceProgram]
///   AND [recalibrateProgram] on that SAME id. A stale mutation to a program
///   writes nothing (not its list edit, not its error); a mutation to a
///   DIFFERENT program is never superseded by it. Because all five share one
///   counter per id, an older update whose delete of the SAME program already
///   completed cannot resurrect it, and an older update can never undo a
///   newer completion / recalibration / advancement.
/// - [_workoutMutationGens] - keyed by the composite `(programId, workoutId)`,
///   SHARED by [addWorkout] (via [_workoutAddGens], see below), [updateWorkout],
///   [swapWorkouts] (both keys), [completeWorkout] and [deleteWorkout]. So a
///   child mutation for Program A's workout can never touch Program B; two
///   workouts that (were the model to allow it) share an id under different
///   programs stay isolated; an older child update cannot undo a newer swap,
///   delete or completion; and overlapping swaps are ordered deterministically
///   (the later swap bumps the shared keys the earlier one's `owns()` reads).
/// - [_workoutAddGens] - keyed by program id, a monotonic supersede-chain for
///   [addWorkout] (which has no child id until the server assigns one).
/// - Parent deletion: a successful [deleteProgram] calls
///   [_invalidateChildGensFor], bumping every [_workoutMutationGens] /
///   [_workoutAddGens] entry under that program id, so an in-flight child
///   mutation for the just-deleted program publishes nothing.
/// - [_detailGen] / [_weekGen] / [_todayGen] order one direct-return read
///   ([getProgramById] / [getWeekWorkouts] / [getTodaysWorkout]) against
///   another on the same axis. The result is returned to the caller, never
///   stored, so there is no "A -> B -> A" stored field; the return is gated by
///   a final [UserSessionEpoch.isCurrent] check so a value computed for A
///   never reaches a caller now resolving under B.
/// - [_impactGen] - orders one [getDeletionImpact] against another; a stale
///   session or a superseded request throws [SessionStaleException] rather
///   than handing back another request's numbers.
/// - [_createGen] - a monotonic supersede-chain for [createProgram]; it also
///   owns [createProgram]'s `_isCreating` flag.
///
/// ## Shared error ownership
///
/// `_errorMessage` is one shared field written by many axes. [_errorGen] is a
/// single global error-publication generation, bumped by every error-capable
/// method at entry (and by [_invalidateGenerations]): an error write only
/// lands if the writing op is still the newest error-slot claimant
/// (`errorGen == _errorGen`) AND passes its own axis `owns()`. So an older
/// request that fails after a newer request already published its error can
/// no longer clobber it. [getDeletionImpact] deliberately does NOT
/// participate - it never writes `_errorMessage` (it rethrows to its caller).
///
/// ## Activity flags
///
/// `_isLoading` is owned solely by [loadPrograms]: its publication is ordered
/// via [_listGen], but its `finally` reset is guarded by [_loadGen] (bumped
/// only by another [loadPrograms] or by [_invalidateGenerations]) so a newer
/// same-session mutation that bumps [_listGen] cannot strand the spinner,
/// while a newer load or a `clear()` still silences the stale finally.
/// `_isCreating` is a plain bool owned by the monotonic [_createGen].
/// `isUpdating` is derived from [_activeUpdateCounts] - a multiset of the
/// program ids with an [updateProgram] PUT in flight, incremented at entry
/// and decremented exactly once per call, so it stays correct while several
/// updates (to the same or different programs) overlap and is emptied by
/// [clear].
///
/// ## List / filter / view identity
///
/// `loadPrograms({isActive})` forwards `isActive` to the repository and
/// replaces `_programs` with that response, so `_programs` represents the
/// latest published query result - NOT an unconditional master cache -
/// whenever a caller uses the public filter (no production caller does today,
/// but the contract is public). [_publishedIsActiveFilter] records which
/// filter the currently-published list belongs to: `null` = unfiltered (or
/// nothing published yet), `true` / `false` = the `isActive` argument of the
/// last owned [loadPrograms]. It is set ONLY by [loadPrograms] on owned
/// success and reset ONLY by [clear] - never by [_invalidateGenerations],
/// because it is a view identity, not a generation.
///
/// Every mutation convergence that upserts a Program into `_programs`
/// ([createProgram], [updateProgram], [completeProgram], [advanceProgram])
/// routes through [_reconcileByFilter] / [_belongsInPublishedList], which
/// keeps a row only while it belongs in that filtered view and otherwise
/// drops it. So a just-completed (hence inactive) Program never lingers in an
/// `isActive: true` list, and a created/advanced Program that does not match
/// the filter is not inserted. [deleteProgram] (removing an id) stays
/// filter-agnostic. Nested-workout mutations never change a Program's
/// `isActive`, so they keep their plain in-place row assignment.
/// `_activePrograms` / `_completedPrograms` remain pure derived views of
/// whatever `_programs` currently holds, recomputed by
/// [_recomputeDerivedLists].
///
/// Four related-but-distinct things are kept apart:
///
/// - [_publishedIsActiveFilter] - the filter the list currently *displayed*
///   in `_programs` belongs to (set on owned [loadPrograms] success).
/// - [_latestRequestedIsActiveFilter] - the filter of the *most recent list
///   request intent* (set at [loadPrograms] entry, BEFORE its first `await`,
///   whether or not that request goes on to win the publish race). An
///   internal follow-up refresh - [recalibrateProgram]'s trailing reload and
///   the connectivity-restored callback - forwards THIS, not the published
///   filter, so it targets the newest requested view. Example: an
///   `isActive: true` list is showing; `recalibrateProgram` starts; a newer
///   manual `loadPrograms(isActive: false)` starts while it is pending;
///   `recalibrateProgram` then acknowledges and reloads - it must reload
///   `isActive: false` (the newer intent), never revert to the
///   currently-published `true` or to unfiltered. Reset only by [clear].
/// - [_listGen] - which list *response* is allowed to publish.
/// - [_programMutationGens] `[A]` - whether [recalibrateProgram] still owns
///   Program A's mutation slot.
///
/// ## List identity
///
/// [_programs], [_activePrograms] and [_completedPrograms] are all `final`
/// lists, only ever mutated in place - never reassigned - so a caller holding
/// a reference (via the getters) also observes a [clear] or reload as that
/// same list emptying / repopulating.
///
/// ## Cleanup and connectivity ownership
///
/// [clear] and [dispose] call [_invalidateGenerations] BEFORE resetting
/// state, so an in-flight continuation can neither repopulate cleared state
/// nor resurrect a previous session's program - even when [clear] is called
/// without a preceding `UserSessionEpoch.invalidate()`.
///
/// The connectivity-restored callback captures a fresh token on every
/// invocation and no-ops entirely if there is no active session, so a
/// connectivity flap while logged out can never dispatch a refresh for
/// nobody. It refreshes on every reconnect (unchanged from the pre-PR
/// behaviour) except when a load is already running, to avoid stacking a
/// redundant duplicate. The refresh it triggers is
/// `loadPrograms(isActive: _latestRequestedIsActiveFilter)` - the newest
/// requested view, so it never silently widens a filtered list to unfiltered
/// - and it is bound by the exact same [_listGen] ordering as a manual
/// refresh, so it can never overwrite a newer mutation.
class ProgramsProvider extends ChangeNotifier {
  final ProgramsRepository _programsRepository;
  final UserSessionEpoch _sessionEpoch;
  final ConnectivityService? _connectivity;

  final List<Program> _programs = [];
  final List<Program> _activePrograms = [];
  final List<Program> _completedPrograms = [];
  bool _isLoading = false;
  bool _isCreating = false;
  String? _errorMessage;
  int? _newlyCreatedProgramId; // Used to auto-select after creation

  // The `isActive` filter identity of the list currently published in
  // [_programs] (see "List / filter / view identity"). `null` = unfiltered /
  // nothing published yet. Set only by [loadPrograms] on owned success, reset
  // only by [clear].
  bool? _publishedIsActiveFilter;

  // The `isActive` of the most recent list-request INTENT - assigned at
  // [loadPrograms] entry, before its first `await`, regardless of whether that
  // request goes on to win the publish race. An internal follow-up refresh
  // ([recalibrateProgram]'s trailing reload, the connectivity callback)
  // forwards this so it targets the newest requested view rather than the
  // currently-published (possibly about-to-be-superseded) one. Reset only by
  // [clear].
  bool? _latestRequestedIsActiveFilter;

  StreamSubscription<bool>? _connectivitySubscription;

  // Monotonic per-resource generations - see the class doc comment.
  int _listGen = 0;
  // Bumped ONLY by [loadPrograms] entry and [_invalidateGenerations] - never
  // by a mutation. Guards the `_isLoading` reset in [loadPrograms]'s `finally`
  // so a newer same-session mutation (which bumps [_listGen] to block this
  // load's publication) cannot strand the spinner, while a newer load or a
  // `clear()` still silences the stale finally.
  int _loadGen = 0;
  int _detailGen = 0;
  int _weekGen = 0;
  int _todayGen = 0;
  int _impactGen = 0;
  int _createGen = 0;

  // Global error-publication generation - see "Shared error ownership".
  int _errorGen = 0;

  // Per-program mutation generations, keyed by program id and shared by
  // updateProgram/deleteProgram/completeProgram/advanceProgram/
  // recalibrateProgram - see the class doc comment.
  final Map<int, int> _programMutationGens = {};

  // Per-child mutation generations, keyed by the composite
  // (programId, workoutId) and shared by updateWorkout/swapWorkouts/
  // completeWorkout/deleteWorkout - see the class doc comment.
  final Map<(int, int), int> _workoutMutationGens = {};

  // Per-program "add a workout" supersede-chains for addWorkout, which has no
  // child id until the server assigns one.
  final Map<int, int> _workoutAddGens = {};

  // Multiset of program ids with an updateProgram PUT in flight - drives
  // `isUpdating`. Incremented at entry, decremented exactly once per call.
  final Map<int, int> _activeUpdateCounts = {};

  /// Test-only seam: invoked with the `Future` returned by the
  /// connectivity-restored listener's own call to [loadPrograms], so a test
  /// can await the real ownership path to completion deterministically
  /// instead of pumping the event loop. Null in production; setting it never
  /// changes control flow or performance.
  @visibleForTesting
  void Function(Future<void> refresh)? onConnectivityRefreshForTesting;

  ProgramsProvider(
    this._programsRepository,
    this._sessionEpoch, [
    this._connectivity,
  ]) {
    // Listen for connectivity changes and refresh when going online. This
    // callback can fire at any point in the app's lifetime, including during
    // a logged-out gap between one user's logout and the next user's login -
    // capture a token fresh on every invocation and skip entirely if there
    // is no active session (see the class doc comment).
    _connectivitySubscription = _connectivity?.connectivityStream.listen((
      isOnline,
    ) {
      final token = _sessionEpoch.capture();
      if (token == null) return;
      // Refresh on every reconnect (unchanged from the pre-PR behaviour),
      // except never stack a second full-list load on top of one already
      // running. Forward the newest requested filter so a reconnect never
      // silently widens a filtered list to unfiltered; the load it triggers
      // is [loadPrograms] itself, so it stays bound by the same [_listGen]
      // ordering as a manual refresh and can never overwrite a newer mutation.
      if (isOnline && !_isLoading) {
        debugPrint('📡 Connection restored - refreshing programs');
        final refresh = loadPrograms(isActive: _latestRequestedIsActiveFilter);
        onConnectivityRefreshForTesting?.call(refresh);
      }
    });
  }

  // Getters
  List<Program> get programs => _programs;
  List<Program> get activePrograms => _activePrograms;
  List<Program> get completedPrograms => _completedPrograms;
  bool get isLoading => _isLoading;
  bool get isCreating => _isCreating;
  bool get isUpdating => _activeUpdateCounts.isNotEmpty;
  String? get errorMessage => _errorMessage;
  int? get newlyCreatedProgramId => _newlyCreatedProgramId;

  /// Set the newly created program ID (for auto-selection)
  void setNewlyCreatedProgramId(int? id) {
    _newlyCreatedProgramId = id;
    notifyListeners();
  }

  /// Clear the newly created program ID after selection
  void clearNewlyCreatedProgramId() {
    _newlyCreatedProgramId = null;
  }

  // ---------------------------------------------------------------------------
  // Generation helpers
  // ---------------------------------------------------------------------------

  int _bumpProgramMutationGen(int id) {
    final next = (_programMutationGens[id] ?? 0) + 1;
    _programMutationGens[id] = next;
    return next;
  }

  int _bumpWorkoutMutationGen((int, int) key) {
    final next = (_workoutMutationGens[key] ?? 0) + 1;
    _workoutMutationGens[key] = next;
    return next;
  }

  int _bumpWorkoutAddGen(int programId) {
    final next = (_workoutAddGens[programId] ?? 0) + 1;
    _workoutAddGens[programId] = next;
    return next;
  }

  /// Bumps every child generation under [programId] so an in-flight
  /// nested-workout mutation for a just-deleted program publishes nothing.
  void _invalidateChildGensFor(int programId) {
    for (final key in _workoutMutationGens.keys.toList()) {
      if (key.$1 == programId) {
        _workoutMutationGens[key] = _workoutMutationGens[key]! + 1;
      }
    }
    final addGen = _workoutAddGens[programId];
    if (addGen != null) _workoutAddGens[programId] = addGen + 1;
  }

  int? _parentProgramIdForWorkout(int workoutId) {
    for (final p in _programs) {
      final ws = p.workouts;
      if (ws != null && ws.any((w) => w.id == workoutId)) return p.id;
    }
    return null;
  }

  void _beginUpdateTracking(int id) =>
      _activeUpdateCounts.update(id, (c) => c + 1, ifAbsent: () => 1);

  void _endUpdateTracking(int id) {
    final c = _activeUpdateCounts[id];
    if (c == null) return;
    if (c <= 1) {
      _activeUpdateCounts.remove(id);
    } else {
      _activeUpdateCounts[id] = c - 1;
    }
  }

  /// Whether [p] belongs in the list currently published in [_programs] given
  /// the [_publishedIsActiveFilter] identity. A `null` filter (unfiltered, or
  /// nothing loaded yet) admits every Program.
  bool _belongsInPublishedList(Program p) {
    final filter = _publishedIsActiveFilter;
    return filter == null || p.isActive == filter;
  }

  /// Reconciles [program] into [_programs] by stable id, honouring the current
  /// filter identity: upsert it in place if it [_belongsInPublishedList],
  /// otherwise remove any row carrying its id. Idempotent; used by every
  /// mutation convergence that publishes a Program so the list stays
  /// internally consistent with the filter that produced it. Returns `true`
  /// iff [_programs] actually changed.
  bool _reconcileByFilter(int id, Program program) {
    final i = _programs.indexWhere((p) => p.id == id);
    if (_belongsInPublishedList(program)) {
      if (i != -1) {
        if (identical(_programs[i], program)) return false;
        _programs[i] = program;
      } else {
        _programs.add(program);
      }
      return true;
    }
    if (i == -1) return false;
    _programs.removeAt(i);
    return true;
  }

  /// Recompute the derived active / completed views from whatever [_programs]
  /// currently holds, in place so retained references stay valid.
  void _recomputeDerivedLists() {
    _activePrograms
      ..clear()
      ..addAll(_programs.where((p) => p.isActive));
    _completedPrograms
      ..clear()
      ..addAll(_programs.where((p) => p.isCompleted));
  }

  /// Invalidate every request / mutation generation so no in-flight
  /// continuation can publish after this returns.
  void _invalidateGenerations() {
    _listGen++;
    _loadGen++;
    _detailGen++;
    _weekGen++;
    _todayGen++;
    _impactGen++;
    _createGen++;
    _errorGen++;
    _programMutationGens.updateAll((_, v) => v + 1);
    _workoutMutationGens.updateAll((_, v) => v + 1);
    _workoutAddGens.updateAll((_, v) => v + 1);
  }

  // ---------------------------------------------------------------------------
  // Program list
  // ---------------------------------------------------------------------------

  /// Load all programs for the current user
  Future<void> loadPrograms({bool? isActive}) async {
    final token = _sessionEpoch.capture();
    if (token == null) return;
    final gen = ++_listGen;
    final loadGen = ++_loadGen;
    final errorGen = ++_errorGen;

    // Record the request INTENT before the first await - regardless of whether
    // this request goes on to win the publish race - so an internal follow-up
    // refresh ([recalibrateProgram], the connectivity callback) can target the
    // newest requested view.
    _latestRequestedIsActiveFilter = isActive;

    bool owns() => _sessionEpoch.isCurrent(token) && gen == _listGen;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _programsRepository.getPrograms(isActive: isActive);
      if (!owns()) return;

      _programs
        ..clear()
        ..addAll(result);
      // Remember which filter this published list represents, so a later
      // mutation convergence reconciles against the right identity.
      _publishedIsActiveFilter = isActive;
      _recomputeDerivedLists();

      debugPrint(
        '✅ Loaded ${_programs.length} programs (${_activePrograms.length} active, ${_completedPrograms.length} completed)',
      );
    } on SessionStaleException {
      return;
    } on RequestCancelledException {
      return;
    } catch (e) {
      if (!owns() || errorGen != _errorGen) return;
      _errorMessage =
          'Failed to load programs: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Load programs error: $e');
    } finally {
      // `_isLoading` means "did MY fetch finish". Guard on [_loadGen] (bumped
      // only by another loadPrograms or by clear()/dispose()), NOT [_listGen]:
      // a newer same-session mutation bumps `_listGen` to block this load's
      // *publication* above but must not strand the spinner, while a newer
      // load or a `clear()` still silences this stale finally.
      if (_sessionEpoch.isCurrent(token) && loadGen == _loadGen) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Get a specific program by ID with all workouts (from API). Not published
  /// into shared Provider state - returned directly to the caller.
  Future<Program?> getProgramById(int id) async {
    final token = _sessionEpoch.capture();
    if (token == null) return null;
    final gen = ++_detailGen;
    final errorGen = ++_errorGen;

    bool owns() => _sessionEpoch.isCurrent(token) && gen == _detailGen;

    try {
      final program = await _programsRepository.getProgramById(id);
      // A result computed for A's session must never reach a caller now
      // resolving under B.
      return _sessionEpoch.isCurrent(token) ? program : null;
    } on SessionStaleException {
      return null;
    } on RequestCancelledException {
      return null;
    } catch (e) {
      if (!owns() || errorGen != _errorGen) return null;
      _errorMessage =
          'Failed to load program: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Load program error: $e');
      notifyListeners();
      return null;
    }
  }

  /// Get a program from local cache by ID (no API call)
  /// Returns null if not found in local cache
  Program? getProgramFromCache(int id) {
    try {
      return _programs.firstWhere((p) => p.id == id);
    } catch (e) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Program mutations
  // ---------------------------------------------------------------------------

  /// Create a new program
  Future<bool> createProgram(Program program) async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;
    final gen = ++_createGen;
    final errorGen = ++_errorGen;

    bool owns() => _sessionEpoch.isCurrent(token) && gen == _createGen;

    _isCreating = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final newProgram = await _programsRepository.createProgram(program);
      if (!owns()) return false;

      // Converge by stable server id, honouring the currently-published
      // filter: a row a racing refresh already published for this id is
      // replaced in place (never duplicated), and a created Program that does
      // not match the filter is not inserted.
      _reconcileByFilter(newProgram.id, newProgram);
      _recomputeDerivedLists();
      // A stale in-flight loadPrograms must not overwrite this create.
      _listGen++;

      debugPrint('✅ Created program: ${newProgram.title}');
      return true;
    } on SessionStaleException {
      return false;
    } on RequestCancelledException {
      return false;
    } catch (e) {
      if (owns() && errorGen == _errorGen) {
        _errorMessage =
            'Failed to create program: ${e.toString().replaceAll('Exception: ', '')}';
      }
      debugPrint('Create program error: $e');
      return false;
    } finally {
      if (owns()) {
        _isCreating = false;
        notifyListeners();
      }
    }
  }

  /// Update an existing program
  Future<bool> updateProgram(int id, Program program) async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;
    final gen = _bumpProgramMutationGen(id);
    final errorGen = ++_errorGen;

    bool owns() =>
        _sessionEpoch.isCurrent(token) && _programMutationGens[id] == gen;

    _beginUpdateTracking(id);
    _errorMessage = null;
    notifyListeners();

    try {
      await _programsRepository.updateProgram(id, program);
      if (!owns()) return false;

      // Converge by stable id, honouring the currently-published filter (an
      // update that flips `isActive` out of the filtered view drops the row
      // rather than leaving an inconsistent one). Preserve workouts / goal the
      // caller did not resend, exactly as the pre-PR code did. Only a row
      // actually present is reconciled - a successful server update for a
      // Program not in the (possibly filtered) published list is a no-op here,
      // matching the pre-PR behaviour.
      final index = _programs.indexWhere((p) => p.id == id);
      if (index != -1) {
        final existingProgram = _programs[index];
        final workoutsToKeep =
            (program.workouts == null || program.workouts!.isEmpty)
                ? existingProgram.workouts
                : program.workouts;
        final goalToKeep = program.goal ?? existingProgram.goal;
        final merged = program.copyWith(
          workouts: workoutsToKeep,
          goal: goalToKeep,
        );
        _reconcileByFilter(id, merged);
        _recomputeDerivedLists();
      }
      _listGen++;

      debugPrint('✅ Updated program: ${program.title}');
      return true;
    } on SessionStaleException {
      return false;
    } on RequestCancelledException {
      return false;
    } catch (e) {
      if (owns() && errorGen == _errorGen) {
        _errorMessage =
            'Failed to update program: ${e.toString().replaceAll('Exception: ', '')}';
        debugPrint('Update program error: $e');
      }
      return false;
    } finally {
      // Single notify point for this axis: the owned success and owned error
      // paths both fall through to here; a superseded (`!owns()`) or
      // lifecycle-aborted path releases its `isUpdating` slot but publishes
      // nothing.
      _endUpdateTracking(id);
      if (owns()) notifyListeners();
    }
  }

  /// Get deletion impact for a program (how many sessions will be deleted)
  Future<Map<String, int>> getDeletionImpact(int id) async {
    final token = _sessionEpoch.capture();
    if (token == null) throw const SessionStaleException();
    final gen = ++_impactGen;

    try {
      final impact = await _programsRepository.getDeletionImpact(id);
      if (!(_sessionEpoch.isCurrent(token) && gen == _impactGen)) {
        throw const SessionStaleException();
      }
      return impact;
    } on SessionStaleException {
      rethrow;
    } on RequestCancelledException {
      rethrow;
    } catch (e) {
      debugPrint('Get deletion impact error: $e');
      rethrow;
    }
  }

  /// Delete a program
  Future<bool> deleteProgram(int id) async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;
    final gen = _bumpProgramMutationGen(id);
    final errorGen = ++_errorGen;

    bool owns() =>
        _sessionEpoch.isCurrent(token) && _programMutationGens[id] == gen;

    try {
      await _programsRepository.deleteProgram(id);
      if (!owns()) return false;

      _programs.removeWhere((p) => p.id == id);
      _recomputeDerivedLists();
      // In-flight child-workout mutations for this program can no longer apply.
      _invalidateChildGensFor(id);
      _listGen++;

      debugPrint('✅ Deleted program $id');
      notifyListeners();
      return true;
    } on SessionStaleException {
      return false;
    } on RequestCancelledException {
      return false;
    } catch (e) {
      if (owns() && errorGen == _errorGen) {
        _errorMessage =
            'Failed to delete program: ${e.toString().replaceAll('Exception: ', '')}';
        debugPrint('Delete program error: $e');
        notifyListeners();
      }
      return false;
    }
  }

  /// Mark a program as completed
  Future<bool> completeProgram(int id) async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;
    final gen = _bumpProgramMutationGen(id);
    final errorGen = ++_errorGen;

    bool owns() =>
        _sessionEpoch.isCurrent(token) && _programMutationGens[id] == gen;

    try {
      await _programsRepository.completeProgram(id);
      if (!owns()) return false;

      final index = _programs.indexWhere((p) => p.id == id);
      if (index != -1) {
        // A completed Program is inactive, so under an `isActive: true`
        // published filter this drops the row rather than leaving it.
        final completed = _programs[index].copyWith(
          isCompleted: true,
          completedAt: DateTime.now().toUtc(),
          isActive: false,
        );
        _reconcileByFilter(id, completed);
        _recomputeDerivedLists();
      }
      _listGen++;

      debugPrint('✅ Completed program $id');
      notifyListeners();
      return true;
    } on SessionStaleException {
      return false;
    } on RequestCancelledException {
      return false;
    } catch (e) {
      if (owns() && errorGen == _errorGen) {
        _errorMessage =
            'Failed to complete program: ${e.toString().replaceAll('Exception: ', '')}';
        debugPrint('Complete program error: $e');
        notifyListeners();
      }
      return false;
    }
  }

  /// Recalibrate a program's start date to Monday of its week
  /// Fixes calendar alignment issues for programs created on non-Monday days
  Future<bool> recalibrateProgram(int id) async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;
    final gen = _bumpProgramMutationGen(id);
    final errorGen = ++_errorGen;

    bool owns() =>
        _sessionEpoch.isCurrent(token) && _programMutationGens[id] == gen;

    try {
      final result = await _programsRepository.recalibrateProgram(id);
      if (!owns()) return false;
      debugPrint('✅ Recalibrated program: $result');

      // Reload to pick up the updated start date. Forward the NEWEST requested
      // filter, read fresh here (not captured at entry): a manual
      // `loadPrograms(isActive: ...)` that started while this recalibration's
      // HTTP was pending has already recorded its intent in
      // [_latestRequestedIsActiveFilter], and this follow-up must honour that
      // newer intent rather than revert the view to the filter that was
      // published when recalibration began. `loadPrograms` is itself fully
      // session/generation-guarded and bumps `_listGen`, so it is the list
      // write for this operation and the last `_listGen` claimant wins.
      await loadPrograms(isActive: _latestRequestedIsActiveFilter);
      return true;
    } on SessionStaleException {
      return false;
    } on RequestCancelledException {
      return false;
    } catch (e) {
      if (owns() && errorGen == _errorGen) {
        _errorMessage =
            'Failed to recalibrate program: ${e.toString().replaceAll('Exception: ', '')}';
        debugPrint('Recalibrate program error: $e');
        notifyListeners();
      }
      return false;
    }
  }

  /// Advance to next workout (increment day/week)
  Future<bool> advanceProgram(int id) async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;
    final gen = _bumpProgramMutationGen(id);
    final errorGen = ++_errorGen;

    bool owns() =>
        _sessionEpoch.isCurrent(token) && _programMutationGens[id] == gen;

    try {
      final updatedProgram = await _programsRepository.advanceProgram(id);
      if (!owns()) return false;

      // Owned canonical replacement by stable id, honouring the
      // currently-published filter (an advance that completes the Program
      // makes it inactive and drops it from an `isActive: true` view).
      final index = _programs.indexWhere((p) => p.id == id);
      if (index != -1) {
        _reconcileByFilter(id, updatedProgram);
        _recomputeDerivedLists();
      }
      _listGen++;

      debugPrint(
        '✅ Advanced program to week ${updatedProgram.currentWeek}, day ${updatedProgram.currentDay}',
      );
      notifyListeners();
      return true;
    } on SessionStaleException {
      return false;
    } on RequestCancelledException {
      return false;
    } catch (e) {
      if (owns() && errorGen == _errorGen) {
        _errorMessage =
            'Failed to advance program: ${e.toString().replaceAll('Exception: ', '')}';
        debugPrint('Advance program error: $e');
        notifyListeners();
      }
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Direct-return workout reads
  // ---------------------------------------------------------------------------

  /// Get workouts for a specific week. Returned directly to the caller.
  Future<List<ProgramWorkout>> getWeekWorkouts(
    int programId,
    int weekNumber,
  ) async {
    final token = _sessionEpoch.capture();
    if (token == null) return [];
    final gen = ++_weekGen;
    final errorGen = ++_errorGen;

    bool owns() => _sessionEpoch.isCurrent(token) && gen == _weekGen;

    try {
      final workouts = await _programsRepository.getWeekWorkouts(
        programId,
        weekNumber,
      );
      return _sessionEpoch.isCurrent(token) ? workouts : <ProgramWorkout>[];
    } on SessionStaleException {
      return [];
    } on RequestCancelledException {
      return [];
    } catch (e) {
      if (!owns() || errorGen != _errorGen) return [];
      _errorMessage =
          'Failed to load workouts: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Load workouts error: $e');
      notifyListeners();
      return [];
    }
  }

  /// Get today's workout. Returned directly to the caller; a 404 here is
  /// normal (rest day / nothing scheduled) so failures stay silent.
  Future<ProgramWorkout?> getTodaysWorkout(int programId) async {
    final token = _sessionEpoch.capture();
    if (token == null) return null;
    final gen = ++_todayGen;

    bool owns() => _sessionEpoch.isCurrent(token) && gen == _todayGen;

    try {
      final workout = await _programsRepository.getTodaysWorkout(programId);
      return owns() ? workout : null;
    } on SessionStaleException {
      return null;
    } on RequestCancelledException {
      return null;
    } catch (e) {
      debugPrint('No workout found for today: $e');
      return null;
    }
  }

  /// Get workouts for the current week of a program
  List<ProgramWorkout> getThisWeeksWorkouts(Program program) {
    if (program.workouts == null || program.workouts!.isEmpty) {
      return [];
    }

    final currentWeek = program.currentWeek;
    return program.workouts!.where((w) => w.weekNumber == currentWeek).toList()
      ..sort((a, b) => a.dayNumber.compareTo(b.dayNumber));
  }

  // ---------------------------------------------------------------------------
  // Nested-workout mutations
  // ---------------------------------------------------------------------------

  /// Add a workout to a program
  Future<bool> addWorkout(int programId, ProgramWorkout workout) async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;
    final gen = _bumpWorkoutAddGen(programId);
    final errorGen = ++_errorGen;

    bool owns() =>
        _sessionEpoch.isCurrent(token) && _workoutAddGens[programId] == gen;

    try {
      final newWorkout = await _programsRepository.addWorkout(
        programId,
        workout,
      );
      if (!owns()) return false;

      final index = _programs.indexWhere((p) => p.id == programId);
      if (index != -1) {
        final updatedWorkouts = List<ProgramWorkout>.from(
          _programs[index].workouts ?? [],
        )..removeWhere((w) => w.id == newWorkout.id);
        updatedWorkouts.add(newWorkout);
        _programs[index] = _programs[index].copyWith(workouts: updatedWorkouts);
        _recomputeDerivedLists();
      }
      _listGen++;

      debugPrint('✅ Added workout to program $programId');
      notifyListeners();
      return true;
    } on SessionStaleException {
      return false;
    } on RequestCancelledException {
      return false;
    } catch (e) {
      if (owns() && errorGen == _errorGen) {
        _errorMessage =
            'Failed to add workout: ${e.toString().replaceAll('Exception: ', '')}';
        debugPrint('Add workout error: $e');
        notifyListeners();
      }
      return false;
    }
  }

  /// Update a program workout
  Future<bool> updateWorkout(int workoutId, ProgramWorkout workout) async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;
    // Unlike completeWorkout/deleteWorkout/swapWorkouts (which only receive a
    // bare workoutId and must scan `_programs` for the parent), updateWorkout
    // is handed the full `ProgramWorkout`, whose `programId` is the
    // authoritative server parent. Use it directly: a scan cannot
    // disambiguate two workouts that share an id under different programs,
    // whereas `workout.programId` always can.
    final programId = workout.programId;
    final key = (programId, workoutId);
    final gen = _bumpWorkoutMutationGen(key);
    final errorGen = ++_errorGen;

    bool owns() =>
        _sessionEpoch.isCurrent(token) && _workoutMutationGens[key] == gen;

    try {
      await _programsRepository.updateWorkout(workoutId, workout);
      if (!owns()) return false;

      // Locate by parent program id AND child id - never by child id alone.
      final pIndex = _programs.indexWhere((p) => p.id == programId);
      if (pIndex != -1 && _programs[pIndex].workouts != null) {
        final workouts = List<ProgramWorkout>.from(_programs[pIndex].workouts!);
        final wIndex = workouts.indexWhere((w) => w.id == workoutId);
        if (wIndex != -1) {
          workouts[wIndex] = workout;
          _programs[pIndex] = _programs[pIndex].copyWith(workouts: workouts);
          _recomputeDerivedLists();
        }
      }
      _listGen++;

      debugPrint(
        '✅ Updated workout $workoutId in program $programId (day ${workout.dayNumber})',
      );
      notifyListeners();
      return true;
    } on SessionStaleException {
      return false;
    } on RequestCancelledException {
      return false;
    } catch (e) {
      if (owns() && errorGen == _errorGen) {
        _errorMessage =
            'Failed to update workout: ${e.toString().replaceAll('Exception: ', '')}';
        debugPrint('Update workout error: $e');
        notifyListeners();
      }
      return false;
    }
  }

  /// Swap two program workouts atomically
  Future<bool> swapWorkouts(int workout1Id, int workout2Id) async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;

    // Resolve the parent program that holds BOTH workouts, by stable id.
    int? programId;
    for (final p in _programs) {
      final ws = p.workouts;
      if (ws == null) continue;
      if (ws.any((w) => w.id == workout1Id) &&
          ws.any((w) => w.id == workout2Id)) {
        programId = p.id;
        break;
      }
    }

    final key1 = (programId ?? -1, workout1Id);
    final key2 = (programId ?? -1, workout2Id);
    final gen1 = _bumpWorkoutMutationGen(key1);
    final gen2 = _bumpWorkoutMutationGen(key2);
    final errorGen = ++_errorGen;

    bool owns() =>
        _sessionEpoch.isCurrent(token) &&
        _workoutMutationGens[key1] == gen1 &&
        _workoutMutationGens[key2] == gen2;

    try {
      await _programsRepository.swapWorkouts(workout1Id, workout2Id);
      if (!owns()) return false;

      if (programId != null) {
        final pIndex = _programs.indexWhere((p) => p.id == programId);
        if (pIndex != -1 && _programs[pIndex].workouts != null) {
          final workouts = List<ProgramWorkout>.from(
            _programs[pIndex].workouts!,
          );
          final i1 = workouts.indexWhere((w) => w.id == workout1Id);
          final i2 = workouts.indexWhere((w) => w.id == workout2Id);
          if (i1 != -1 && i2 != -1) {
            final w1 = workouts[i1];
            final w2 = workouts[i2];
            workouts[i1] = w1.copyWith(
              dayNumber: w2.dayNumber,
              orderIndex: w2.orderIndex,
            );
            workouts[i2] = w2.copyWith(
              dayNumber: w1.dayNumber,
              orderIndex: w1.orderIndex,
            );
            _programs[pIndex] = _programs[pIndex].copyWith(workouts: workouts);
            _recomputeDerivedLists();
          }
        }
      }
      _listGen++;

      debugPrint('✅ Swapped workouts $workout1Id and $workout2Id');
      notifyListeners();
      return true;
    } on SessionStaleException {
      return false;
    } on RequestCancelledException {
      return false;
    } catch (e) {
      if (owns() && errorGen == _errorGen) {
        _errorMessage =
            'Failed to swap workouts: ${e.toString().replaceAll('Exception: ', '')}';
        debugPrint('Swap workouts error: $e');
        notifyListeners();
      }
      return false;
    }
  }

  /// Mark a workout as completed
  Future<bool> completeWorkout(int workoutId, {String? notes}) async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;
    final programId = _parentProgramIdForWorkout(workoutId);
    final key = (programId ?? -1, workoutId);
    final gen = _bumpWorkoutMutationGen(key);
    final errorGen = ++_errorGen;

    bool owns() =>
        _sessionEpoch.isCurrent(token) && _workoutMutationGens[key] == gen;

    try {
      await _programsRepository.completeWorkout(workoutId, notes: notes);
      if (!owns()) return false;

      if (programId != null) {
        final pIndex = _programs.indexWhere((p) => p.id == programId);
        if (pIndex != -1 && _programs[pIndex].workouts != null) {
          final workouts = List<ProgramWorkout>.from(
            _programs[pIndex].workouts!,
          );
          final wIndex = workouts.indexWhere((w) => w.id == workoutId);
          if (wIndex != -1) {
            workouts[wIndex] = workouts[wIndex].copyWith(
              isCompleted: true,
              completedAt: DateTime.now().toUtc(),
            );
            _programs[pIndex] = _programs[pIndex].copyWith(workouts: workouts);
            _recomputeDerivedLists();
          }
        }
      }
      _listGen++;

      debugPrint('✅ Completed workout $workoutId');
      notifyListeners();
      return true;
    } on SessionStaleException {
      return false;
    } on RequestCancelledException {
      return false;
    } catch (e) {
      if (owns() && errorGen == _errorGen) {
        _errorMessage =
            'Failed to complete workout: ${e.toString().replaceAll('Exception: ', '')}';
        debugPrint('Complete workout error: $e');
        notifyListeners();
      }
      return false;
    }
  }

  /// Delete a workout
  Future<bool> deleteWorkout(int workoutId) async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;
    final programId = _parentProgramIdForWorkout(workoutId);
    final key = (programId ?? -1, workoutId);
    final gen = _bumpWorkoutMutationGen(key);
    final errorGen = ++_errorGen;

    bool owns() =>
        _sessionEpoch.isCurrent(token) && _workoutMutationGens[key] == gen;

    try {
      await _programsRepository.deleteWorkout(workoutId);
      if (!owns()) return false;

      if (programId != null) {
        final pIndex = _programs.indexWhere((p) => p.id == programId);
        if (pIndex != -1 && _programs[pIndex].workouts != null) {
          final workouts = List<ProgramWorkout>.from(
            _programs[pIndex].workouts!,
          )..removeWhere((w) => w.id == workoutId);
          _programs[pIndex] = _programs[pIndex].copyWith(workouts: workouts);
          _recomputeDerivedLists();
        }
      }
      _listGen++;

      debugPrint('✅ Deleted workout $workoutId');
      notifyListeners();
      return true;
    } on SessionStaleException {
      return false;
    } on RequestCancelledException {
      return false;
    } catch (e) {
      if (owns() && errorGen == _errorGen) {
        _errorMessage =
            'Failed to delete workout: ${e.toString().replaceAll('Exception: ', '')}';
        debugPrint('Delete workout error: $e');
        notifyListeners();
      }
      return false;
    }
  }

  /// Get all program workouts scheduled for today from active programs
  /// Returns a list of (Program, ProgramWorkout) tuples
  List<({Program program, ProgramWorkout workout})> getTodaysWorkouts() {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final result = <({Program program, ProgramWorkout workout})>[];

    for (final program in _activePrograms) {
      if (program.workouts == null || program.workouts!.isEmpty) continue;

      for (final workout in program.workouts!) {
        // Use stored scheduledDate if available, otherwise fall back to calculation
        DateTime workoutDate;
        if (workout.scheduledDate != null) {
          workoutDate = DateTime(
            workout.scheduledDate!.year,
            workout.scheduledDate!.month,
            workout.scheduledDate!.day,
          );
        } else {
          // Fallback for old data without scheduledDate
          final localStartDate = program.startDate.toLocal();
          final startDate = DateTime(
            localStartDate.year,
            localStartDate.month,
            localStartDate.day,
          );
          workoutDate = startDate.add(
            Duration(
              days: (workout.weekNumber - 1) * 7 + (workout.dayNumber - 1),
            ),
          );
        }

        if (workoutDate == todayDate && !workout.isRestDay) {
          result.add((program: program, workout: workout));
        }
      }
    }

    return result;
  }

  /// Clear all programs data (called on logout via [SessionCleanupCoordinator]).
  ///
  /// Every generation is bumped BEFORE any state is reset, so a load or
  /// mutation continuation that resolves after this returns fails its
  /// ownership check and can neither repopulate the cleared lists nor
  /// resurrect a previous user's error - even when `clear()` is called on its
  /// own, without a preceding `UserSessionEpoch.invalidate()`.
  ///
  /// The three lists are emptied in place (not reassigned), so any reference a
  /// caller obtained before this call also becomes empty.
  void clear() {
    _invalidateGenerations();

    _programs.clear();
    _activePrograms.clear();
    _completedPrograms.clear();
    _publishedIsActiveFilter = null;
    _latestRequestedIsActiveFilter = null;
    _isLoading = false;
    _isCreating = false;
    _activeUpdateCounts.clear();
    _errorMessage = null;
    _newlyCreatedProgramId = null;
    notifyListeners();
    debugPrint('🧹 ProgramsProvider cleared');
  }

  @override
  void dispose() {
    _invalidateGenerations();
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}
