import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regression tests for `.githooks/pre-commit`.
///
/// The hook runs `dart format` and `flutter analyze`. Git exports repo-local
/// environment variables (`GIT_DIR`, `GIT_INDEX_FILE`, `GIT_WORK_TREE`,
/// `GIT_PREFIX`, `GIT_CONFIG_PARAMETERS`, ...) into every hook process. If
/// those leak into `dart` / `flutter`, Flutter's own `git` calls (notably
/// `bin/internal/update_engine_version` -> `git -C "$FLUTTER_ROOT" ls-files
/// bin/internal/engine.version`) resolve against THIS repo instead of the
/// SDK, bypass the "engine.version is tracked, leave it alone" guard, and
/// overwrite the external Flutter SDK's `engine.version` with an empty
/// string - breaking `dart`/`flutter` machine-wide.
///
/// These tests drive the real hook script with a fully controlled harness:
/// a throwaway git repo (path deliberately containing a space), fake
/// `dart` / `flutter` executables on `PATH` that record their environment
/// and cwd, and a polluted `GIT_*` environment that mirrors what
/// `git commit` exports. No dependency on the developer's real Flutter
/// install. Requires only `git` and a POSIX `sh` (present on every dev
/// machine and CI runner; git-bash provides `sh` on Windows).
void main() {
  final sh = _findSh();
  final gitAvailable = _which('git') != null;
  final canRun = sh != null && gitAvailable;

  late Directory work; // <tmp>/pre commit hook <rnd>
  late Directory repo; // <work>/repo               (space in the full path)
  late Directory fakeBin; // <repo>/.fakebin
  late Directory outDir; // <work>/out              (OUTSIDE the repo)
  late File hookScript; // <repo>/pre-commit        (copy of the real hook)
  late File outsideSentinel; // <outDir>/SDK_WOULD_BE_CORRUPTED

  final repoHook = File(
    _join([Directory.current.path, '.githooks', 'pre-commit']),
  );

  setUp(() async {
    if (!canRun) return;
    work = await Directory.systemTemp.createTemp('pre commit hook ');
    repo = Directory(_join([work.path, 'repo']))..createSync(recursive: true);
    outDir = Directory(_join([work.path, 'out']))..createSync(recursive: true);
    fakeBin = Directory(_join([repo.path, '.fakebin']))..createSync();
    outsideSentinel = File(_join([outDir.path, 'SDK_WOULD_BE_CORRUPTED']));

    // Real git repo so the hook's own `git rev-parse ...` calls work.
    await _run('git', ['init', '-q'], repo.path);
    await _run('git', ['config', 'user.email', 't@t'], repo.path);
    await _run('git', ['config', 'user.name', 't'], repo.path);
    File(_join([repo.path, 'seed.txt'])).writeAsStringSync('seed\n');
    await _run('git', ['add', 'seed.txt'], repo.path);
    await _run('git', ['commit', '-q', '-m', 'seed'], repo.path);

    hookScript = File(_join([repo.path, 'pre-commit']))
      ..writeAsStringSync(repoHook.readAsStringSync());

    // Fake `dart`: records env + cwd, exits with $FAKE_DART_EXIT (default 0).
    _writeExecutable(_join([fakeBin.path, 'dart']), r'''
#!/bin/sh
env > "$FAKE_OUT/dart.env"
pwd > "$FAKE_OUT/dart.cwd"
exit "${FAKE_DART_EXIT:-0}"
''');

    // Fake `flutter`: records env + cwd, and - modelling the real failure -
    // only "corrupts the SDK" (writes OUTSIDE the repo) if it still sees a
    // leaked GIT_DIR. Exits with $FAKE_FLUTTER_EXIT (default 0).
    _writeExecutable(_join([fakeBin.path, 'flutter']), r'''
#!/bin/sh
env > "$FAKE_OUT/flutter.env"
pwd > "$FAKE_OUT/flutter.cwd"
if [ -n "$GIT_DIR" ]; then
  echo "leaked GIT_DIR=$GIT_DIR" > "$SDK_SENTINEL"
fi
exit "${FAKE_FLUTTER_EXIT:-0}"
''');
  });

  tearDown(() async {
    if (!canRun) return;
    if (await work.exists()) {
      await work.delete(recursive: true);
    }
  });

  Future<ProcessResult> runHook({
    String dartExit = '0',
    String flutterExit = '0',
  }) {
    final gitDir = _join([repo.path, '.git']);
    return Process.run(
      sh!,
      [hookScript.path],
      workingDirectory: repo.path,
      environment: {
        // Fake tools win over anything real on PATH.
        'PATH': '${fakeBin.path}$_pathSep${Platform.environment['PATH'] ?? ''}',
        'FAKE_OUT': outDir.path,
        'SDK_SENTINEL': outsideSentinel.path,
        'FAKE_DART_EXIT': dartExit,
        'FAKE_FLUTTER_EXIT': flutterExit,
        // A benign var that MUST survive into the child tools.
        'HOOK_KEEP_ME': 'unrelated-value',
        // What `git commit` exports into a hook - must NOT reach the tools.
        'GIT_DIR': gitDir,
        'GIT_INDEX_FILE': _join([gitDir, 'index']),
        'GIT_WORK_TREE': repo.path,
        'GIT_PREFIX': '',
        'GIT_CONFIG_PARAMETERS': "'protocol.version=2'",
        if (Platform.environment.containsKey('HOME'))
          'HOME': Platform.environment['HOME']!,
        if (Platform.environment.containsKey('USERPROFILE'))
          'USERPROFILE': Platform.environment['USERPROFILE']!,
        if (Platform.environment.containsKey('SYSTEMROOT'))
          'SYSTEMROOT': Platform.environment['SYSTEMROOT']!,
      },
    );
  }

  Map<String, String> parseEnvFile(String name) {
    final out = <String, String>{};
    for (final line in File(_join([outDir.path, name])).readAsLinesSync()) {
      final i = line.indexOf('=');
      if (i > 0) out[line.substring(0, i)] = line.substring(i + 1);
    }
    return out;
  }

  test('repo-local Git variables are absent from the dart/flutter child '
      'environment (both tools)', () async {
    if (!canRun) {
      markTestSkipped('needs git + POSIX sh');
      return;
    }
    final res = await runHook();
    expect(
      res.exitCode,
      0,
      reason: 'stdout:\n${res.stdout}\nstderr:\n${res.stderr}',
    );

    final localVars =
        (await _run('git', ['rev-parse', '--local-env-vars'], repo.path)).stdout
            .toString()
            .split(RegExp(r'\s+'))
            .where((s) => s.isNotEmpty)
            .toSet();
    expect(localVars, contains('GIT_DIR')); // sanity: the list is non-trivial

    for (final envFile in ['dart.env', 'flutter.env']) {
      final env = parseEnvFile(envFile);
      final leaked = env.keys.where(localVars.contains).toList();
      expect(
        leaked,
        isEmpty,
        reason: '$envFile leaked repo-local Git vars: $leaked',
      );
      expect(env.containsKey('GIT_DIR'), isFalse);
      expect(env.containsKey('GIT_INDEX_FILE'), isFalse);
      expect(env.containsKey('GIT_WORK_TREE'), isFalse);
      expect(env.containsKey('GIT_PREFIX'), isFalse);
      expect(env.containsKey('GIT_CONFIG_PARAMETERS'), isFalse);
    }
  });

  test('unrelated environment variables still reach the child tools', () async {
    if (!canRun) {
      markTestSkipped('needs git + POSIX sh');
      return;
    }
    await runHook();
    for (final envFile in ['dart.env', 'flutter.env']) {
      final env = parseEnvFile(envFile);
      expect(
        env['HOOK_KEEP_ME'],
        'unrelated-value',
        reason: '$envFile dropped a benign var',
      );
      expect(env['PATH'], isNotNull);
      expect(env['FAKE_OUT'], outDir.path);
    }
  });

  test('the hook runs the checks against the repo working tree (cwd is the '
      'repo root, whose path contains a space)', () async {
    if (!canRun) {
      markTestSkipped('needs git + POSIX sh');
      return;
    }
    await runHook();
    // The hook does `cd "$(git rev-parse --show-toplevel)"`. `git` and the
    // fake tools' `pwd` can print the path in different forms (Windows
    // `C:/...` vs msys `/tmp/...`), so match on the form-independent tail:
    // "<unique temp dir>/repo", with its embedded space.
    final tail = '${work.path.split(RegExp(r'[\\/]')).last}/repo';
    expect(tail, contains(' '), reason: 'harness must exercise a spaced path');
    for (final cwdFile in ['dart.cwd', 'flutter.cwd']) {
      final seen = File(
        _join([outDir.path, cwdFile]),
      ).readAsStringSync().trim().replaceAll('\\', '/');
      expect(
        seen,
        endsWith(tail),
        reason: '$cwdFile should be the repo working tree root',
      );
    }
  });

  test('a failing dart format check fails the hook', () async {
    if (!canRun) {
      markTestSkipped('needs git + POSIX sh');
      return;
    }
    final res = await runHook(dartExit: '2');
    expect(res.exitCode, isNonZero);
    expect(res.stdout.toString(), contains('Formatting check failed'));
    expect(File(_join([outDir.path, 'flutter.env'])).existsSync(), isFalse);
  });

  test('a failing flutter analyze fails the hook', () async {
    if (!canRun) {
      markTestSkipped('needs git + POSIX sh');
      return;
    }
    final res = await runHook(flutterExit: '3');
    expect(res.exitCode, isNonZero);
    expect(res.stdout.toString(), contains('flutter analyze reported issues'));
  });

  test('both checks passing makes the hook succeed', () async {
    if (!canRun) {
      markTestSkipped('needs git + POSIX sh');
      return;
    }
    final res = await runHook();
    expect(res.exitCode, 0);
    expect(res.stdout.toString(), contains('Pre-commit checks passed.'));
    expect(File(_join([outDir.path, 'dart.env'])).existsSync(), isTrue);
    expect(File(_join([outDir.path, 'flutter.env'])).existsSync(), isTrue);
  });

  test('the hook never causes a write outside the repository - it cannot '
      'corrupt the external SDK', () async {
    if (!canRun) {
      markTestSkipped('needs git + POSIX sh');
      return;
    }
    final before =
        _listRecursive(work).where((e) => !_isWithin(repo.path, e)).toSet();

    final res = await runHook();
    expect(res.exitCode, 0);

    expect(
      outsideSentinel.existsSync(),
      isFalse,
      reason:
          'a leaked GIT_DIR would have triggered an out-of-repo write '
          '(the exact real-SDK corruption mechanism)',
    );

    final after =
        _listRecursive(work).where((e) => !_isWithin(repo.path, e)).toSet();
    final created = after.difference(before)
      ..removeWhere((e) => _isWithin(outDir.path, e)); // fake-tool recorders
    expect(
      created,
      isEmpty,
      reason: 'hook created files outside the repo: $created',
    );
  });
}

