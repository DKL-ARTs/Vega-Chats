plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.vega.vega_chat"
    compileSdk = 35

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.vega.vega_chat"
        minSdk = flutter.minSdkVersion
        targetSdk = 34
        versionCode = flutter.hasProperty("versionCode") ? flutter.versionCode : flutter.versionCode()
        versionName = flutter.hasProperty("versionName") ? flutter.versionName : flutter.versionName()
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
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
