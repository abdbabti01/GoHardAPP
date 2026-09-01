import 'dart:async';
import 'package:flutter/material.dart';
import '../core/services/user_session_epoch.dart';
import '../data/models/body_metric.dart';
import '../data/repositories/body_metrics_repository.dart';
import '../data/services/session_request_exceptions.dart';
import '../core/services/connectivity_service.dart';

/// Provider for body metrics management.
///
/// ## Session ownership
///
/// App-scoped provider: a single instance created with `previous ??`
/// outlives logout/login (see main.dart), so a continuation started under
/// user A must never publish into the state user B now sees through this
/// same instance. Every async method captures `_sessionEpoch.capture()`
/// before its first `await` and rechecks ownership after every `await` - in
/// the success path, `catch`, and `finally` - before it touches `_metrics`,
/// `_latestMetric`, a mutating flag, the error, or calls `notifyListeners()`.
/// A `null` capture (logged out) returns immediately using each method's
/// existing return convention without starting work.
///
/// [SessionStaleException] / [RequestCancelledException] raised by the
/// repository are expected lifecycle outcomes, not failures: every method
/// intercepts both before its generic `catch`, so a session ending mid-flight
/// is dropped silently rather than surfaced as a user-visible error.
///
/// ## Same-session ordering
///
/// Session identity alone cannot order two requests within one session, so
/// each independently-refreshable resource carries a monotonically
/// increasing generation:
///
/// - [_listGen] - the metrics list. Bumped by [loadBodyMetrics] AND by
///   [createBodyMetric]/[updateBodyMetric]/[deleteBodyMetric]'s successful
///   writes, so a slower in-flight list load can never resurrect a metric a
///   newer mutation removed, and a stale list load can never overwrite a
///   newer mutation's list edit.
/// - [_latestGen] - the derived "latest" metric fetched directly via
///   [loadLatestMetric]. Bumped the same way as [_listGen] for the same
///   reason; [loadBodyMetrics]'s own derivation of `_latestMetric` from the
///   list it just fetched is gated by [_listGen] instead (it is computed
///   synchronously from that same call's result, with no separate await).
/// - [_detailGen] - owns only [getBodyMetricById]'s ordering against ANOTHER
///   detail request (same axis). The method has no `_selectedMetric` /
///   detail field to publish into (its successful result is returned
///   directly to whichever caller awaited it, exactly as it always was) -
///   see the method's own doc comment for why an "A -> B -> A" generation
///   over a stored field is not applicable here, proven from the absence of
///   such a field in this class. Its shared `_errorMessage` write is
///   additionally gated by [_errorGen] (see "Shared error ownership").
/// - [_chartGen] - the [getChartData] analogue of [_detailGen]: orders one
///   chart request against another chart request; the returned chart data
///   itself is handed directly to its caller (typically a `FutureBuilder`),
///   never published into a stored field; its `_errorMessage` write is
///   gated by [_errorGen] too.
/// - [_createGen] - owns [createBodyMetric]'s `_isCreating` flag. Creates
///   have no per-item identity (a new metric has no id yet), so they form a
///   monotonic supersede-chain: the newest create owns the flag, and an
///   older concurrent create's optimistic insert is deliberately dropped
///   (its server row still reappears on the next [loadBodyMetrics]) -
///   mirrors `MessagesProvider._sendGens`' documented trade-off. This is
///   distinct from updates below, which are genuinely independent per id.
/// - [_metricMutationGens] - keyed by metric id, shared by
///   [updateBodyMetric] AND [deleteBodyMetric] on that SAME id: a stale
///   update/delete to a metric writes nothing (not its list edit, not its
///   error), while a mutation to a DIFFERENT metric is never superseded by
///   it. Because both operations share one counter per id, a slow update
///   whose delete of the SAME metric already completed can never resurrect
///   it - the delete's completion bumps the exact counter the update's
///   `owns()` check reads.
///
/// ## Active-update tracking ([isUpdating])
///
/// [isUpdating] is derived from [_activeUpdates], a set of the exact
/// `(id, gen)` identity of every in-flight [updateBodyMetric] operation, NOT
/// a single boolean. Each update adds its identity before its first `await`
/// and removes exactly that identity in its `finally`:
///
/// - update A (id 1) finishing while update B (id 2) is still in flight
///   removes only `(1, genA)`, so [isUpdating] stays `true` for B;
/// - an older update to id 1 finishing after its replacement removes only
///   its own `(1, genOld)` - the replacement's `(1, genNew)` is untouched;
/// - a stale user-A update whose identity [clear] already dropped finds
///   nothing to remove, so it cannot disturb user-B's active-update set;
/// - [clear]/[dispose] empty [_activeUpdates] (via [_invalidateGenerations])
///   before resetting visible state.
///
/// The `finally` grants two separate permissions. Publishing an update's
/// MUTATION results (list edit, cleared spinner/error) requires full
/// ownership (`owns()` - session current AND still the current op for this
/// id). Announcing that removing THIS operation's own record just flipped
/// [isUpdating] `true -> false` requires only that the exact record was
/// present and removed, the removal emptied [_activeUpdates], and the
/// captured session is still current. So a superseded update - its metric
/// generation bumped by a newer update, OR by a delete of the same id that
/// completed first - still emits the [isUpdating] transition even though it
/// publishes no results: the op that superseded it notified BEFORE this
/// record was removed and therefore could not have published this
/// transition itself.
///
/// [deleteBodyMetric] deliberately does NOT participate in [_activeUpdates]:
/// it never had a loading flag (the pre-PR code had none either), and
/// [isUpdating] has always meant "a PUT update is in progress". Deletes are
/// ordered solely by [_metricMutationGens] for their list edit.
///
/// [_isCreating] stays a plain boolean owned by the monotonic [_createGen]
/// (see above) - creates supersede rather than run independently, so there
/// is no independent-concurrent axis to track the way there is for updates
/// of different ids.
///
/// ## Shared error ownership
///
/// `_errorMessage` is one shared field written by six axes (list, detail,
/// chart, create, update, delete). Each carries its own axis generation for
/// list-edit ordering, but that does not order an error write on axis X
/// against a newer op on axis Y. [_errorGen] is a single global
/// error-publication generation, bumped by every error-capable method at
/// entry (and by [clearError] and [_invalidateGenerations]): an error write
/// only lands if the writing op is still the newest error-slot claimant
/// (`errorGen == _errorGen`) AND passes its own axis `owns()`. So an older
/// chart request that fails after a newer list request has already
/// published its error can no longer clobber it. This gates only the shared
/// `_errorMessage` write - the underlying requests still run fully
/// concurrently; nothing is serialized.
///
/// [clear] and [dispose] bump every generation (list, latest, detail, chart,
/// create, error, and every per-metric mutation entry) and empty
/// [_activeUpdates] BEFORE resetting state, so an in-flight continuation can
/// neither repopulate cleared state nor resurrect a previous session's
/// metric - even when [clear] is called without a preceding
/// `UserSessionEpoch.invalidate()`.
///
/// ## List identity
///
/// [_metrics] is a single `final` list, only ever mutated in place - never
/// reassigned - so a caller that already holds a reference to it (via the
/// [metrics] getter) also observes a [clear] or reload as that same list
/// emptying/repopulating, not a stale snapshot frozen at whatever it
/// contained when the reference was taken.
///
/// ## Connectivity ownership
///
/// The connectivity-restored callback captures a fresh token on every
/// invocation and no-ops entirely if there is no active session, so a
/// connectivity flap while logged out can never dispatch a refresh for
/// nobody, and a refresh a since-invalidated session's callback started can
/// never commit (the same pattern as `SharedWorkoutProvider`). The refresh
/// it triggers is [loadBodyMetrics] itself, so it is bound by the exact same
/// [_listGen] ordering as a manual refresh - an older connectivity-triggered
/// load can never overwrite a newer manual one, or vice versa.
class BodyMetricsProvider extends ChangeNotifier {
  final BodyMetricsRepository _bodyMetricsRepository;
  final UserSessionEpoch _sessionEpoch;
  final ConnectivityService? _connectivity;

