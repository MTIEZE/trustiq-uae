import java.util.Properties

// Signing details live outside the repository, in android/key.properties,
// which is gitignored. A keystore in a public repo is a keystore anyone can
// sign your app with.
val keystoreProperties = Properties()
val keystoreFile = rootProject.file("key.properties")
if (keystoreFile.exists()) {
    keystoreFile.inputStream().use { keystoreProperties.load(it) }
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "ae.trustiq.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Permanent once the app is published. Changing it later is a new app
        // on the store, not an update to this one.
        // Permanent. Play ties a listing to this string for the life of the
        // app: it cannot be changed after the first upload, and it is what
        // shows in the store URL. Chosen before anything was uploaded.
        applicationId = "ae.trustiq.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystoreFile.exists()) {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Deliberately left unsigned when there is no key.properties,
            // rather than falling back to the debug key as the Flutter
            // template does. A debug-signed release looks finished and is not:
            // it can never be uploaded to Play under that key, and every
            // tester holding one has to uninstall before a real build will
            // install over it. An unsigned build fails loudly instead, which
            // is the outcome you want on the day you forgot.
            if (keystoreFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }

            // R8 is deliberately off. It breaks by reflection, silently, at
            // launch, and there is no device here to find that out on. An
            // optimisation nobody can verify is not worth putting in front of
            // a beta tester. Turn it on the day somebody can run the result.
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
