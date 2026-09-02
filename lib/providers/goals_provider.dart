import 'dart:async';
import 'package:flutter/material.dart';
import '../core/services/user_session_epoch.dart';
import '../data/models/goal.dart';
import '../data/models/goal_progress.dart';
import '../data/repositories/goals_repository.dart';
import '../data/services/session_request_exceptions.dart';
import '../core/services/connectivity_service.dart';

/// Provider for goals management.
///
/// ## Session ownership
///
/// App-scoped provider: a single instance created with `previous ??`
/// outlives logout/login (see main.dart), so a continuation started under
/// user A must never publish into the state user B now sees through this
/// same instance. Every async method captures `_sessionEpoch.capture()`
/// before its first `await` and rechecks ownership after every `await` - in
/// the success path, `catch`, and `finally` - before it touches `_goals`,
/// `_isLoading`, `_errorMessage`, optimistic bookkeeping, or calls
/// `notifyListeners()`. A `null` capture (logged out) returns immediately
/// using each method's existing return convention without starting work.
///
/// [SessionStaleException] / [RequestCancelledException] raised by the
/// repository are expected lifecycle outcomes, not failures: every method
/// intercepts both before its generic `catch`, so a session ending mid-flight
/// is dropped silently rather than surfaced as a user-visible error.
///
/// ## Same-session ordering and resource identity
///
/// Session identity alone cannot order two requests within one session, so
/// each independently-refreshable resource carries a monotonically
/// increasing generation:
///
/// - [_listGen] - the goals list. Bumped by [loadGoals] AND by every
///   successful [createGoal]/[updateGoal]/[deleteGoal]/[completeGoal] write,
///   so a slower in-flight list load can never resurrect a goal a newer
///   mutation removed, nor overwrite a newer mutation's list edit.
///   [addProgress] refreshes the list by awaiting [loadGoals] itself, so it
///   inherits that same ordering. Bumping [_listGen] only blocks a *future*
///   publication, so each optimistic mutation's owned-success continuation
///   ALSO re-converges the list to its authoritative intended state by
///   stable id (create: upsert the server row, removing its own temp row and
///   any pre-existing server-id row; update/complete: upsert the intended
///   goal; delete: ensure the id is absent). This repairs a
///   `loadGoals()` that both started and completed while the mutation's HTTP
///   call was still pending and had already republished the pre-mutation
///   server list. The reapplication is idempotent, requires full [owns()]
///   (so a superseded/stale ack reapplies nothing and Goal A's ack never
///   touches Goal B), and on the happy path rewrites the identical value the
///   optimistic step applied.
/// - [_detailGen] - orders one [getGoalById] against another [getGoalById]
///   (same axis). The result is returned directly to the caller, never
///   stored, so there is no "A -> B -> A" stored field to protect; the
///   returned value is additionally gated by a final `isCurrent` check so a
///   result computed for A never reaches a caller now resolving under B.
/// - [_historyGen] - the [getProgressHistory] analogue of [_detailGen].
/// - [_impactGen] - orders one [getDeletionImpact] against another; its
///   result is returned directly and gated by a final `isCurrent`/generation
///   check (a stale session or a superseded request throws
///   [SessionStaleException] rather than handing back stale numbers).
/// - [_createGen] - a monotonic supersede-chain for [createGoal]. Creates
///   have no server id yet, so the newest create owns the axis; an older
///   concurrent create only ever removes its OWN uniquely-keyed optimistic
///   placeholder (see [_nextTempId]), never the newer one's.
/// - [_goalMutationGens] - keyed by goal id, SHARED by [updateGoal],
///   [deleteGoal], [completeGoal] AND [addProgress] on that SAME id: a stale
///   mutation to a goal writes nothing (not its list edit, not its error,
///   not its rollback), while a mutation to a DIFFERENT goal is never
///   superseded by it. Because all four operations share one counter per id,
///   a slow update whose delete of the SAME goal already completed can never
///   resurrect it, and an older update can never undo a newer completion -
///   the delete/complete bumps the exact counter the update's `owns()` check
///   reads.
///
/// ## Shared error ownership
///
/// `_errorMessage` is one shared field written by seven axes (list, detail,
/// history, create, update, delete, complete, add-progress). Each carries
/// its own axis generation for list-edit ordering, but that does not order
/// an error write on axis X against a newer op on axis Y. [_errorGen] is a
/// single global error-publication generation, bumped by every error-capable
/// method at entry (and by [clearError] and [_invalidateGenerations]): an
/// error write only lands if the writing op is still the newest error-slot
/// claimant (`errorGen == _errorGen`) AND passes its own axis `owns()`. So
/// an older detail request that fails after a newer list request has already
/// published its error can no longer clobber it. This gates only the shared
/// `_errorMessage` write - the underlying requests still run fully
/// concurrently; nothing is serialized.
///
/// [getDeletionImpact] deliberately does NOT participate in [_errorGen]: it
/// never wrote `_errorMessage` (it rethrows to its caller), so it has no
/// shared-error write to gate.
///
/// ## No mutation activity flag
///
/// This provider exposes no per-mutation spinner. `_isLoading` is owned
/// solely by [loadGoals] (bumped/read via [_listGen]); the optimistic
/// mutations update `_goals` immediately and expose their progress only
/// through that list edit, exactly as the pre-PR code did. The deprecated
/// `isCreating`/`isUpdating` getters remain plain aliases of [isLoading] for
/// backwards compatibility - there is no independent active-operation set to
/// track because there is no such state axis.
///
/// ## List identity
///
/// [_goals] is a single `final` list, only ever mutated in place - never
/// reassigned - so a caller that already holds a reference to it (via the
/// [goals] getter, or [activeGoals]/[completedGoals] which read it) also
/// observes a [clear] or reload as that same list emptying/repopulating.
///
/// ## List filter identity
///
/// [loadGoals] takes an optional `isActive` filter and issues a filtered
/// repository request, so the published [_goals] represents a specific
/// filtered view. [_publishedIsActiveFilter] records which one (`null` =
/// unfiltered / nothing published). Every optimistic write, convergence
/// upsert and rollback reinsert on [createGoal]/[updateGoal]/[completeGoal]
/// (and the [deleteGoal] rollback) goes through [_reconcileByFilter] /
/// [_belongsInPublishedList], which upserts a Goal only while it belongs in
/// that filtered view and otherwise removes its row. So a just-completed
/// (hence inactive) Goal never lingers in an `isActive: true` list, a
/// created/updated Goal that does not match the filter is not inserted, and
/// a rollback after a refresh changed the filter does not reintroduce a
/// now-non-matching Goal. Deletion (and its convergence `removeWhere`) is
/// filter-agnostic - removing an id is always valid.
///
/// ## Cleanup and connectivity ownership
///
/// [clear] and [dispose] bump every generation (list, detail, history,
/// impact, create, error, and every per-goal mutation entry) BEFORE
/// resetting state, so an in-flight continuation can neither repopulate
/// cleared state nor resurrect a previous session's goal - even when [clear]
/// is called without a preceding `UserSessionEpoch.invalidate()`.
///
/// The connectivity-restored callback captures a fresh token on every
/// invocation and no-ops entirely if there is no active session, so a
/// connectivity flap while logged out can never dispatch a refresh for
/// nobody. The refresh it triggers is [loadGoals] itself, so it is bound by
/// the exact same [_listGen] ordering as a manual refresh.
class GoalsProvider extends ChangeNotifier {
  final GoalsRepository _goalsRepository;
  final UserSessionEpoch _sessionEpoch;
  final ConnectivityService? _connectivity;

