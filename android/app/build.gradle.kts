plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.flutter_netease_music"
    compileSdk = flutter.compileSdkVersion

    // 强制覆盖 Flutter SDK 写死的 ndkVersion=28.2.13676358,
    // 用系统里已有的 29.0.14206865(避免自动下载/无写权限)。
    ndkVersion = "29.0.14206865"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.flutter_netease_music"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // native build 不在这里做——交给 packages/musiclibrary/ plugin 的
    // android/build.gradle.kts + CMakeLists.txt 处理,Flutter 工具链会自动
    // 把 plugin 生成的 .so 打包进 APK。

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
    // Flutter SDK 内部的 ndkVersion val=28.2.13676358 在 android{} 块里通过
    // ndkVersion = "29.0.14206865" 显式 override。本地/CI 走 gradle.properties 里的
    // android.ndkVersion,SDK 自动下载对应版本(android.builder.sdkDownload=true)。
    // jni plugin (path_provider_android 2.3.x) 用 `ndkVersion flutter.ndkVersion`
    // 拿到的是 override 后的 29,不需降版本。
}
