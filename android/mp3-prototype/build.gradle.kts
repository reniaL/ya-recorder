plugins {
    id("com.android.application")
    id("kotlin-android")
}

android {
    namespace = "io.github.renial.ya_recorder.mp3prototype"
    compileSdk = 36

    defaultConfig {
        applicationId = "io.github.renial.ya_recorder.mp3prototype"
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "0.1"
        ndk { abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86_64") }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    // This experiment is not a distributable production application.
    buildTypes { release { isMinifyEnabled = false } }
}

kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }

dependencies {
    implementation(project(":mp3-encoder"))
    testImplementation("junit:junit:4.13.2")
}