// ------------------------- harness helpers -------------------------

String get _pathSep => Platform.isWindows ? ';' : ':';

String _join(List<String> parts) => parts.join('/');

bool _isWithin(String parent, String child) {
  final p = Directory(parent).absolute.path.replaceAll('\\', '/');
  final c = File(child).absolute.path.replaceAll('\\', '/');
  return c == p || c.startsWith('$p/');
}

String? _findSh() {
  final localAppData = Platform.environment['LOCALAPPDATA'];
  final programFiles = Platform.environment['ProgramFiles'];
  final candidates =
      Platform.isWindows
          ? [
            if (programFiles != null) '$programFiles\\Git\\bin\\sh.exe',
            if (programFiles != null) '$programFiles\\Git\\usr\\bin\\sh.exe',
            r'C:\Program Files\Git\bin\sh.exe',
            r'C:\Program Files\Git\usr\bin\sh.exe',
            if (localAppData != null)
              '$localAppData\\Programs\\Git\\bin\\sh.exe',
            if (localAppData != null)
              '$localAppData\\Programs\\Git\\usr\\bin\\sh.exe',
            'sh',
          ]
          : ['/bin/sh', 'sh'];
  for (final c in candidates) {
    if (c == 'sh') {
      if (_which('sh') != null) return 'sh';
      continue;
    }
    if (File(c).existsSync()) return c;
  }
  return null;
}

String? _which(String exe) {
  try {
    final r = Process.runSync(Platform.isWindows ? 'where' : 'which', [exe]);
    if (r.exitCode == 0) {
      final first = r.stdout.toString().split('\n').first.trim();
      return first.isEmpty ? null : first;
    }
  } catch (_) {}
  return null;
}

Future<ProcessResult> _run(String exe, List<String> args, String cwd) async {
  final r = await Process.run(exe, args, workingDirectory: cwd);
  if (r.exitCode != 0) {
    throw StateError(
      '$exe ${args.join(' ')} failed (${r.exitCode}): ${r.stderr}',
    );
  }
  return r;
}

void _writeExecutable(String path, String contents) {
  File(path).writeAsStringSync(contents);
  // Best effort: needed on POSIX, a no-op concern under git-bash (which
  // execs by shebang regardless of the NTFS exec bit). Never let a missing
  // `chmod` on PATH turn setUp into a hard error.
  try {
    Process.runSync('chmod', ['+x', path]);
  } on ProcessException catch (_) {
    // ignore
  }
}

List<String> _listRecursive(Directory d) =>
    d.listSync(recursive: true, followLinks: false).map((e) => e.path).toList();
