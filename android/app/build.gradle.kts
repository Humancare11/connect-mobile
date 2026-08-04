import java.util.Base64
import java.util.Properties
import org.gradle.api.tasks.Copy

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

// ── Strip dev/UAT env files from the production release bundle ───────────
// flutter_dotenv needs .env, .env.uat, and .env.production all present at
// *build* time — main.dart picks the right one at runtime via
// dotenv.load(fileName: ...) based on --dart-define=APP_ENV — but pubspec.yaml
// has no concept of a conditional asset, so by default all three ship inside
// every APK/AAB, including production: the UAT backend URL and its OAuth
// client ID sit right next to the production ones as plaintext, inspectable
// by unzipping the artifact. This hook deletes the two production doesn't
// need, but only for an actual production release build — local/UAT builds
// are untouched.
//
// APP_ENV isn't visible here directly (it's a --dart-define, which Gradle
// doesn't otherwise see); it's read via the same "dart-defines" project
// property the Flutter Gradle plugin itself uses to forward --dart-define
// values through to the Dart compiler (see BaseFlutterTaskHelper.kt) — a
// long-standing, stable integration point, but still internal to Flutter's
// tooling. If a future Flutter upgrade ever renames it, this fails *open*
// (silently stops stripping) rather than failing the build, which is why
// the release checklist includes actually inspecting the built .aab's
// contents rather than trusting this hook blindly.
fun releaseAppEnv(): String? {
    val raw = project.findProperty("dart-defines")?.toString() ?: return null
    return raw.split(",")
        .asSequence()
        .mapNotNull { encoded ->
            runCatching {
                String(Base64.getDecoder().decode(encoded), Charsets.UTF_8)
            }.getOrNull()
        }
        .firstOrNull { it.startsWith("APP_ENV=") }
        ?.removePrefix("APP_ENV=")
}

// Flutter copies flutter_assets (which is where .env/.env.uat/.env.production
// land, per pubspec.yaml) into place via a task named copyFlutterAssets<Variant>
// — e.g. copyFlutterAssetsRelease for the release build type used by both
// `flutter build apk --release` and `flutter build appbundle --release`
// (there are no product flavors here, so "release" is the only release
// variant). That task runs after Android's own asset merge and before
// anything packages/signs the result, so hooking its doLast is the latest
// point that's still safe to delete from — stripping *after* signing would
// invalidate the bundle's signature and Play Console would reject the
// upload outright.
tasks.matching { it.name == "copyFlutterAssetsRelease" }.configureEach {
    doLast {
        if (releaseAppEnv() != "production") return@doLast

        val destinationDir = (this as? Copy)?.destinationDir
        if (destinationDir == null || !destinationDir.exists()) return@doLast

        val strippedNames = setOf(".env", ".env.uat")
        var strippedCount = 0

        destinationDir.walkTopDown()
            .filter { it.isFile && it.name in strippedNames }
            .forEach { file ->
                logger.lifecycle(
                    "[release-env] Removing ${file.name} from the production " +
                        "release bundle: ${file.path}"
                )
                file.delete()
                strippedCount++
            }

        if (strippedCount == 0) {
            logger.warn(
                "[release-env] Expected to strip .env/.env.uat from the " +
                    "production release bundle but found neither under " +
                    "$destinationDir — inspect the built .aab manually " +
                    "before uploading to Play Console."
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.appcompat:appcompat:1.7.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
