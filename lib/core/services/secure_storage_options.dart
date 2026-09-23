import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Every FlutterSecureStorage instance must use these Android options.
/// Android backs all instances with the same "FlutterSecureStorage" prefs file;
/// mixing encrypted and default modes makes the plugin migrate entries into the
/// encrypted format, after which a default-mode read returns null (this lost
/// the onboarding flag after process death).
const AndroidOptions kAndroidSecureOptions = AndroidOptions(
  encryptedSharedPreferences: true,
);