  final List<BodyMetric> _metrics = [];
  BodyMetric? _latestMetric;
  bool _isLoading = false;
  bool _isCreating = false;
  String? _errorMessage;

  StreamSubscription<bool>? _connectivitySubscription;

  // Monotonic per-resource generations - see the class doc comment.
  int _listGen = 0;
  int _latestGen = 0;
  int _detailGen = 0;
  int _chartGen = 0;
  int _createGen = 0;

  // Global error-publication generation - see "Shared error ownership".
  int _errorGen = 0;

  // Per-metric mutation generations, keyed by metric id and shared by
  // updateBodyMetric/deleteBodyMetric - see the class doc comment.
  final Map<int, int> _metricMutationGens = {};

  // Exact identities of every in-flight updateBodyMetric operation. See the
  // "Active-update tracking" section of the class doc comment.
  final Set<({int id, int gen})> _activeUpdates = {};

  /// Test-only seam: invoked with the `Future` returned by the
  /// connectivity-restored listener's own call to [loadBodyMetrics], so a
  /// test can await the real ownership path to completion deterministically
  /// instead of pumping the event loop. Null in production; setting it never
  /// changes control flow or performance.
  @visibleForTesting
  void Function(Future<void> refresh)? onConnectivityRefreshForTesting;

  BodyMetricsProvider(
    this._bodyMetricsRepository,
    this._sessionEpoch, [
    this._connectivity,
  ]) {
    // Listen for connectivity changes and refresh when going online. This
    // callback can fire at any point in the app's lifetime, including during
    // a logged-out gap between one user's logout and the next user's login -
    // capture a token fresh on every invocation and skip entirely if there
    // is no active session (see the class doc comment's "Connectivity
    // ownership" section).
    _connectivitySubscription = _connectivity?.connectivityStream.listen((
      isOnline,
    ) {
      final token = _sessionEpoch.capture();
      if (token == null) return;
      if (isOnline && _metrics.isEmpty) {
        debugPrint('📡 Connection restored - loading body metrics');
        final refresh = loadBodyMetrics();
        onConnectivityRefreshForTesting?.call(refresh);
      }
    });
  }

