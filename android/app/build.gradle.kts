import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Never sign production builds with the Android debug certificate.
val releaseProperties = Properties()
val releasePropertiesFile = rootProject.file("key.properties")
if (releasePropertiesFile.isFile) {
    releasePropertiesFile.inputStream().use { releaseProperties.load(it) }
}
val releaseSigningConfigured = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    .all { !releaseProperties.getProperty(it).isNullOrBlank() }

android {
    namespace = "pro.kaleert.nextlink"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "pro.kaleert.nextlink"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    packaging {
        jniLibs { useLegacyPackaging = true }
    }

    flavorDimensions += "distribution"
    productFlavors {
        create("original") { dimension = "distribution" }
        create("shadow") { dimension = "distribution" }
    }

    signingConfigs {
        if (releaseSigningConfigured) {
            create("production") {
                storeFile = rootProject.file(releaseProperties.getProperty("storeFile"))
                storePassword = releaseProperties.getProperty("storePassword")
                keyAlias = releaseProperties.getProperty("keyAlias")
                keyPassword = releaseProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (releaseSigningConfigured) {
                signingConfig = signingConfigs.getByName("production")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.3")
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    implementation(files("libs/t2swrapper.aar"))
}

flutter {
    source = "../.."
}

// Fail closed: a release task must never accidentally produce an unsigned APK.
// Debug builds and PR checks work without credentials.
gradle.taskGraph.whenReady {
    val releaseRequested = allTasks.any { task ->
        task.project == project && task.name.contains("Release", ignoreCase = true) &&
            (task.name.startsWith("assemble") || task.name.startsWith("bundle") || task.name.startsWith("package"))
    }
    if (releaseRequested && !releaseSigningConfigured) {
        throw GradleException(
            "Release signing is not configured. See docs/android-release.md and android/key.properties.example"
        )
    }
}
