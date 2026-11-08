pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.4.0" apply false
}

include(":app")

// The Wear OS app (wear/README.md), only when one of its own tasks is asked
// for (`./gradlew :wear:bundleRelease`) or -PvelorkiWear=true (an IDE sync).
// `flutter build` runs unqualified tasks such as `bundleRelease`, which would
// otherwise build the watch app beside the phone's, and the F-Droid build
// never sees it.
if (gradle.startParameter.taskNames.any { it.startsWith(":wear:") } ||
    providers.gradleProperty("velorkiWear").orNull == "true"
) {
    include(":wear")
}
