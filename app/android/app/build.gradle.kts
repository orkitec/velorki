import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The upload key, when android/key.properties names it (release.yml writes
// both from secrets). Without it a release build is signed with the debug key,
// so `flutter run --release` still works; Play refuses such a build.
val uploadKey = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

android {
    namespace = "com.orkitec.velorki"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // A test build beside the store's, whose Play signing a local build
        // cannot match: with ORG_GRADLE_PROJECT_velorkiDevBuild=true it is
        // com.orkitec.velorki.dev, "Velorki Dev". Never on CI: a CI build
        // asking for it fails, so a release can only be the store's id.
        val devBuild = project.findProperty("velorkiDevBuild") == "true"
        if (devBuild && System.getenv("CI") == "true") {
            throw GradleException("velorkiDevBuild is for local test builds only, never on CI")
        }
        applicationId = if (devBuild) "com.orkitec.velorki.dev" else "com.orkitec.velorki"
        manifestPlaceholders["appLabel"] = if (devBuild) "Velorki Dev" else "Velorki"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Raised from Flutter's default: drift/sqlite3, MapLibre and the
        // foreground-service location type all expect API 26+.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (uploadKey.containsKey("storeFile")) {
            create("upload") {
                storeFile = file(uploadKey.getProperty("storeFile"))
                storePassword = uploadKey.getProperty("storePassword")
                keyAlias = uploadKey.getProperty("keyAlias")
                keyPassword = uploadKey.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("upload") ?: signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
