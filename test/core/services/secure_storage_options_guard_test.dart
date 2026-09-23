// BUG-10 guard: on Android every FlutterSecureStorage shares one prefs file,
// so mixing encrypted and default modes made the plugin migrate entries and a
// default-mode read then returned null (onboarding flag lost after process
// death). The platform behavior can't run in a unit test, so this pins the
// invariant: every instance must pass kAndroidSecureOptions.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every FlutterSecureStorage instance uses kAndroidSecureOptions', () {
    final pattern = RegExp(r'FlutterSecureStorage\(([^;]*?)\)\s*;');
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      for (final m in pattern.allMatches(src)) {
        if (!m.group(1)!.contains('kAndroidSecureOptions')) {
          offenders.add(f.path);
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
