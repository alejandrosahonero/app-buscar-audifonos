import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firebase Crashlytics, applied only when the project has been connected to a
// Firebase project. `google-services.json` is downloaded from the Firebase
// console into `android/app/`.
//
// Conditional on purpose: the google-services plugin does not degrade when the
// file is missing, it fails the build. Making it unconditional would mean
// nobody can compile the app until they own a Firebase project. Without the
// file the app builds and runs exactly as before and simply does not report —
// `CrashReporter.initialize` catches the missing configuration.
val hasFirebase = file("google-services.json").exists()
if (hasFirebase) {
    apply(plugin = "com.google.gms.google-services")
    // Uploads the R8 mapping file on every release build, which is what makes
    // the Kotlin/Java half of a stack trace readable in the console. The Dart
    // half needs `flutter symbolize` — see CLAUDE.md.
    apply(plugin = "com.google.firebase.crashlytics")
}

// Upload keystore credentials. `key.properties` is git-ignored: create it from
// `key.properties.example`. When the file is missing (fresh clone, CI without
// secrets) the release build falls back to the debug signing config so
// `flutter build` still works locally.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasKeystore = keystorePropertiesFile.exists()
if (hasKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.alejandrosahonero.buscaraudifonos"

    // Pinned to 37: required by permission_handler 13 and
    // flutter_secure_storage 11. Do not lower it.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // CANNOT be changed after the first publication on Google Play.
        applicationId = "com.alejandrosahonero.buscaraudifonos"
        minSdk = 24
        // Play requires targeting a recent API every year (deadline is usually
        // 31 August). `flutter.targetSdkVersion` tracks the Flutter stable
        // default; pin it manually if you need a specific value.
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasKeystore) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

            // Code shrinking + resource shrinking: the single biggest win on
            // APK/AAB size. Keep proguard-rules.pro in sync with the plugins.
            // (PNG crunching is already enabled by default for release.)
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
        debug {
            // R8 off in debug: it costs build time and mangles stack traces,
            // which is exactly what you need readable while developing.
            isMinifyEnabled = false
        }
    }

    // No product flavors on purpose. A `dev` / `prod` split forced every single
    // command to carry `--flavor`, and a plain `flutter run` simply failed. The
    // one thing the split actually protected — never requesting production ad
    // units from a development build — is covered by `kReleaseMode` in
    // AppConfig.useProductionAds, which cannot be got wrong by forgetting a
    // command line argument. Do not reintroduce them.
    //
    // The visible name is declared straight in AndroidManifest.xml
    // (`android:label`), not as a manifest placeholder: there is no longer a
    // per-flavor value to inject.
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
