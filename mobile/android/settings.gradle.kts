pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("com.android.application") version "7.4.2"
    id("org.jetbrains.kotlin.android") version "1.9.22"
    id("dev.flutter.flutter-gradle-plugin") version "1.0.0"
}

include(":app")

rootProject.name = "vega_chat"
