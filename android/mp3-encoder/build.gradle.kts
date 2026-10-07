plugins {
    id("com.android.library")
    id("kotlin-android")
}

val encoderSourceAssets by tasks.registering(Sync::class) {
    from(projectDir) {
        include("third_party/**", "src/main/cpp/**", "src/main/kotlin/**",
            "build.gradle.kts", "consumer-rules.pro", "src/main/AndroidManifest.xml")
        // AAPT expands assets ending in .gz; preserve the pinned bytes instead.
        rename { name -> if (name.endsWith(".tar.gz")) "$name.bin" else name }
    }
    into(layout.buildDirectory.dir("generated/encoder-source-assets/mp3-encoder"))
}

android {
    namespace = "io.github.renial.ya_recorder.mp3"
    compileSdk = 36
    ndkVersion = "28.2.13676358"
    defaultConfig {
        minSdk = 24
        consumerProguardFiles("consumer-rules.pro")
        ndk { abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86_64") }
        externalNativeBuild {
            cmake { arguments += "-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON" }
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }
    // Keep the complete source, project patch, JNI and build recipe with the .so.
    sourceSets.getByName("main").assets.srcDir(layout.buildDirectory.dir("generated/encoder-source-assets"))
}

tasks.named("preBuild").configure { dependsOn(encoderSourceAssets) }

kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }
