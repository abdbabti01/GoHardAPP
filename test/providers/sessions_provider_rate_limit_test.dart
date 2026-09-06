import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:go_hard_app/core/services/user_session_epoch.dart';
import 'package:go_hard_app/data/repositories/session_sync_diagnostics.dart';
import 'package:go_hard_app/data/services/rate_limited_exception.dart';
import 'package:go_hard_app/providers/sessions_provider.dart';

// Reuses the Mockito mocks generated for
// sessions_provider_sync_diagnostics_test.dart (same
// SessionRepository/ConnectivityService surface, unchanged by this PR) - no
// new build_runner output.
import 'sessions_provider_sync_diagnostics_test.mocks.dart';

/// Proves the "foreground authenticated operation receiving 429" contract
/// (prompt items 30-31) using `SessionsProvider.loadSessions()` as the
/// representative ordinary foreground repository call: the session stays
/// active (no logout, no epoch invalidation), no stale/fabricated success is
/// published, and the surfaced message is the existing generic
/// `e.toString().replaceAll('Exception: ', '')` pattern applied to
/// `RateLimitedException` - which is already safe (no raw header/body text)
/// with zero changes to this provider.
void main() {
  late MockSessionRepository repo;
  late UserSessionEpoch epoch;
  late MockConnectivityService connectivity;
  late StreamController<bool> connectivityController;
  late SessionsProvider provider;
  late StreamController<SessionSyncSnapshot> watchController;

  setUp(() {
    repo = MockSessionRepository();
    // Broadcast, unlike the single-subscription controller
    // sessions_provider_sync_diagnostics_test.dart uses: several tests below
    // deliberately never reach `_installWatch` (every `getSessions()` call
    // throws), so nothing ever calls `.listen()` on this stream - a
    // single-subscription StreamController's `close()` Future never
    // completes until the stream has been listened to at least once, which
    // would hang `tearDown` for exactly those tests.
    watchController = StreamController<SessionSyncSnapshot>.broadcast(
      sync: true,
    );
    when(
      repo.watchSessionSyncSnapshot(any),
    ).thenAnswer((_) => watchController.stream);

    epoch = UserSessionEpoch()..activate(1);
    connectivity = MockConnectivityService();
    connectivityController = StreamController<bool>.broadcast(sync: true);
    when(connectivity.isOnline).thenReturn(true);
    when(
      connectivity.connectivityStream,
    ).thenAnswer((_) => connectivityController.stream);
    provider = SessionsProvider(repo, epoch, connectivity);
  });

  tearDown(() async {
    try {
      provider.dispose();
    } catch (_) {}
    await connectivityController.close();
    if (!watchController.isClosed) await watchController.close();
  });

  test('30. a 429 on an ordinary foreground load keeps the session active - no '
      'logout, no epoch invalidation, and the row is reported as an error, '
      'never a silently fabricated success', () async {
    when(
      repo.getSessions(waitForSync: anyNamed('waitForSync')),
    ).thenThrow(const RateLimitedException(retryAfter: Duration(seconds: 20)));

    await provider.loadSessions();

    expect(provider.isLoading, isFalse);
    expect(provider.sessions, isEmpty);
    expect(
      provider.errorMessage,
      'Failed to load sessions: Too many requests. Please wait and try again.',
    );
    expect(epoch.isCurrent(UserSessionToken(generation: 1, userId: 1)), isTrue);
  });

  test('31. the surfaced message never contains a raw header/body value or the '
      'exception type name', () async {
    when(repo.getSessions(waitForSync: anyNamed('waitForSync'))).thenThrow(
      const RateLimitedException(
        retryAfter: Duration(seconds: 20),
        code: 'rate_limited',
      ),
    );

    await provider.loadSessions();

    expect(provider.errorMessage, isNot(contains('RateLimited')));
    expect(provider.errorMessage, isNot(contains('rate_limited')));
    expect(provider.errorMessage, isNot(contains('20')));
  });

  test('a later successful load (after the condition clears) recovers '
      'normally and clears the error', () async {
    when(
      repo.getSessions(waitForSync: anyNamed('waitForSync')),
    ).thenThrow(const RateLimitedException());
    await provider.loadSessions();
    expect(provider.errorMessage, isNotEmpty);

    when(
      repo.getSessions(waitForSync: anyNamed('waitForSync')),
    ).thenAnswer((_) async => <dynamic>[].cast());
    await provider.loadSessions();

    expect(provider.errorMessage, isNull);
  });
}
