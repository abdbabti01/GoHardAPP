import '../../core/constants/api_config.dart';
import '../services/api_exception.dart';
import '../services/api_service.dart';

enum AccountDeletionOutcome { success, invalidPassword }

/// Repository for the single account-lifecycle operation that outlives the
/// account itself: permanent deletion. Uses the generic (session-bound)
/// [ApiService.delete] rather than [ApiService.postPublic] - unlike
/// login/signup, this call IS authenticated by the current session's token,
/// so a genuine 401 (e.g. the token expired mid-request) SHOULD trigger the
/// app's normal forced-session-expiration handling, not be suppressed.
class AccountRepository {
  final ApiService _apiService;

  AccountRepository(this._apiService);

  /// Calls `DELETE /account` with the current password. The account to
  /// delete is never named by this call - the server derives it solely from
  /// the caller's own JWT (see AccountController.DeleteAccount) - so there is
  /// no request value here that could ever target a different account.
  ///
  /// Returns [AccountDeletionOutcome.invalidPassword] for the server's 400
  /// (wrong password); any other failure (network, 401, 5xx) propagates as
  /// the same exception every other [ApiService] call throws, for the caller
  /// to handle exactly like it handles any other failed request.
  Future<AccountDeletionOutcome> deleteAccount(String password) async {
    try {
      await _apiService.delete(ApiConfig.account, data: {'password': password});
      return AccountDeletionOutcome.success;
    } on ApiException catch (e) {
      if (e.statusCode == 400) {
        return AccountDeletionOutcome.invalidPassword;
      }
      rethrow;
    }
  }
}
