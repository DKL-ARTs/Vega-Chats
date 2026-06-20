plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.vega.vega_chat"
    compileSdk = 34

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.vega.vega_chat"
        minSdk = flutter.minSdkVersion
        targetSdk = 34
        versionCode = flutter.versionCode()
        versionName = flutter.versionName()
    }

    buildTypes {
        debug {
            isMinifyEnabled = false
            isShrinkResources = false
        }
        release {
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    jvmToolchain(17)
}

flutter {
    source = "../.."
}
