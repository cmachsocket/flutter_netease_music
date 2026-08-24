package com.example.flutter_netease_music

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

/// 主 Activity (Flutter 标准)
/// 
/// 2026-08-24: override onCreate 在 super.onCreate 之后调
/// `window.setDecorFitsSystemWindows(true)`, 关闭 Android 15+ 默认 edge-to-edge 强制。
/// 
/// - 不调这个: Android 15+ (targetSdk 36) 会强制 edge-to-edge, Flutter UI 占满全屏,
///   系统状态栏/导航栏用透明背景覆盖在 Flutter UI 上 (看起来"全屏应用")。
/// - 调这个: 状态栏/导航栏保留系统自己的位置 + 默认颜色, Flutter UI 在它们下方绘制
///   (传统 Android 风格)。
/// 
/// 注意: 这个 API 在 API 30 (Android 11) + 才稳定。我们 compileSdk=37 / targetSdk=36,
/// minSdk=23 (Flutter 默认)。低于 API 30 设备会走 framework 的 deprecated path, 不影响。
/// 
/// 也试过 AndroidManifest 加 androidx.window.WindowOptOutEdgeToEdgeEnforcement meta-data,
/// 但项目没有 androidx.window:window 依赖, meta-data 不会被 framework 识别, 没用。
class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 关掉 edge-to-edge, 状态栏/导航栏保留系统自己位置
        window.setDecorFitsSystemWindows(true)
    }
}
