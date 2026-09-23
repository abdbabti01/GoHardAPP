import 'package:flutter/foundation.dart';

import '../data/local/services/local_database_service.dart';
import '../data/repositories/account_repository.dart';
import 'auth_provider.dart';

/// Orchestrates permanent account deletion: server deletion MUST succeed
/// before any local state is touched (a transient network error must never
/// leave the user logged out of a server account that still exists), then
/// reuses [AuthProvider.logout]'s existing, battle-tested session-termination
/// pass (session-epoch invalidation, in-flight request cancellation,
/// credential/background-service clearing, navigation to the unauthenticated
/// destination), and only then wipes every local record via
/// [LocalDatabaseService.clearAll] - the one thing logout deliberately never
/// does. Onboarding completion is intentionally left untouched: it reflects
/// whether this app installation has been introduced to a user before, not
/// whether any particular account still exists, so the post-deletion
/// destination is the Login screen, not onboarding again.
class AccountDeletionProvider extends ChangeNotifier {
  final AccountRepository _accountRepository;
  final AuthProvider _authProvider;
  final LocalDatabaseService _localDb;

  AccountDeletionProvider(
    this._accountRepository,
    this._authProvider,
    this._localDb,
  );

  bool _isDeleting = false;
  String? _errorMessage;

  bool get isDeleting => _isDeleting;
  String? get errorMessage => _errorMessage;

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Returns true on success. Double-submit safe: a call while one is
  /// already in flight is ignored rather than firing a second request.
  Future<bool> deleteAccount(String password) async {
    if (_isDeleting) return false;

    _isDeleting = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final outcome = await _accountRepository.deleteAccount(password);
      switch (outcome) {
        case AccountDeletionOutcome.invalidPassword:
          _errorMessage = 'Incorrect password';
          return false;
        case AccountDeletionOutcome.success:
          break;
      }

      // Server deletion succeeded - now it is safe to end the local session
      // and destroy local data. Neither step is allowed to fail this
      // operation: the server-side deletion already committed, so from here
      // on we do the best we can locally and never report failure back to
      // the user for what is, from the server's perspective, already done.
      try {
        await _authProvider.logout();
      } catch (e) {
        debugPrint('⚠️ Post-deletion logout step failed: $e');
      }
      try {
        await _localDb.clearAll();
      } catch (e) {
        debugPrint('⚠️ Failed to clear local data after account deletion: $e');
      }

      return true;
    } catch (e) {
      _errorMessage =
          'Could not delete your account. Check your connection and try again.';
      debugPrint('Account deletion error: $e');
      return false;
    } finally {
      _isDeleting = false;
      notifyListeners();
    }
  }
}
