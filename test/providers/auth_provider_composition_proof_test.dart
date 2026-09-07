import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Locates the repository root by walking up from the current working
/// directory until a `pubspec.yaml` is found - works regardless of exactly
/// where `flutter test` happens to be invoked from.
Directory _repoRoot() {
  var dir = Directory.current;
  while (!File('${dir.path}/pubspec.yaml').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      fail('Could not locate repository root (no pubspec.yaml found).');
    }
    dir = parent;
  }
  return dir;
}

String _readLib(String relativePath) {
  final file = File('${_repoRoot().path}/lib/$relativePath');
  expect(file.existsSync(), isTrue, reason: '${file.path} must exist');
  return file.readAsStringSync();
}

/// A source-level composition proof, not a behavioral test: reads the
/// REAL production source of `main.dart`'s composition and
/// `AuthProvider`/`SessionCleanupCoordinator` themselves, and asserts:
///
///  1. `main.dart` actually instantiates `SessionCleanupInitializer` (the
///     widget that performs the real wiring) somewhere in the real app
///     tree - not just in a test's own hand-built Provider graph.
///  2. That wiring assigns `AuthProvider.onSessionEnding` to
///     `SessionCleanupCoordinator.cleanUp` specifically - not some other,
///     unreviewed method.
///  3. `SessionCleanupCoordinator` (the class `onSessionEnding` is wired
///     to in production) never references Isar, `clearAll`, or
///     `DatabaseCleanup` anywhere in its own source.
///  4. Inside `auth_provider.dart`, the string `clearAll` appears ONLY
///     within the body of `_clearDurableDataForExplicitLogout` - the one
///     method in the whole file gated behind `pass.kind ==
///     _TerminationKind.explicitLogout` and reachable ONLY from an
///     explicit-logout-kind pass, never from a pass that stays
///     forced-expiration-only for its entire run (see
///     `_runTerminationPass`).
///
/// This is the composition-level complement to the behavioral proof in
/// `auth_provider_forced_expiration_durable_retention_test.dart` (real
/// Isar, real `LocalDatabaseService.instance`) and
/// `auth_provider_termination_race_test.dart` (mocked `LocalDatabaseService
/// .clearAll` call-count assertions) - together they show BOTH that the
/// real app wiring routes forced expiration through the real, Isar-free
/// coordinator, AND that no code path inside `AuthProvider` itself could
/// reach a durable-data write even if the wiring were somehow different.
void main() {
  test('main.dart wires the real app to SessionCleanupInitializer, which '
      'assigns AuthProvider.onSessionEnding to coordinator.cleanUp', () {
    final mainSource = _readLib('main.dart');
    expect(
      mainSource.contains('SessionCleanupInitializer('),
      isTrue,
      reason:
          'the real app composition root must actually construct the '
          'widget that performs the onSessionEnding wiring - this is '
          'what makes it PRODUCTION wiring, not merely something a test '
          'constructs by hand',
    );

    final initializerSource = _readLib(
      'core/services/session_cleanup_initializer.dart',
    );
    expect(
      initializerSource.contains(
        'authProvider.onSessionEnding = coordinator.cleanUp;',
      ),
      isTrue,
      reason:
          'onSessionEnding must be wired to SessionCleanupCoordinator\'s '
          'own cleanUp method by name - a textual match, not an '
          'assumption, so a future refactor that silently rewires this '
          'to something else fails this test immediately',
    );
  });

  test('SessionCleanupCoordinator - the class onSessionEnding is wired to in '
      'production - never references Isar, clearAll, or DatabaseCleanup '
      'anywhere in its own source', () {
    final coordinatorSource = _readLib(
      'core/services/session_cleanup_coordinator.dart',
    );
    final codeOnly = _stripComments(coordinatorSource);

    for (final forbidden in [
      'clearAll',
      'DatabaseCleanup',
      'Isar.',
      'isar.',
      '.writeTxn',
    ]) {
      expect(
        codeOnly.contains(forbidden),
        isFalse,
        reason:
            'SessionCleanupCoordinator must never reference "$forbidden" '
            'in actual code - it is real, non-mocked production wiring '
            'that AuthProvider\'s forced-expiration pass invokes '
            'unconditionally (onSessionEnding), so if it ever touched '
            'Isar, no amount of AuthProvider-level guarding could stop '
            'forced expiration from indirectly deleting durable data',
      );
    }
  });

  test('inside auth_provider.dart, "clearAll" appears ONLY within '
      '_clearDurableDataForExplicitLogout - the sole method reachable ONLY '
      'from an explicit-logout-kind pass', () {
    final authProviderSource = _readLib('providers/auth_provider.dart');
    final codeOnly = _stripComments(authProviderSource);

    final clearAllOccurrences = 'clearAll'.allMatches(codeOnly).length;
    expect(
      clearAllOccurrences,
      greaterThan(0),
      reason:
          'sanity check: explicit logout must still actually clear Isar '
          'somewhere in this file',
    );

    final methodMatch = RegExp(
      r'Future<void> _clearDurableDataForExplicitLogout\(\) async \{([\s\S]*?)\n  \}',
    ).firstMatch(codeOnly);
    expect(
      methodMatch,
      isNotNull,
      reason: '_clearDurableDataForExplicitLogout must exist as written',
    );
    final methodBody = methodMatch!.group(1)!;
    final occurrencesInsideMethod = 'clearAll'.allMatches(methodBody).length;

    expect(
      occurrencesInsideMethod,
      clearAllOccurrences,
      reason:
          'every single occurrence of "clearAll" in the whole file must '
          'be inside _clearDurableDataForExplicitLogout - if a future '
          'edit added ANY other call site (even one nominally guarded by '
          'a pass.kind check inline), this composition proof fails, '
          'forcing that new call site through the same, single, '
          'greppable, reviewable choke point',
    );

    // And that method itself must only ever be invoked from a line that
    // also mentions the explicit-logout kind, so the choke point itself
    // cannot be reached from a pass that never became one.
    final callSites = RegExp(
      r'^.*_clearDurableDataForExplicitLogout\(\).*$',
      multiLine: true,
    ).allMatches(codeOnly).where((m) => !m.group(0)!.contains('Future<void>'));
    for (final call in callSites) {
      // The call site itself is a bare `await _clearDurableDataForExplicitLogout();`
      // guarded by an `if (pass.kind == _TerminationKind.explicitLogout)`
      // on the line(s) immediately above - verified structurally by
      // locating the nearest preceding `if (pass.kind ==` within a small
      // window, since Dart's own type system does not expose control
      // flow to a plain source scan.
      final callIndex = codeOnly.indexOf(call.group(0)!);
      final precedingWindow = codeOnly.substring(
        (callIndex - 200).clamp(0, codeOnly.length),
        callIndex,
      );
      expect(
        precedingWindow.contains(
          'pass.kind == _TerminationKind.explicitLogout',
        ),
        isTrue,
        reason:
            'the call to _clearDurableDataForExplicitLogout() must be '
            'immediately guarded by an explicit-logout kind check',
      );
    }
  });

  test('the FCM-unregister call site sits AFTER the onSessionEnding await, '
      'never inside the pass\'s synchronous prefix (before any await) - a '
      'check placed any earlier could never observe a LATE-joining explicit '
      'logout upgrading pass.kind, since nothing else can run in that '
      'window at all (Dart single-threaded execution never yields before a '
      'pass\'s first await)', () {
    final authProviderSource = _readLib('providers/auth_provider.dart');
    final codeOnly = _stripComments(authProviderSource);

    final runPassMatch = RegExp(
      r'Future<void> _runTerminationPass\(_TerminationPass pass\) async \{([\s\S]*?)\n  \}',
    ).firstMatch(codeOnly);
    expect(
      runPassMatch,
      isNotNull,
      reason: '_runTerminationPass must exist as written',
    );
    final body = runPassMatch!.group(1)!;

    final onSessionEndingIndex = body.indexOf('onSessionEnding?.call()');
    final fcmCallIndex = body.indexOf('_unregisterFcmForExplicitLogout()');
    expect(onSessionEndingIndex, greaterThanOrEqualTo(0));
    expect(fcmCallIndex, greaterThanOrEqualTo(0));

    expect(
      fcmCallIndex,
      greaterThan(onSessionEndingIndex),
      reason:
          'a prior version of this code placed the FCM-unregister check '
          'BEFORE onSessionEnding\'s await, in the pass\'s synchronous '
          'prefix - structurally unreachable by any join, so a pass '
          'that started as forced-expiration-only would ALWAYS skip '
          'FCM-unregister even after a later logout() call upgraded '
          'it (an independent reviewer caught this; see the git history '
          'for the fix). This test pins the corrected ordering.',
    );

    // The ordering alone isn't enough - the call must still be gated by
    // an explicit-logout kind check immediately before it (mirroring
    // the analogous check for _clearDurableDataForExplicitLogout
    // above), or a regression that made it fire unconditionally (even
    // for a pure forced-expiration pass) would satisfy the ordering
    // assertion above while reintroducing a different bug.
    final precedingWindow = body.substring(
      (fcmCallIndex - 200).clamp(0, body.length),
      fcmCallIndex,
    );
    expect(
      precedingWindow.contains('pass.kind == _TerminationKind.explicitLogout'),
      isTrue,
      reason:
          'the call to _unregisterFcmForExplicitLogout() must remain '
          'guarded by an explicit-logout kind check - it must never '
          'fire unconditionally for a pass that stays '
          'forced-expiration-only',
    );
  });
}

/// Strips `//` line comments and `///`/`/* */` block comments so a plain
/// substring search doesn't get confused by a forbidden word appearing
/// only in prose (e.g. this very file's own doc comments, if it somehow
/// searched itself - it does not, but the source files it reads do
/// legitimately mention "Isar"/"clearAll" in their own doc comments).
String _stripComments(String source) {
  final noBlockComments = source.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  final lines = noBlockComments.split('\n');
  final buffer = StringBuffer();
  for (final line in lines) {
    final commentIndex = line.indexOf('//');
    buffer.writeln(commentIndex == -1 ? line : line.substring(0, commentIndex));
  }
  return buffer.toString();
}