  final List<Goal> _goals = [];
  bool _isLoading = false;
  String? _errorMessage;

  StreamSubscription<bool>? _connectivitySubscription;

  // Monotonic per-resource generations - see the class doc comment.
  int _listGen = 0;
  int _detailGen = 0;
  int _historyGen = 0;
  int _impactGen = 0;
  int _createGen = 0;

  // Global error-publication generation - see "Shared error ownership".
  int _errorGen = 0;

  // Per-goal mutation generations, keyed by goal id and shared by
  // updateGoal/deleteGoal/completeGoal/addProgress - see the class doc comment.
  final Map<int, int> _goalMutationGens = {};

  // Distinct negative placeholder id for each optimistic [createGoal], so an
  // older concurrent create can identify and remove exactly its own row
  // rather than any create's row (the pre-PR code shared a single `-1`).
  int _nextTempId = -1;

  // The `isActive` filter identity of the list currently published in
  // [_goals]: `null` means "unfiltered" (or nothing published yet), `true` /
  // `false` mean the last owned [loadGoals] used that `isActive` argument.
  // Set only by [loadGoals] on owned success and reset by [clear]. Every
  // optimistic write, convergence upsert and rollback reinsert consults it
  // via [_belongsInPublishedList] so a mutation can never leave a Goal in
  // [_goals] that does not belong in the currently-published filtered view
  // (e.g. a just-completed - hence inactive - Goal must not remain in an
  // `isActive: true` list).
  bool? _publishedIsActiveFilter;

