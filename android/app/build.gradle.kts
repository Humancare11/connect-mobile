import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: reads android/key.properties (gitignored — see
// https://flutter.dev/to/reference-keystore).
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

// A release build signed with the debug key is not a smaller-scope mistake —
// Play Console outright refuses to accept it ("You uploaded an APK/AAB signed
// in debug mode"), and if it were ever accepted it would mean shipping under
// a signing identity nobody deliberately controls. So unlike the old
// silent-fallback behaviour, a missing key.properties now fails the build —
// but only when a release variant is actually what's being built. The
// `buildTypes { release { ... } }` block below is configured by Gradle on
// every invocation (including plain `flutter run` in debug), so the check
// must be scoped to release tasks specifically or it would break debug
// builds on any machine without a keystore.
val requestedReleaseBuild = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}

// The one legitimate case that still needs the debug key for a release
// variant — a local `flutter run --release` performance-testing session on
// a machine with no keystore provisioned — must opt in explicitly, either
// with `flutter run --release -- -PallowDebugRelease=true` or by setting the
// ORG_GRADLE_PROJECT_allowDebugRelease=true environment variable. Never set
// this in CI or for anything that leaves your machine.
val allowDebugReleaseSigning =
    (project.findProperty("allowDebugRelease") as String?)
        ?.equals("true", ignoreCase = true) == true

android {
    namespace = "com.humancareconnect.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.humancareconnect.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = when {
                hasReleaseSigning -> signingConfigs.getByName("release")
                allowDebugReleaseSigning -> signingConfigs.getByName("debug")
                requestedReleaseBuild -> throw GradleException(
                    "Release build requested but android/key.properties is " +
                        "missing, so this would be signed with the debug " +
                        "key — Play Console rejects debug-signed uploads. " +
                        "Add android/key.properties with your upload " +
                        "keystore (see https://flutter.dev/to/reference-keystore), " +
                        "or, for local `flutter run --release` testing only, " +
                        "set -PallowDebugRelease=true or the " +
                        "ORG_GRADLE_PROJECT_allowDebugRelease=true env var."
                )
                // Not a release task (e.g. plain `flutter run`/`build apk --debug`)
                // — this build type is configured but its tasks won't run, so
                // any valid signing config is just a harmless placeholder.
                else -> signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

// There is a single `.env` asset (production config, see pubspec.yaml), and
// it is exactly what every build — including the production release — is meant
// to ship. Nothing to strip from the bundle.

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.appcompat:appcompat:1.7.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
