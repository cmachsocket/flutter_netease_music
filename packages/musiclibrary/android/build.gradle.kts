// musiclibrary plugin (FFI) Android 端 build 脚本
//
// 职责:
//   1. 通过 NDK 编译 ncm_music_api.so (MusicLibrary 的网易云 API 共享库)
//   2. 通过 Maven prefab 引入 libcurl 给 native 端使用
//   3. 声明 plugin bundle 哪些 .so 给 Flutter 工具链打包进 APK
//
// 见: packages/musiclibrary/android/src/main/CMakeLists.txt

plugins {
    id("com.android.library")
}

android {
    namespace = "com.example.musiclibrary"
    compileSdk = 35

    // 跟随主 app 的 NDK 版本(/android/app/build.gradle.kts 已设 29.0.14206865)
    ndkVersion = "29.0.14206865"

    // 调用 plugin 自己的 CMakeLists.txt
    externalNativeBuild {
        cmake {
            path = file("src/main/CMakeLists.txt")
            version = "3.21.0"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        minSdk = 23
    }

    // NDK ABI 过滤:Flutter 现在主流是 arm64-v8a + x86_64 (emulator)
    // 其他 ABI 可以按需加
    // ndk { abiFilters += listOf("arm64-v8a", "x86_64") }
}

// ========== libcurl via Maven Prefab ==========
// AGP 8.0+ 默认 prefab=true,可以直接 find_package(CURL CONFIG) 拿到 .so + headers。
// Google 官方为 NDK 提供的 prefab 包:
//   group:    com.android.ndk.thirdparty
//   artifact: curl
//   repo:     https://dl.google.com/android/maven2/
// 该 AAR 内部 prefab.json 声明依赖 openssl,prefab 会自动传递导出。
dependencies {
    implementation("com.android.ndk.thirdparty:curl:7.85.0-beta-1")
}
