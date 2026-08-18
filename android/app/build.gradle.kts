plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.flutter_netease_music"
    compileSdk = flutter.compileSdkVersion

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
    // 注意: FlutterExtension.ndkVersion 是 val (SDK 里写死的 28.2.13676358),
    // 不能在 app 这边 override。
    // jni plugin 用 `ndkVersion flutter.ndkVersion` 会拿到 28.2。
    // 当前依赖 jni 的 path_provider_android 2.3.x 必须用 NDK 28.2。
    // 临时 fix: dependency_overrides 锁 path_provider_android 到 2.2.23 (不用 jni)。
}
