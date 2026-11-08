import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// The phone's upload key (android/key.properties, written by release.yml), so
// Play sees one app signed by one key; without it the debug key, as for the
// phone.
val uploadKey = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

val WEAR_VERSION_CODE_OFFSET = 100_000

// The version comes from pubspec.yaml as the phone's does: the same name, and
// the build number N as 100000 + N. Play wants every version code of the app
// distinct, the phone's (N) and the F-Droid build's per-ABI ones (1000, 2000
// or 4000 + N) included; those stay under 100000 while N does. A release
// passes the number it computed as -PvelorkiBuildNumber, as the phone's gets
// --build-number.
val pubspecVersion = rootProject.file("../pubspec.yaml").readLines()
    .first { it.startsWith("version:") }
    .substringAfter(":").trim()
val buildNumber = (providers.gradleProperty("velorkiBuildNumber").orNull
    ?: pubspecVersion.substringAfter("+")).toInt()
require(buildNumber in 1 until WEAR_VERSION_CODE_OFFSET - 4000) {
    "build number $buildNumber would collide with the phone's version codes"
}

android {
    namespace = "com.orkitec.velorki.wear"
    compileSdk { version = release(37) { minorApiLevel = 0 } }

    defaultConfig {
        // The phone's id: Play takes a Wear OS app as the phone app's
        // companion only under the same package name.
        applicationId = "com.orkitec.velorki"
        minSdk = 30
        targetSdk = 36
        versionCode = WEAR_VERSION_CODE_OFFSET + buildNumber
        versionName = providers.gradleProperty("velorkiBuildName").orNull
            ?: pubspecVersion.substringBefore("+")
    }

    signingConfigs {
        if (uploadKey.containsKey("storeFile")) {
            create("upload") {
                storeFile = rootProject.file("app/" + uploadKey.getProperty("storeFile"))
                storePassword = uploadKey.getProperty("storePassword")
                keyAlias = uploadKey.getProperty("keyAlias")
                keyPassword = uploadKey.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
            signingConfig = signingConfigs.findByName("upload") ?: signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
    }

    // The phone and the watch are held to one file of example messages;
    // see WatchProtocolTest.
    sourceSets.getByName("test").resources.srcDir("../../test/fixtures/watch")

    testOptions {
        unitTests.isReturnDefaultValues = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2026.09.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material:material-icons-extended:1.7.8")
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.core:core-ktx:1.18.0")
    implementation("androidx.lifecycle:lifecycle-service:2.11.0")
    implementation("androidx.wear.compose:compose-material3:1.7.1")
    implementation("androidx.wear.compose:compose-foundation:1.7.1")
    implementation("androidx.wear:wear-ongoing:1.1.0")
    implementation("androidx.health:health-services-client:1.1.0")
    implementation("androidx.concurrent:concurrent-futures-ktx:1.3.0")
    // The version watch_connectivity puts on the phone.
    implementation("com.google.android.gms:play-services-wearable:19.0.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.11.0")

    debugImplementation("androidx.compose.ui:ui-tooling")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.11.0")
    testImplementation("org.json:json:20250517")
}
