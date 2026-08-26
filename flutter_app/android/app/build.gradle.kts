plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing config.
//
// Resolution order, first match wins:
//   1. Env vars ANDROID_KEYSTORE_PATH / ANDROID_KEYSTORE_PASSWORD /
//      ANDROID_KEY_ALIAS / ANDROID_KEY_PASSWORD (matching the legacy
//      Dosbox-X-Android build.gradle, so the GitHub Actions secrets carry
//      over unchanged: ANDROID_KEYSTORE_BASE64 is decoded by the CI workflow
//      to a temp .jks and the path is exported).
//   2. `key.properties` next to this file -- a checked-out keystore + four
//      credentials, for local dev where the env vars aren't.
//
// applicationId is `app.simplespeccy` so existing SimpleSpeccy installs
// upgrade in place -- the display name is "Retro-Spectrum" and the Kotlin
// namespace is `com.crownpark.retro_spectrum` for code consistency, but the
// Play Store identity is the one inherited from the app this replaces.
import java.util.Properties

// Floor for the version code. SimpleSpeccy, the app this one replaces, is
// live on 83; anything at or below that is rejected at upload.
val SPECTRUM_VERSION_CODE_BASE = 100

data class KeystoreConfig(
    val path: String,
    val storePassword: String,
    val keyAlias: String,
    val keyPassword: String,
)

fun resolveKeystore(): KeystoreConfig? {
    val envPath = System.getenv("ANDROID_KEYSTORE_PATH")
    val envStorePw = System.getenv("ANDROID_KEYSTORE_PASSWORD")
    val envAlias = System.getenv("ANDROID_KEY_ALIAS")
    val envKeyPw = System.getenv("ANDROID_KEY_PASSWORD")
    if (envPath != null && envStorePw != null && envAlias != null && envKeyPw != null) {
        logger.lifecycle("release: using keystore from ANDROID_KEYSTORE_PATH env var")
        return KeystoreConfig(envPath, envStorePw, envAlias, envKeyPw)
    }

    val propsFile = rootProject.file("key.properties")
    if (propsFile.exists()) {
        val p = Properties().apply { load(propsFile.inputStream()) }
        val path = p["storeFile"] as String?
        val storePw = p["storePassword"] as String?
        val alias = p["keyAlias"] as String?
        val keyPw = p["keyPassword"] as String?
        if (path != null && storePw != null && alias != null && keyPw != null) {
            logger.lifecycle("release: using keystore from ${propsFile.absolutePath}")
            return KeystoreConfig(path, storePw, alias, keyPw)
        }
    }

    logger.warn(
        "release: no ANDROID_KEYSTORE_* env vars and no key.properties; " +
            "falling back to the debug keystore. This build will not be " +
            "accepted by Play Console."
    )
    return null
}

val keystoreConfig = resolveKeystore()

android {
    namespace = "com.crownpark.retro_spectrum"
    // Pinned, not flutter.compileSdkVersion. The whole Retro-* family states
    // its SDK levels outright: a floating value takes whatever the Flutter
    // on the build machine happens to default to, which is how Play
    // compliance ends up depending on which laptop or runner did the build.
    compileSdk = 36
    // The NDK the family builds its cores with.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Retro-Spectrum is the display name; `app.simplespeccy` is the Play
        // Store identity it inherits. This app REPLACES SimpleSpeccy, whose
        // listing has been published under that id since 2026 and is on
        // version code 83. Shipping under any other applicationId would create
        // a brand-new listing that existing installs never update to, which is
        // why the Kotlin namespace (com.crownpark.retro_spectrum, below) and
        // the applicationId deliberately differ. Play keys on this string and
        // it can never change again.
        applicationId = "app.simplespeccy"
        // 26, the Retro-* family standard. There is no Android core in this
        // project yet (native/speccy_core/android is empty), so nothing
        // constrains this from below -- it is set to match its siblings so
        // the first core built here has the target to hit.
        minSdk = 26
        // Play requires the target to stay within a year of the latest
        // Android release - 36 or higher from 31 August 2026 - and refuses
        // updates outright below that. flutter.targetSdkVersion floats with
        // whichever Flutter version happens to run the build, so an older SDK
        // on a CI runner or another machine could drop it under the bar
        // without a line of this project changing. Compliance is a decision,
        // so it is written down.
        targetSdk = 36
        // SimpleSpeccy published version code 83 and Play never accepts a code
        // at or below what is already live. The pubspec restarted at 1, so the
        // build number is lifted clear of the old line rather than colliding
        // with it - the same pattern Retro-Dosbox uses over its Java
        // predecessor.
        versionCode = SPECTRUM_VERSION_CODE_BASE + flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystoreConfig != null) {
                storeFile = file(keystoreConfig.path)
                storePassword = keystoreConfig.storePassword
                keyAlias = keystoreConfig.keyAlias
                keyPassword = keystoreConfig.keyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystoreConfig != null) {
                signingConfigs.getByName("release")
            } else {
                // Fallback for dev/CI: sign with the debug key so
                // `flutter run --release` still works on a fresh tree.
                // A build that ships without the release keystore is wrong;
                // the warning above is the explicit signal.
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}