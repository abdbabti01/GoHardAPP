/// An immutable snapshot of a specific authenticated session, captured at
/// the moment some async work began. Two tokens describe the same session
/// only if both fields match exactly - in practice `generation` alone is
/// already globally unique per session (see [UserSessionEpoch]), so
/// `userId` is redundant for correctness but kept for defensive-in-depth
/// and readability (assertion failures/debug logs can name the user
/// without a separate lookup).
final class UserSessionToken {
  const UserSessionToken({required this.generation, required this.userId});

  /// Monotonically increasing identity for this session. Bumped by every
  /// [UserSessionEpoch.activate] AND every [UserSessionEpoch.invalidate]
  /// call - never reused, never decremented, never reset. No two sessions
  /// (authenticated or logged-out) ever share a generation.
  final int generation;

  /// The authenticated user this token belongs to. Always non-null here -
  /// a token is only ever produced by [UserSessionEpoch.capture] while a
  /// user is active; there is no such thing as a token for "logged out."
  final int userId;

  @override
  bool operator ==(Object other) =>
      other is UserSessionToken &&
      other.generation == generation &&
      other.userId == userId;

  @override
  int get hashCode => Object.hash(generation, userId);

  @override
  String toString() =>
      'UserSessionToken(generation: $generation, userId: $userId)';
}

/// The single source of truth for "which authenticated session, if any, is
/// currently active." A plain, dependency-free value service - no
/// `BuildContext`, no dependency on `AuthProvider` or any feature Provider,
/// safe to inject into anything without risk of a circular dependency.
///
/// Fixes the exact race a naive "increment on logout only" epoch has: if
/// only [invalidate] bumps the generation, a callback that starts during
/// the logged-out gap between User A's logout and User B's login would
/// capture the same generation User B's own first loads then use,
/// incorrectly passing a staleness check it should fail. Both [activate]
/// and [invalidate] bump the generation here, so the logged-out gap
/// consumes its own generation - strictly between A's last active
/// generation and B's new one - and [capture] returns `null` throughout
/// that gap so there is nothing for a logged-out-triggered callback to
/// hold onto in the first place.
///
/// This class deliberately exposes no way to set the generation directly
/// - only [activate]/[invalidate] can advance it, and both always advance
/// it forward by exactly one.
class UserSessionEpoch {
  int _generation = 0;
  int? _activeUserId;

  /// Returns a token for the CURRENTLY active session, or `null` if there
  /// is no authenticated user right now. Callers must call this ONCE,
  /// before starting async work - never after an `await` - since the
  /// whole point is to snapshot "what session was active when this
  /// began." A `null` result means there is no session to do user-scoped
  /// work for at all; callers should not start the operation.
  UserSessionToken? capture() {
    final userId = _activeUserId;
    if (userId == null) return null;
    return UserSessionToken(generation: _generation, userId: userId);
  }

  /// True only if [token] still describes the CURRENT session - i.e.
  /// nothing has activated a different session or invalidated this one
  /// since [token] was captured. A token from a superseded generation
  /// (any prior user, any prior logged-out gap, or this same user's own
  /// earlier session) always returns false, forever - generations are
  /// never reused.
  bool isCurrent(UserSessionToken token) =>
      token.generation == _generation && token.userId == _activeUserId;

  /// Called exactly once per successful login/signup/session-restoration.
  /// ALWAYS bumps the generation, even for the same [userId]
  /// re-authenticating - this is what guarantees a new session never
  /// collides with anything captured before it, including during a
  /// logged-out gap that only [invalidate] would otherwise have marked.
  void activate(int userId) {
    _generation++;
    _activeUserId = userId;
  }

  /// Called once per logical logout pass, before any cleanup step runs.
  /// Bumps the generation and clears the active user - [capture] now
  /// returns `null` until the next [activate].
  void invalidate() {
    _generation++;
    _activeUserId = null;
  }
}