  // Getters
  List<BodyMetric> get metrics => _metrics;
  BodyMetric? get latestMetric => _latestMetric;
  bool get isLoading => _isLoading;
  bool get isCreating => _isCreating;

  /// `true` while at least one [updateBodyMetric] operation is still in
  /// flight and still owns its slot. Derived from [_activeUpdates] so a
  /// finished update to one metric never reports "no update" while an
  /// update to a different metric is still running.
  bool get isUpdating => _activeUpdates.isNotEmpty;

  String? get errorMessage => _errorMessage;

  /// Load body metrics for the current user.
  Future<void> loadBodyMetrics({int days = 90}) async {
    final token = _sessionEpoch.capture();
    if (token == null) return;
    final gen = ++_listGen;
    final errorGen = ++_errorGen;

    bool owns() => _sessionEpoch.isCurrent(token) && gen == _listGen;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _bodyMetricsRepository.getBodyMetrics(days: days);
      if (!owns()) return;

      _metrics
        ..clear()
        ..addAll(result);
      if (_metrics.isNotEmpty) {
        _metrics.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
        _latestMetric = _metrics.first;
      }

      debugPrint('✅ Loaded ${_metrics.length} body metrics');
    } on SessionStaleException {
      return;
    } on RequestCancelledException {
      return;
    } catch (e) {
      if (!owns() || errorGen != _errorGen) return;
      _errorMessage =
          'Failed to load body metrics: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Load body metrics error: $e');
    } finally {
      if (owns()) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Load the latest body metric entry.
  Future<void> loadLatestMetric() async {
    final token = _sessionEpoch.capture();
    if (token == null) return;
    final gen = ++_latestGen;

    bool owns() => _sessionEpoch.isCurrent(token) && gen == _latestGen;

    try {
      final metric = await _bodyMetricsRepository.getLatestMetric();
      if (!owns()) return;
      _latestMetric = metric;
      notifyListeners();
      debugPrint('✅ Loaded latest metric');
    } on SessionStaleException {
      return;
    } on RequestCancelledException {
      return;
    } catch (e) {
      // This method never publishes into `_errorMessage`; an ordinary
      // failure is logged only, exactly as before.
      debugPrint('Load latest metric error: $e');
    }
  }

  /// Get a specific body metric by ID. Not published into shared Provider
  /// state - the result is returned directly to whichever caller awaits this
  /// call, exactly as the pre-existing contract did; there is no stored
  /// "selected"/detail field for a stale result to overwrite. The only
  /// cross-session/cross-axis risk is the shared `_errorMessage` write on
  /// failure, gated by [_detailGen] (against another detail request) and
  /// [_errorGen] (against a newer op on any axis).
  Future<BodyMetric?> getBodyMetricById(int id) async {
    final token = _sessionEpoch.capture();
    if (token == null) return null;
    final gen = ++_detailGen;
    final errorGen = ++_errorGen;

    bool owns() => _sessionEpoch.isCurrent(token) && gen == _detailGen;

    try {
      final metric = await _bodyMetricsRepository.getBodyMetricById(id);
      // A result computed for A's session must never reach a caller now
      // resolving under B, even though it is never published into shared
      // state.
      return _sessionEpoch.isCurrent(token) ? metric : null;
    } on SessionStaleException {
      return null;
    } on RequestCancelledException {
      return null;
    } catch (e) {
      if (!owns() || errorGen != _errorGen) return null;
      _errorMessage =
          'Failed to load metric: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Load metric error: $e');
      notifyListeners();
      return null;
    }
  }

  /// Create a new body metric entry.
  Future<bool> createBodyMetric(BodyMetric metric) async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;
    final gen = ++_createGen;
    final errorGen = ++_errorGen;

    bool owns() => _sessionEpoch.isCurrent(token) && gen == _createGen;

    _isCreating = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final newMetric = await _bodyMetricsRepository.createBodyMetric(metric);
      if (!owns()) return false;

      _metrics.insert(0, newMetric); // Add to beginning (most recent)
      _latestMetric = newMetric;
      // A stale in-flight list/latest refresh must not overwrite what this
      // create just wrote.
      _listGen++;
      _latestGen++;

      debugPrint('✅ Created body metric entry');
      return true;
    } on SessionStaleException {
      return false;
    } on RequestCancelledException {
      return false;
    } catch (e) {
      if (!owns() || errorGen != _errorGen) return false;
      _errorMessage =
          'Failed to create body metric: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Create body metric error: $e');
      return false;
    } finally {
      if (owns()) {
        _isCreating = false;
        notifyListeners();
      }
    }
  }

  /// Update an existing body metric entry.
  Future<bool> updateBodyMetric(int id, BodyMetric metric) async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;
    final gen = (_metricMutationGens[id] ?? 0) + 1;
    _metricMutationGens[id] = gen;
    final errorGen = ++_errorGen;

    // This exact (id, gen) pair identifies THIS update operation. It is
    // registered before the first await and removed by this operation's own
    // `finally`: removing `op` can never touch a newer replacement (which
    // registered a different (id, gen)); an update to a different metric
    // registers a disjoint identity; and a stale op whose identity `clear()`
    // already dropped simply finds nothing to remove.
    final op = (id: id, gen: gen);
    _activeUpdates.add(op);

    bool owns() =>
        _sessionEpoch.isCurrent(token) && _metricMutationGens[id] == gen;

    _errorMessage = null;
    notifyListeners();

    try {
      await _bodyMetricsRepository.updateBodyMetric(id, metric);
      if (!owns()) return false;

      // Update local list
      final index = _metrics.indexWhere((m) => m.id == id);
      if (index != -1) {
        _metrics[index] = metric;

        // Update latest if this was the latest
        if (_latestMetric?.id == id) {
          _latestMetric = metric;
        }
      }
      _listGen++;
      _latestGen++;

      debugPrint('✅ Updated body metric: $id');
      return true;
    } on SessionStaleException {
      return false;
    } on RequestCancelledException {
      return false;
    } catch (e) {
      if (!owns() || errorGen != _errorGen) return false;
      _errorMessage =
          'Failed to update body metric: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Update body metric error: $e');
      return false;
    } finally {
      // Two distinct permissions on the way out:
      //
      //  - Publishing this update's MUTATION RESULTS (its list edit, its
      //    cleared spinner/error) requires full ownership - session current
      //    AND still the current op for this metric id (`owns()`).
      //  - Announcing that removing THIS operation's own active-update
      //    record just changed the externally visible `isUpdating` value
      //    only requires: the exact record was present and removed, the
      //    captured session is still current, and the removal actually
      //    emptied `_activeUpdates`. A superseded update (its metric
      //    generation bumped by a newer update OR by a delete of the same
      //    id) has no results to publish but MUST still emit this
      //    transition so a `select`-on-`isUpdating` consumer rebuilds -
      //    the delete/newer-update that superseded it notified BEFORE this
      //    record was removed, so it cannot have published this
      //    true -> false transition.
      final wasUpdating = _activeUpdates.isNotEmpty;
      final removed = _activeUpdates.remove(op);
      final stoppedUpdating = wasUpdating && _activeUpdates.isEmpty;

      if (owns()) {
        notifyListeners();
      } else if (removed && stoppedUpdating && _sessionEpoch.isCurrent(token)) {
        notifyListeners();
      }
    }
  }

  /// Delete a body metric entry.
  Future<bool> deleteBodyMetric(int id) async {
    final token = _sessionEpoch.capture();
    if (token == null) return false;
    final gen = (_metricMutationGens[id] ?? 0) + 1;
    _metricMutationGens[id] = gen;
    final errorGen = ++_errorGen;

    bool owns() =>
        _sessionEpoch.isCurrent(token) && _metricMutationGens[id] == gen;

    _errorMessage = null;
    notifyListeners();

    try {
      await _bodyMetricsRepository.deleteBodyMetric(id);
      if (!owns()) return false;

      _metrics.removeWhere((m) => m.id == id);

      // Update latest if needed
      if (_latestMetric?.id == id) {
        _latestMetric = _metrics.isNotEmpty ? _metrics.first : null;
      }
      _listGen++;
      _latestGen++;

      debugPrint('✅ Deleted body metric: $id');
      notifyListeners();
      return true;
    } on SessionStaleException {
      return false;
    } on RequestCancelledException {
      return false;
    } catch (e) {
      if (!owns() || errorGen != _errorGen) return false;
      _errorMessage =
          'Failed to delete body metric: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Delete body metric error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Get chart data for a specific metric. Not published into shared
  /// Provider state - see [getBodyMetricById]'s doc comment for the same
  /// reasoning; [_chartGen] orders it against another chart request and
  /// [_errorGen] gates its shared `_errorMessage` write on failure against a
  /// newer op on any axis.
  Future<List<Map<String, dynamic>>> getChartData({
    String metric = 'weight',
    int days = 90,
  }) async {
    final token = _sessionEpoch.capture();
    if (token == null) return [];
    final gen = ++_chartGen;
    final errorGen = ++_errorGen;

    bool owns() => _sessionEpoch.isCurrent(token) && gen == _chartGen;

    try {
      final data = await _bodyMetricsRepository.getChartData(
        metric: metric,
        days: days,
      );
      return _sessionEpoch.isCurrent(token) ? data : [];
    } on SessionStaleException {
      return [];
    } on RequestCancelledException {
      return [];
    } catch (e) {
      if (!owns() || errorGen != _errorGen) return [];
      _errorMessage =
          'Failed to load chart data: ${e.toString().replaceAll('Exception: ', '')}';
      debugPrint('Load chart data error: $e');
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

  /// Invalidate every request/mutation generation and empty active-update
  /// tracking so no in-flight continuation can publish after this returns.
  void _invalidateGenerations() {
    _listGen++;
    _latestGen++;
    _detailGen++;
    _chartGen++;
    _createGen++;
    _errorGen++;
    _metricMutationGens.updateAll((_, value) => value + 1);
    _activeUpdates.clear();
  }

  /// Clear all body metrics data (called on logout via
  /// [SessionCleanupCoordinator]).
  ///
  /// Every generation is bumped and [_activeUpdates] is emptied BEFORE any
  /// state is reset, so a load or mutation continuation that resolves after
  /// this returns fails its ownership check and can neither repopulate the
  /// cleared fields, resurrect a previous user's error, nor leave
  /// [isUpdating] stuck `true` - even when `clear()` is called on its own,
  /// without a preceding `UserSessionEpoch.invalidate()`.
  ///
  /// [_metrics] is emptied in place (not reassigned), so any reference a
  /// caller obtained before this call also becomes empty.
  void clear() {
    _invalidateGenerations();

    _metrics.clear();
    _latestMetric = null;
    _errorMessage = null;
    _isLoading = false;
    _isCreating = false;
    notifyListeners();
    debugPrint('🧹 BodyMetricsProvider cleared');
  }

  @override
  void dispose() {
    _invalidateGenerations();
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}
