import 'package:flutter/foundation.dart';
import '../../core/constants/api_config.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/session_request_coordinator.dart';
import '../../core/services/user_session_epoch.dart';
import '../models/body_metric.dart';
import '../services/api_service.dart';
import '../services/session_request_context.dart';
import '../services/session_request_exceptions.dart';

/// Repository for body metrics operations.
///
/// ## Session binding
///
/// Every operation below captures exactly one [SessionRequestContext] via
/// [_sessionCoordinator] at operation entry - before any other `await` - and
/// passes that SAME context to its [ApiService] call, so the request carries
/// the JWT pinned at capture time (never the live secure-storage token) and
/// the generation-scoped `CancelToken` that a logout aborts. Live credentials
/// are never reread after an operation starts - this repository does not
/// depend on `AuthService` at all.
///
/// A `null` capture (logged out, or the session changed while the JWT read
/// was in flight) is treated per-method, matching each method's own
/// pre-existing "nothing to return" convention:
///
/// - [getBodyMetrics] / [getChartData] - list-returning GETs that already
///   had an established "no data available" result (`[]` when offline); a
///   null capture is folded into that same convention.
/// - [getLatestMetric] - already returned `null` on any ordinary failure
///   (its pre-existing catch-all); a null capture is folded into that.
/// - [getBodyMetricById] / [createBodyMetric] / [updateBodyMetric] /
///   [deleteBodyMetric] - operate on one required record with no safe empty
///   result, so a null capture is itself a stale state ->
///   [SessionStaleException], matching `ExerciseRepository`'s convention for
///   single-record mutations.
///
/// This repository has no local (Isar) cache, no detached/background work,
/// and no nested/recovery/follow-up HTTP - a single bound call per method is
/// the entire surface.
///
/// [SessionStaleException] and [RequestCancelledException] are expected
/// lifecycle outcomes of a session ending mid-flight, not failures. Methods
/// that already had a `catch` block ([getBodyMetrics], [getLatestMetric],
/// [getChartData]) rethrow both unchanged, before any generic
/// logging/fallback - never logged as an ordinary failure, never converted
/// into a successful empty result, never routed through `onUnauthorized`.
/// The remaining methods ([getBodyMetricById], [createBodyMetric],
/// [updateBodyMetric], [deleteBodyMetric]) had no `catch` block before this
/// change and still have none - both exception types already propagate to
/// the caller untouched, so there is nothing to convert.
/// `BodyMetricsProvider`'s own session/generation guards discard both
/// without publishing.
class BodyMetricsRepository {
  final ApiService _apiService;

  /// Shared app-wide session-identity instance - the SAME object handed to
  /// `AuthProvider`, `AnalyticsRepository`, `DirectMessagesRepository`, etc.
  /// (see main.dart). Only `AuthProvider` calls activate()/invalidate(); this
  /// repository only ever reads it indirectly, through the context
  /// [_sessionCoordinator] derives from it - it holds no Isar state and does
  /// no post-`await` local write, so every staleness decision is made by
  /// [ApiService] against [SessionRequestContext.epochToken] (matches
  /// `DirectMessagesRepository`'s identical unused-field rationale).
  // ignore: unused_field
  final UserSessionEpoch _sessionEpoch;

  /// Shared app-wide coordinator that captures a [SessionRequestContext]
  /// (pinned JWT + generation-scoped CancelToken) for every session-bound
  /// HTTP call. The SAME instance handed to every other session-bound
  /// repository; never constructed privately.
  final SessionRequestCoordinator _sessionCoordinator;

  final ConnectivityService? _connectivity;

  BodyMetricsRepository(
    this._apiService,
    this._sessionEpoch,
    this._sessionCoordinator, [
    this._connectivity,
  ]);

  /// Captures the session context for one operation, or `null` if there is
  /// no authenticated session to act for.
  Future<SessionRequestContext?> _capture() =>
      _sessionCoordinator.captureContext();