  /// Test-only seam: invoked with the `Future` returned by the
  /// connectivity-restored listener's own call to [loadGoals], so a test can
  /// await the real ownership path to completion deterministically instead of
  /// pumping the event loop. Null in production; setting it never changes
  /// control flow or performance.
  @visibleForTesting
  void Function(Future<void> refresh)? onConnectivityRefreshForTesting;

  GoalsProvider(
    this._goalsRepository,
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
      if (isOnline && _goals.isEmpty) {
        debugPrint('📡 Connection restored - loading goals');
        final refresh = loadGoals();
        onConnectivityRefreshForTesting?.call(refresh);
      }
    });
  }

  // Getters - derive filtered lists from single source of truth
  List<Goal> get goals => _goals;
  List<Goal> get activeGoals =>
      _goals.where((g) => g.isActive && !g.isCompleted).toList();
  List<Goal> get completedGoals => _goals.where((g) => g.isCompleted).toList();
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  // Legacy getters for backwards compatibility (deprecated)
  @Deprecated('Use isLoading instead')
  bool get isCreating => _isLoading;
  @Deprecated('Use isLoading instead')
  bool get isUpdating => _isLoading;

  /// Whether [g] belongs in the list currently published in [_goals] given
  /// the [_publishedIsActiveFilter] identity. A `null` filter (unfiltered, or
  /// nothing loaded yet) admits every Goal.
  bool _belongsInPublishedList(Goal g) {
    final filter = _publishedIsActiveFilter;
    return filter == null || g.isActive == filter;
  }

  /// Reconciles [goal] into [_goals] by stable id, honouring the current
  /// filter identity: upsert it in place if it [_belongsInPublishedList],
  /// otherwise remove any row that carries its id. Idempotent; used by every
  /// optimistic write, convergence upsert and rollback reinsert on
  /// update/complete so the published list stays internally consistent with
  /// the filter that produced it. Returns `true` iff [_goals] actually
  /// changed, so a caller with no other state to publish can skip a
  /// redundant `notifyListeners()`.
  bool _reconcileByFilter(int id, Goal goal) {
    final i = _goals.indexWhere((g) => g.id == id);
    if (_belongsInPublishedList(goal)) {
      if (i != -1) {
        if (identical(_goals[i], goal)) return false;
        _goals[i] = goal;
      } else {
        _goals.add(goal);
      }
      return true;
    }
    if (i == -1) return false;
    _goals.removeAt(i);
    return true;
  }

  /// Load all goals for the current user
  Future<void> loadGoals({bool? isActive}) async {
    final token = _sessionEpoch.capture();
    if (token == null) return;
    final gen = ++_listGen;
    final errorGen = ++_errorGen;

    bool owns() => _sessionEpoch.isCurrent(token) && gen == _listGen;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _goalsRepository.getGoals(isActive: isActive);
      if (!owns()) return;

      _goals
        ..clear()
        ..addAll(result);
      // Remember which filter this published list represents, so a later
      // mutation ack / rollback reconciles against the right identity.
      _publishedIsActiveFilter = isActive;

      debugPrint(
        '✅ Loaded ${_goals.length} goals (${activeGoals.length} active, ${completedGoals.length} completed)',
      );
    } on SessionStaleException {
      return;
    } on RequestCancelledException {
      return;
    } catch (e) {
      if (!owns() || errorGen != _errorGen) return;
      _errorMessage =
          'Failed to load goals: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Load goals error: $e');
    } finally {
      if (owns()) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Get a specific goal by ID with progress history. Not published into
  /// shared Provider state - the result is returned directly to whichever
  /// caller awaits this call, exactly as the pre-existing contract did.
  Future<Goal?> getGoalById(int id) async {
    final token = _sessionEpoch.capture();
    if (token == null) return null;
    final gen = ++_detailGen;
    final errorGen = ++_errorGen;

    bool owns() => _sessionEpoch.isCurrent(token) && gen == _detailGen;

    try {
      final goal = await _goalsRepository.getGoalById(id);
      // A result computed for A's session must never reach a caller now
      // resolving under B, even though it is never published into shared
      // state.
      return _sessionEpoch.isCurrent(token) ? goal : null;
    } on SessionStaleException {
      return null;
    } on RequestCancelledException {
      return null;
    } catch (e) {
      if (!owns() || errorGen != _errorGen) return null;
      _errorMessage =
          'Failed to load goal: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Load goal error: $e');
      notifyListeners();
      return null;
    }
  }

  /// Create a new goal with optimistic update
  Future<Goal?> createGoal(Goal goal) async {
    final token = _sessionEpoch.capture();
    if (token == null) return null;
    final gen = ++_createGen;
    final errorGen = ++_errorGen;
    final tempId = _nextTempId--;

    bool owns() => _sessionEpoch.isCurrent(token) && gen == _createGen;

    _errorMessage = null;

    // 1. Add optimistic goal with a unique temporary id (optimistic update),
    //    but only if it belongs in the currently-published filtered list.
    final optimisticGoal = goal.copyWith(id: tempId, createdAt: DateTime.now());
    if (_belongsInPublishedList(optimisticGoal)) {
      _goals.add(optimisticGoal);
    }
    notifyListeners();

    debugPrint('📝 Optimistically added goal: ${optimisticGoal.goalType}');

    try {
      // 2. Make API call
      final newGoal = await _goalsRepository.createGoal(goal);

      if (!owns()) {
        // Superseded by a newer create, or the session ended. Drop only our
        // OWN optimistic placeholder (unique tempId); never publish the
        // server row into a newer operation's or another user's list.
        _discardOptimisticCreate(tempId, owns: false);
        return null;
      }

      // 3. Converge to the authoritative server row. A `loadGoals()` that
      // both started AND completed while this create's POST was in flight
      // will have wiped our optimistic placeholder (and cannot yet contain
      // the server row, since the server had not processed the create).
      // Remove our own placeholder if it survived, plus any row already
      // carrying the returned server id (a racing refresh, or a retry), then
      // insert the server row exactly once - idempotent upsert by stable
      // server id, never a duplicate. `newGoal.id` is a positive server id
      // and `tempId` is a unique negative, so this can never match another
      // in-flight create's placeholder. Only insert the server row if it
      // belongs in the currently-published filtered list.
      _goals.removeWhere((g) => g.id == tempId || g.id == newGoal.id);
      if (_belongsInPublishedList(newGoal)) {
        _goals.add(newGoal);
      }
      // A stale in-flight list refresh must not overwrite what this create
      // just wrote.
      _listGen++;

      debugPrint('✅ Created goal: ${newGoal.goalType} (ID: ${newGoal.id})');
      notifyListeners();
      return newGoal;
    } on SessionStaleException {
      _discardOptimisticCreate(tempId, owns: owns());
      return null;
    } on RequestCancelledException {
      _discardOptimisticCreate(tempId, owns: owns());
      return null;
    } catch (e) {
      // Roll back our own optimistic insert (unique tempId). Publish the
      // rollback/error only while this create still owns its axis - after
      // clear()/dispose() bumps _createGen, owns() is false and nothing is
      // notified (matches BodyMetricsProvider).
      final published = owns();
      _goals.removeWhere((g) => g.id == tempId);
      if (published && errorGen == _errorGen) {
        _errorMessage =
            'Failed to create goal: ${e.toString().replaceAll('Exception: ', '')}';
      }
      debugPrint('Create goal error: $e');
      if (published) notifyListeners();
      return null;
    }
  }

  /// Removes this create's own optimistic placeholder. [owns] gates the
  /// `notifyListeners()`: once `clear()`/`dispose()` has bumped `_createGen`
  /// (or a newer create superseded this one, or the session ended) the row is
  /// still cleaned up but nothing is published - a newer create's own
  /// completion, or the next `loadGoals()`, reconciles the list.
  void _discardOptimisticCreate(int tempId, {required bool owns}) {
    final removed = _goals.indexWhere((g) => g.id == tempId) != -1;
    _goals.removeWhere((g) => g.id == tempId);
    if (removed && owns) notifyListeners();
  }

  /// Update an existing goal with optimistic update
  Future<bool> updateGoal(int id, Goal goal) async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;
    final gen = (_goalMutationGens[id] ?? 0) + 1;
    _goalMutationGens[id] = gen;
    final errorGen = ++_errorGen;

    bool owns() =>
        _sessionEpoch.isCurrent(token) && _goalMutationGens[id] == gen;

    _errorMessage = null;

    // 1. Store original goal for rollback, located by stable identity.
    final originalIndex = _goals.indexWhere((g) => g.id == id);
    if (originalIndex == -1) {
      _errorMessage = 'Goal not found';
      notifyListeners();
      return false;
    }
    final originalGoal = _goals[originalIndex];

    // 2. Apply optimistic update by stable id, honouring the current filter
    //    (an update that flips `isActive` out of the published filter drops
    //    the row rather than leaving an inconsistent one).
    _reconcileByFilter(id, goal);
    notifyListeners();

    debugPrint('📝 Optimistically updated goal: $id');

    try {
      // 3. Make API call
      await _goalsRepository.updateGoal(id, goal);
      if (!owns()) return false;

      // Converge: a `loadGoals()` that started AND completed while this PUT
      // was in flight will have restored the pre-update server row (or
      // dropped it). Reapply the intended updated goal by stable id, honouring
      // the currently-published filter - idempotent, never duplicates. On the
      // happy path this rewrites the identical value the optimistic step
      // already applied.
      _reconcileByFilter(id, goal);
      _listGen++;
      debugPrint('✅ Updated goal: $id');
      notifyListeners();
      return true;
    } on SessionStaleException {
      _rollbackGoal(id, originalGoal, token, gen);
      return false;
    } on RequestCancelledException {
      _rollbackGoal(id, originalGoal, token, gen);
      return false;
    } catch (e) {
      if (owns()) {
        // Rollback by stable identity, honouring the current filter (a
        // refresh may have changed it while the PUT was pending).
        _reconcileByFilter(id, originalGoal);
        if (errorGen == _errorGen) {
          _errorMessage =
              'Failed to update goal: ${e.toString().replaceAll('Exception: ', '')}';
        }
        debugPrint('Update goal error: $e');
        notifyListeners();
      }
      return false;
    }
  }

  /// Restores [goal] by stable identity (honouring the currently-published
  /// filter) only if this operation still owns the per-goal mutation slot
  /// (session current AND still the newest mutation for this id). A newer
  /// update/delete/complete on the same id makes this a no-op, so a stale
  /// rollback can never resurrect a deleted goal, undo a newer completion, or
  /// touch another user's list.
  void _rollbackGoal(int id, Goal goal, UserSessionToken token, int gen) {
    if (!(_sessionEpoch.isCurrent(token) && _goalMutationGens[id] == gen)) {
      return;
    }
    if (_reconcileByFilter(id, goal)) notifyListeners();
  }

  /// Get deletion impact for a goal (how many programs and sessions will be
  /// deleted). Returned directly to the caller, never stored; a stale session
  /// or a superseded request throws [SessionStaleException] rather than
  /// handing back another request's numbers.
  Future<Map<String, int>> getDeletionImpact(int id) async {
    final token = _sessionEpoch.capture();
    if (token == null) throw const SessionStaleException();
    final gen = ++_impactGen;

    try {
      final impact = await _goalsRepository.getDeletionImpact(id);
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

  /// Delete a goal with optimistic update
  Future<bool> deleteGoal(int id) async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;
    final gen = (_goalMutationGens[id] ?? 0) + 1;
    _goalMutationGens[id] = gen;
    final errorGen = ++_errorGen;

    bool owns() =>
        _sessionEpoch.isCurrent(token) && _goalMutationGens[id] == gen;

    _errorMessage = null;

    // 1. Store original goal for rollback
    final originalIndex = _goals.indexWhere((g) => g.id == id);
    if (originalIndex == -1) {
      return true; // Already deleted
    }
    final originalGoal = _goals[originalIndex];

    // 2. Optimistically remove
    _goals.removeAt(originalIndex);
    notifyListeners();

    debugPrint('📝 Optimistically deleted goal: $id');

    try {
      // 3. Make API call
      await _goalsRepository.deleteGoal(id);
      if (!owns()) return false;

      // Converge: a `loadGoals()` that started AND completed while this
      // DELETE was in flight will have resurrected the optimistically-removed
      // row. Ensure the id is absent - idempotent (no-op if already gone).
      _goals.removeWhere((g) => g.id == id);
      _listGen++;
      debugPrint('✅ Deleted goal: $id');
      notifyListeners();
      return true;
    } on SessionStaleException {
      _reinsertGoal(id, originalGoal, originalIndex, token, gen);
      return false;
    } on RequestCancelledException {
      _reinsertGoal(id, originalGoal, originalIndex, token, gen);
      return false;
    } catch (e) {
      if (owns()) {
        _reinsertGoalUnchecked(id, originalGoal, originalIndex);
        if (errorGen == _errorGen) {
          _errorMessage =
              'Failed to delete goal: ${e.toString().replaceAll('Exception: ', '')}';
        }
        debugPrint('Delete goal error: $e');
        notifyListeners();
      }
      return false;
    }
  }

  void _reinsertGoal(
    int id,
    Goal goal,
    int originalIndex,
    UserSessionToken token,
    int gen,
  ) {
    if (!(_sessionEpoch.isCurrent(token) && _goalMutationGens[id] == gen)) {
      return;
    }
    _reinsertGoalUnchecked(id, goal, originalIndex);
    notifyListeners();
  }

  void _reinsertGoalUnchecked(int id, Goal goal, int originalIndex) {
    if (_goals.any((g) => g.id == id)) return;
    // A refresh may have changed the published filter while the DELETE was
    // pending; do not reinsert a Goal that no longer belongs in it.
    if (!_belongsInPublishedList(goal)) return;
    if (originalIndex >= 0 && originalIndex <= _goals.length) {
      _goals.insert(originalIndex, goal);
    } else {
      _goals.add(goal);
    }
  }

  /// Mark a goal as completed with optimistic update
  Future<bool> completeGoal(int id) async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;
    final gen = (_goalMutationGens[id] ?? 0) + 1;
    _goalMutationGens[id] = gen;
    final errorGen = ++_errorGen;

    bool owns() =>
        _sessionEpoch.isCurrent(token) && _goalMutationGens[id] == gen;

    _errorMessage = null;

    // 1. Store original for rollback, located by stable identity.
    final originalIndex = _goals.indexWhere((g) => g.id == id);
    if (originalIndex == -1) {
      _errorMessage = 'Goal not found';
      notifyListeners();
      return false;
    }
    final originalGoal = _goals[originalIndex];

    // 2. Optimistically mark as completed. The completed Goal is inactive, so
    //    under an `isActive: true` published filter this drops the row.
    final completedGoal = originalGoal.copyWith(
      isCompleted: true,
      isActive: false,
      completedAt: DateTime.now(),
    );
    _reconcileByFilter(id, completedGoal);
    notifyListeners();

    debugPrint('📝 Optimistically completed goal: $id');

    try {
      // 3. Make API call
      await _goalsRepository.completeGoal(id);
      if (!owns()) return false;

      // Converge: a `loadGoals()` that started AND completed while this PUT
      // /complete was in flight will have restored the incomplete server
      // row. Reapply the exact intended completed goal by stable id, honouring
      // the currently-published filter - idempotent, never duplicates. A
      // concurrent addProgress on this same id shares `_goalMutationGens[id]`,
      // so it would already have superseded this via `owns()`.
      _reconcileByFilter(id, completedGoal);
      _listGen++;
      debugPrint('✅ Completed goal: $id');
      notifyListeners();
      return true;
    } on SessionStaleException {
      _rollbackGoal(id, originalGoal, token, gen);
      return false;
    } on RequestCancelledException {
      _rollbackGoal(id, originalGoal, token, gen);
      return false;
    } catch (e) {
      if (owns()) {
        _reconcileByFilter(id, originalGoal);
        if (errorGen == _errorGen) {
          _errorMessage =
              'Failed to complete goal: ${e.toString().replaceAll('Exception: ', '')}';
        }
        debugPrint('Complete goal error: $e');
        notifyListeners();
      }
      return false;
    }
  }

  /// Add progress entry for a goal
  Future<bool> addProgress(int goalId, GoalProgress progress) async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;
    final gen = (_goalMutationGens[goalId] ?? 0) + 1;
    _goalMutationGens[goalId] = gen;
    final errorGen = ++_errorGen;

    bool owns() =>
        _sessionEpoch.isCurrent(token) && _goalMutationGens[goalId] == gen;

    _errorMessage = null;
    notifyListeners();

    try {
      await _goalsRepository.addProgress(goalId, progress);
      if (!owns()) return false;

      // Reload to get the updated goal with new progress. loadGoals() is
      // itself fully session/generation-guarded and bumps _listGen, so this
      // is the list write for this operation.
      await loadGoals();

      debugPrint('✅ Added progress to goal: $goalId');
      return true;
    } on SessionStaleException {
      return false;
    } on RequestCancelledException {
      return false;
    } catch (e) {
      if (!owns() || errorGen != _errorGen) return false;
      _errorMessage =
          'Failed to add progress: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Add progress error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Get progress history for a goal. Returned directly to the caller, never
  /// stored; a result computed for A never reaches a caller now under B.
  Future<List<GoalProgress>> getProgressHistory(int goalId) async {
    final token = _sessionEpoch.capture();
    if (token == null) return [];
    final gen = ++_historyGen;
    final errorGen = ++_errorGen;

    bool owns() => _sessionEpoch.isCurrent(token) && gen == _historyGen;

    try {
      final history = await _goalsRepository.getProgressHistory(goalId);
      return _sessionEpoch.isCurrent(token) ? history : <GoalProgress>[];
    } on SessionStaleException {
      return [];
    } on RequestCancelledException {
      return [];
    } catch (e) {
      if (!owns() || errorGen != _errorGen) return [];
      _errorMessage =
          'Failed to load progress history: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Load progress history error: $e');
      notifyListeners();
      return [];
    }
  }

  /// Clear error message
  void clearError() {
    // Claim the error slot so an older in-flight op cannot re-populate the
    // error the user just dismissed.
    _errorGen++;
    _errorMessage = null;
    notifyListeners();
  }

  /// Invalidate every request/mutation generation so no in-flight
  /// continuation can publish after this returns.
  void _invalidateGenerations() {
    _listGen++;
    _detailGen++;
    _historyGen++;
    _impactGen++;
    _createGen++;
    _errorGen++;
    _goalMutationGens.updateAll((_, value) => value + 1);
  }

  /// Clear all goals data (called on logout via [SessionCleanupCoordinator]).
  ///
  /// Every generation is bumped BEFORE any state is reset, so a load or
  /// mutation continuation that resolves after this returns fails its
  /// ownership check and can neither repopulate the cleared list nor
  /// resurrect a previous user's error - even when `clear()` is called on its
  /// own, without a preceding `UserSessionEpoch.invalidate()`.
  ///
  /// [_goals] is emptied in place (not reassigned), so any reference a caller
  /// obtained before this call also becomes empty.
  void clear() {
    _invalidateGenerations();

    _goals.clear();
    _publishedIsActiveFilter = null;
    _errorMessage = null;
    _isLoading = false;
    notifyListeners();
    debugPrint('🧹 GoalsProvider cleared');
  }

  @override
  void dispose() {
    _invalidateGenerations();
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}
