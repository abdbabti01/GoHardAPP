/// Sessions state management using Riverpod.
/// Replaces SessionsProvider ChangeNotifier with a more scalable pattern.
///
library;

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/session.dart';
import '../../data/repositories/session_repository.dart';
import '../../core/services/connectivity_service.dart';
import 'repository_providers.dart';
import 'core_providers.dart';

// ============================================================
// Sessions State
// ============================================================

/// Immutable state class for sessions
class SessionsState {
  final bool isLoading;
  final bool isCreating;
  final List<Session> sessions;
  final String? errorMessage;

  const SessionsState({
    this.isLoading = false,
    this.isCreating = false,
    this.sessions = const [],
    this.errorMessage,
  });

  SessionsState copyWith({
    bool? isLoading,
    bool? isCreating,
    List<Session>? sessions,
    String? errorMessage,
  }) {
    return SessionsState(
      isLoading: isLoading ?? this.isLoading,
      isCreating: isCreating ?? this.isCreating,
      sessions: sessions ?? this.sessions,
      errorMessage: errorMessage,
    );
  }

  /// Get sessions filtered by program
  List<Session> getSessionsForProgram(int programId) {
    return sessions.where((s) => s.programId == programId).toList();
  }

  /// Get sessions not linked to any program
  List<Session> get standaloneSessions {
    return sessions.where((s) => s.programId == null).toList();
  }

  /// Get sessions sorted by date (newest first)
  List<Session> get sortedByDate {
    final sorted = List<Session>.from(sessions);
    sorted.sort((a, b) => b.date.compareTo(a.date));
    return sorted;
  }
}

// ============================================================
// Sessions Notifier
// ============================================================

/// StateNotifier for sessions state management
class SessionsNotifier extends StateNotifier<SessionsState> {
  final SessionRepository _sessionRepository;
  final ConnectivityService _connectivity;

  StreamSubscription? _connectivitySubscription;

  SessionsNotifier(this._sessionRepository, this._connectivity)
    : super(const SessionsState()) {
    _init();
  }

  void _init() {
    // Listen to connectivity changes to refresh data when online
    _connectivitySubscription = _connectivity.connectivityStream.listen((
      isOnline,
    ) {
      if (isOnline) {
        loadSessions();
      }
    });
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  /// Load all sessions for current user
  Future<void> loadSessions() async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      // The repository handles userId internally via AuthService
      final sessions = await _sessionRepository.getSessions();
      state = state.copyWith(isLoading: false, sessions: sessions);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  /// Create a new session
  Future<Session?> createSession(Session session) async {
    state = state.copyWith(isCreating: true, errorMessage: null);

    try {
      final created = await _sessionRepository.createSession(session);
      // Reload sessions to get the updated list
      await loadSessions();
      state = state.copyWith(isCreating: false);
      return created;
    } catch (e) {
      state = state.copyWith(isCreating: false, errorMessage: e.toString());
      return null;
    }
  }

  /// Update session status (draft, in_progress, completed)
  Future<bool> updateSessionStatus(int sessionId, String status) async {
    try {
      await _sessionRepository.updateSessionStatus(sessionId, status);
      // Reload sessions to get the updated list
      await loadSessions();
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      return false;
    }
  }

  /// Delete a session
  Future<bool> deleteSession(int sessionId) async {
    try {
      await _sessionRepository.deleteSession(sessionId);
      // Reload sessions to get the updated list
      await loadSessions();
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      return false;
    }
  }

  /// Get a single session by ID
  Session? getSessionById(int sessionId) {
    try {
      return state.sessions.firstWhere((s) => s.id == sessionId);
    } catch (_) {
      return null;
    }
  }

  /// Clear error message
  void clearError() {
    state = state.copyWith(errorMessage: null);
  }
}

// ============================================================
// Provider Definition
// ============================================================

/// Sessions state notifier provider
final sessionsNotifierProvider =
    StateNotifierProvider<SessionsNotifier, SessionsState>((ref) {
      final sessionRepository = ref.watch(sessionRepositoryProvider);
      final connectivity = ref.watch(connectivityServiceProvider);
      return SessionsNotifier(sessionRepository, connectivity);
    });

/// Convenience provider for sessions list
final sessionsListProvider = Provider<List<Session>>((ref) {
  return ref.watch(sessionsNotifierProvider).sessions;
});

/// Convenience provider for loading state
final sessionsLoadingProvider = Provider<bool>((ref) {
  return ref.watch(sessionsNotifierProvider).isLoading;
});

/// Provider for a specific session by ID
final sessionByIdProvider = Provider.family<Session?, int>((ref, sessionId) {
  final sessions = ref.watch(sessionsNotifierProvider).sessions;
  try {
    return sessions.firstWhere((s) => s.id == sessionId);
  } catch (_) {
    return null;
  }
});
