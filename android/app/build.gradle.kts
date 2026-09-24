import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // TODO: Re-enable when Firebase is needed
    // id("com.google.gms.google-services")
}

// Release signing comes from android/key.properties (git-ignored) or, for CI,
// the GOHARD_* environment variables. Nothing secret lives in this file.
//   key.properties keys: storeFile, storePassword, keyAlias, keyPassword
//   env fallbacks:       GOHARD_KEYSTORE_PATH, GOHARD_KEYSTORE_PASSWORD,
//                        GOHARD_KEY_ALIAS,     GOHARD_KEY_PASSWORD
// If neither is present the release build falls back to the debug key (fine
// for `flutter run --release`, NOT distributable) and prints a warning. Set
// REQUIRE_RELEASE_SIGNING=true (e.g. in the release CI job) to make any
// release task fail instead of silently signing with the debug key.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

fun signingValue(propertyKey: String, envKey: String): String? =
    (keystoreProperties.getProperty(propertyKey) ?: System.getenv(envKey))
        ?.takeIf { it.isNotBlank() }

val releaseStoreFile = signingValue("storeFile", "GOHARD_KEYSTORE_PATH")
val releaseStorePassword = signingValue("storePassword", "GOHARD_KEYSTORE_PASSWORD")
val releaseKeyAlias = signingValue("keyAlias", "GOHARD_KEY_ALIAS")
val releaseKeyPassword = signingValue("keyPassword", "GOHARD_KEY_PASSWORD")
val hasReleaseSigning =
    listOf(releaseStoreFile, releaseStorePassword, releaseKeyAlias, releaseKeyPassword)
        .all { it != null }

android {
    namespace = "com.example.go_hard_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.go_hard_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                val releaseRequested =
                    gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }
                if (releaseRequested && System.getenv("REQUIRE_RELEASE_SIGNING") == "true") {
                    throw GradleException(
                        "Release signing is required but no keystore is configured. " +
                            "Provide android/key.properties or the GOHARD_KEYSTORE_* env vars."
                    )
                }
                if (releaseRequested) {
                    logger.warn(
                        "WARNING: release build is signed with the DEBUG key " +
                            "(no android/key.properties or GOHARD_KEYSTORE_* configured). " +
                            "Not distributable."
                    )
                }
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