  /// Get body metrics for the current user.
  /// Optional parameter: days (default 90 days).
  Future<List<BodyMetric>> getBodyMetrics({int days = 90}) async {
    final context = await _capture();
    if (context == null) {
      debugPrint(
        '⚠️ Body metrics: no active session - skipping getBodyMetrics',
      );
      return [];
    }

    final isOnline = _connectivity?.isOnline ?? true;
    if (!isOnline) {
      debugPrint(
        '📴 Offline - body metrics feature requires online connection',
      );
      return [];
    }

    try {
      final data = await _apiService.get<List<dynamic>>(
        ApiConfig.bodyMetrics,
        queryParameters: {'days': days.toString()},
        sessionContext: context,
      );

      return data
          .map((json) => BodyMetric.fromJson(json as Map<String, dynamic>))
          .toList();
    } on SessionStaleException {
      rethrow;
    } on RequestCancelledException {
      rethrow;
    } catch (e) {
      debugPrint('⚠️ Failed to fetch body metrics: $e');
      rethrow;
    }
  }

  /// Get the latest body metric entry.
  Future<BodyMetric?> getLatestMetric() async {
    final context = await _capture();
    if (context == null) {
      debugPrint(
        '⚠️ Body metrics: no active session - skipping getLatestMetric',
      );
      return null;
    }

    try {
      final data = await _apiService.get<Map<String, dynamic>>(
        ApiConfig.bodyMetricsLatest,
        sessionContext: context,
      );
      return BodyMetric.fromJson(data);
    } on SessionStaleException {
      rethrow;
    } on RequestCancelledException {
      rethrow;
    } catch (e) {
      debugPrint('⚠️ Failed to fetch latest metric: $e');
      return null;
    }
  }

  /// Get a specific body metric by ID.
  Future<BodyMetric> getBodyMetricById(int id) async {
    final context = await _capture();
    if (context == null) throw const SessionStaleException();

    final data = await _apiService.get<Map<String, dynamic>>(
      ApiConfig.bodyMetricById(id),
      sessionContext: context,
    );
    return BodyMetric.fromJson(data);
  }

  /// Add a new body metric entry.
  Future<BodyMetric> createBodyMetric(BodyMetric metric) async {
    final context = await _capture();
    if (context == null) throw const SessionStaleException();

    final data = await _apiService.post<Map<String, dynamic>>(
      ApiConfig.bodyMetrics,
      data: metric.toJson(),
      sessionContext: context,
    );
    return BodyMetric.fromJson(data);
  }

  /// Update an existing body metric entry.
  Future<void> updateBodyMetric(int id, BodyMetric metric) async {
    final context = await _capture();
    if (context == null) throw const SessionStaleException();

    await _apiService.put<void>(
      ApiConfig.bodyMetricById(id),
      data: metric.toJson(),
      sessionContext: context,
    );
  }

  /// Delete a body metric entry.
  Future<void> deleteBodyMetric(int id) async {
    final context = await _capture();
    if (context == null) throw const SessionStaleException();

    await _apiService.delete(
      ApiConfig.bodyMetricById(id),
      sessionContext: context,
    );
  }

  /// Get chart data for a specific metric.
  /// metric: weight, bodyfat, chest, waist, hip, arm, thigh, calf
  /// days: number of days to fetch (default 90)
  Future<List<Map<String, dynamic>>> getChartData({
    String metric = 'weight',
    int days = 90,
  }) async {
    final context = await _capture();
    if (context == null) {
      debugPrint('⚠️ Body metrics: no active session - skipping getChartData');
      return [];
    }

    try {
      final data = await _apiService.get<List<dynamic>>(
        ApiConfig.bodyMetricsChart,
        queryParameters: {'metric': metric, 'days': days.toString()},
        sessionContext: context,
      );

      return data.map((json) => json as Map<String, dynamic>).toList();
    } on SessionStaleException {
      rethrow;
    } on RequestCancelledException {
      rethrow;
    } catch (e) {
      debugPrint('⚠️ Failed to fetch chart data: $e');
      rethrow;
    }
  }
}
