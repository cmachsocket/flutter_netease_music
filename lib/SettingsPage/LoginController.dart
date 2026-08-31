import 'dart:async';

import 'package:flutter/widgets.dart' show TextEditingController;
import 'package:get/get.dart';

import '../AppShell.dart';
import '../sdk/AuthController.dart';

/// 登录页 controller(手机 + 验证码)
///
/// - 输入框数据源统一走 [phoneController] / [codeController] + listener 同步到 RxString,
///   理由同 [SearchController.textController]:不显式绑 controller 的话清除/回填 TextField
///   没反应(因为 Flutter 复用 TextField 内部看不见的 TextEditingController state)
/// - **凭证管理**: [AuthController] 全局持有 [AuthInfo] (cookie + loggedIn + uid),
///   本 controller 只做 UI 状态 + 业务编排 (输入验证 / 倒计时 / snackbar)
///   真正的 SDK 调用 (`/captcha/sent` / `/login/cellphone` / `/login/status` / cookie
///   持久化) 都在 [AuthController]
///
/// 职责分层:
/// - **AuthController** (lib/controller/): 全局凭证持有者, 调 SDK 拿数据
/// - **LoginController** (本页): UI 状态 + 业务编排, 把请求转给 AuthController
/// - **NeteaseApi** (lib/sdk/): 底层 SDK 入口, 只被 AuthController 调
class LoginController extends GetxController {
  // 业务常量集中放这里(单一来源,View 也引用)
  static const int phoneLength = 11;

  /// 验证码输入框**上限**(防呆:避免用户输 100 位)
  ///
  /// **不假设验证码位数** —— 网易云后端会动态调整(见过 4/6/8 位),
  /// 前端不知道下次是几位,所以**只设上限不限下限**,位数交给后端决定。
  static const int codeMaxLength = 8;
  static const int countdownSeconds = 60;
  static const String countryCode = '86';
  static const Duration tickInterval = Duration(seconds: 1);

  // 中国大陆手机号 + 任意位数字验证码 (只验"非空 + 全数字",不验位数)
  static final RegExp _phonePattern = RegExp(r'^1\d{10}$');
  static final RegExp _codePattern = RegExp(r'^\d+$');

  final TextEditingController phoneController = TextEditingController();
  final TextEditingController codeController = TextEditingController();

  final RxString phone = ''.obs;
  final RxString code = ''.obs;

  /// 倒计时剩余秒数;>0 表示冷却中
  final RxInt countdown = 0.obs;

  /// 发送验证码 / 登录请求进行中(用于 UI loading)
  final RxBool isSendingCode = false.obs;
  final RxBool isLoggingIn = false.obs;

  Timer? _timer;

  /// 全局凭证持有者 —— 真正的 SDK 调用都走它。
  /// `permanent: true` 全局 controller, 启动时 main.dart 注册。
  late final AuthController _auth;

  @override
  void onInit() {
    super.onInit();
    _auth = Get.find<AuthController>();

    phoneController.addListener(_syncPhone);
    codeController.addListener(_syncCode);
  }

  @override
  void onClose() {
    phoneController.removeListener(_syncPhone);
    phoneController.dispose();
    codeController.removeListener(_syncCode);
    codeController.dispose();
    _timer?.cancel();
    super.onClose();
  }

  void _syncPhone() => phone.value = phoneController.text;
  void _syncCode() => code.value = codeController.text;

  bool get isPhoneValid => _phonePattern.hasMatch(phone.value);

  /// 验证码格式合法:非空 + 全数字(**不限位数**,后端会动态决定)
  bool get isCodeValid => _codePattern.hasMatch(code.value);

  /// "获取验证码"按钮可点的条件:手机号格式对 + 不在冷却中 + 不在请求中
  bool get canSendCode =>
      isPhoneValid && countdown.value == 0 && !isSendingCode.value;

  /// "登录"按钮可点的条件:手机号 + 验证码都格式对 + 不在请求中
  bool get canLogin => isPhoneValid && isCodeValid && !isLoggingIn.value;

  /// 登录态(从 [AuthController.authInfo] 转发)。
  /// 设置页 [SettingsPage] 直接读这个判断已登录。

  void _startCountdown() {
    countdown.value = countdownSeconds;
    _timer?.cancel();
    _timer = Timer.periodic(tickInterval, (_) {
      countdown.value--;
      if (countdown.value <= 0) {
        _timer?.cancel();
      }
    });
  }

  /// 发送验证码 —— 委托给 [AuthController.sendCode]
  ///
  /// - 成功 → 启动 60s 倒计时 (期间按钮置灰, 文案显示 "重新发送(60s)")
  /// - 失败 → 弹 SnackBar (具体错误在 [AuthController.sendCode] 内部已处理)
  void sendCode() async {
    if (!canSendCode) return;
    isSendingCode.value = true;
    try {
      final ok = await _auth.sendCode(
        phoneStr: phone.value,
        countryCode: countryCode,
      );
      if (ok) {
        _startCountdown();
      } else {
        Get.snackbar('发送失败', '请稍后重试', snackPosition: SnackPosition.BOTTOM);
      }
    } finally {
      isSendingCode.value = false;
    }
  }

  /// 登录 —— 委托给 [AuthController.login]
  ///
  /// - 成功 → 弹 "登录成功" SnackBar + 回到 Settings 页
  /// - 失败 → 弹 SnackBar 提示 (具体错误在 [AuthController.login] 内部已处理)
  void login() async {
    if (!canLogin) return;
    isLoggingIn.value = true;
    try {
      final ok = await _auth.login(
        phoneStr: phone.value,
        codeStr: code.value,
        countryCode: countryCode,
      );
      if (ok) {
        Get.snackbar(
          '登录成功',
          '已保存登录状态, 下次启动自动恢复',
          snackPosition: SnackPosition.BOTTOM,
        );
        Get.back(id: AppShell.shellNavigatorId);
      } else {
        Get.snackbar(
          '登录失败',
          '请检查手机号 / 验证码 (常见: 验证码错 / 风控要求扫码 / 频繁登录)',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } finally {
      isLoggingIn.value = false;
    }
  }

  /// 退出登录 —— 委托给 [AuthController.logout]
  ///
  /// SettingsPage 的 "已登录" 项点击退出时调这个。AuthController.logout
  /// 内部已清 SDK cookie + GetStorage + 持久化。
  bool logout() => _auth.logout();
}

/// 后面要全部重构snackbar提示，移动到view层，controller只负责业务逻辑。
