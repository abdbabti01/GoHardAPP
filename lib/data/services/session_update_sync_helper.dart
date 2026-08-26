import 'dart:convert';

import 'package:isar/isar.dart';

import '../../core/constants/api_config.dart';
import '../local/models/local_session.dart';
import '../local/services/model_mapper.dart';
import '../models/session.dart';
import 'api_exception.dart';
import 'api_service.dart';

/// Result of pushing a full-session update to the server.
enum SessionSyncOutcome {
  /// The server accepted the update and returned the authoritative session;
  /// it has been persisted locally and the row is marked synced.
  synced,

  /// The server rejected the update with a well-formed 409 conflict. The
  /// conflict snapshot has been stored locally for later manual
  /// resolution; the pending local edit was left untouched.
  conflict,

  /// The server returned a 409 but its payload could not be parsed as the
  /// documented conflict contract. The pending local edit was preserved
  /// untouched and a sync error was recorded.
  conflictDataInvalid,

  /// The update could not be confirmed (an empty/204 success body and the
  /// follow-up recovery GET failed). The pending local edit was preserved
  /// untouched for a later retry.
  deferred,
}

/// Centralizes the full-session PUT update contract so the call sites that
/// push a session update (periodic background sync, date edits, name
/// edits) cannot drift from each other or from the server's version/409
/// contract.
class SessionUpdateSyncHelper {
  final ApiService _apiService;

  SessionUpdateSyncHelper(this._apiService);

  /// Push [localSession]'s current mutable fields to the server.
  ///
  /// Never guesses a version: it always sends whatever is persisted in
  /// [LocalSession.version] (which may be null) via
  /// [ModelMapper.buildSessionUpdateRequest].
  Future<SessionSyncOutcome> pushUpdate(
    Isar db,
    LocalSession localSession,
  ) async {
    final serverId = localSession.serverId;
    if (serverId == null) {
      throw StateError('Cannot push a session update without a serverId');
    }

    final payload = ModelMapper.buildSessionUpdateRequest(localSession);

    dynamic result;
    try {
      result = await _apiService.put<dynamic>(
        ApiConfig.sessionById(serverId),
        data: payload,
      );
    } on ApiException catch (e) {
      if (e.statusCode == 409) {
        return _handleConflict(db, localSession, e);
      }
      rethrow;
    }

    if (result is Map<String, dynamic>) {
      await _applyServerSession(db, localSession, Session.fromJson(result));
      return SessionSyncOutcome.synced;
    }

    // Rollback-safe path: an upgraded client may still be talking to an
    // older API that replies 204/empty on success. Recover the
    // authoritative session with a GET rather than guessing it applied.
    try {
      final data = await _apiService.get<Map<String, dynamic>>(
        ApiConfig.sessionById(serverId),
      );
      await _applyServerSession(db, localSession, Session.fromJson(data));
      return SessionSyncOutcome.synced;
    } catch (_) {
      // Recovery failed - leave the pending local edit untouched for retry.
      return SessionSyncOutcome.deferred;
    }
  }

  Future<void> _applyServerSession(
    Isar db,
    LocalSession localSession,
    Session serverSession,
  ) async {
    await db.writeTxn(() async {
      final updated = ModelMapper.sessionToLocal(
        serverSession,
        localId: localSession.localId,
        isSynced: true,
      );
      await db.localSessions.put(updated);
    });
  }

  Future<SessionSyncOutcome> _handleConflict(
    Isar db,
    LocalSession localSession,
    ApiException e,
  ) async {
    final data = e.responseData;
    final serverData = data is Map ? data['serverData'] : null;
    final currentVersion = data is Map ? data['currentVersion'] : null;

    if (serverData is! Map || currentVersion is! int) {
      // Malformed conflict payload - never overwrite the pending edit;
      // just record the failure so the row keeps retrying safely.
      await db.writeTxn(() async {
        localSession.syncError = 'Malformed 409 conflict response';
        localSession.lastSyncAttempt = DateTime.now().toUtc();
        await db.localSessions.put(localSession);
      });
      return SessionSyncOutcome.conflictDataInvalid;
    }

    await db.writeTxn(() async {
      localSession.conflictServerSnapshotJson = jsonEncode(serverData);
      localSession.conflictServerVersion = currentVersion;
      localSession.conflictDetectedAt = DateTime.now().toUtc();
      localSession.syncStatus = 'conflict';
      localSession.isSynced = false;
      await db.localSessions.put(localSession);
    });
    return SessionSyncOutcome.conflict;
  }
}
