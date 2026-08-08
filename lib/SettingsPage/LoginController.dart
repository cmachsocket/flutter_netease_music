import 'dart:async';

import 'package:flutter/widgets.dart' show TextEditingController;
import 'package:get/get.dart';

/// 登录页 controller(手机 + 验证码)
///
/// - 输入框数据源统一走 [phoneController] / [codeController] + listener 同步到 RxString,
///   理由同 [SearchController.textController]:不显式绑 controller 的话清除/回填 TextField
///   没反应(因为 Flutter 复用 TextField 内部看不见的 TextEditingController state)
/// - 接 SDK 后:[sendCode] 调后端发送验证码接口;[login] 调后端登录接口 + 存 token
/// - 当前 stub:sendCode 只启动 60s 倒计时;login 直接 Get.back() 模拟登录成功
class LoginController extends GetxController {
  // 业务常量集中放这里(单一来源,View 也引用)
  static const int phoneLength = 11;
  static const int codeLength = 6;
  static const int countdownSeconds = 60;
  static const Duration tickInterval = Duration(seconds: 1);

  // 中国大陆手机号 / 6 位数字验证码
  static final RegExp _phonePattern = RegExp(r'^1\d{10}$');
  static final RegExp _codePattern = RegExp(r'^\d{6}$');

  final TextEditingController phoneController = TextEditingController();
  final TextEditingController codeController = TextEditingController();

  final RxString phone = ''.obs;
  final RxString code = ''.obs;

  /// 倒计时剩余秒数;>0 表示冷却中
  final RxInt countdown = 0.obs;

  Timer? _timer;

  @override
  void onInit() {
    super.onInit();
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
  bool get isCodeValid => _codePattern.hasMatch(code.value);

  /// "获取验证码"按钮可点的条件:手机号格式对 + 不在冷却中
  bool get canSendCode => isPhoneValid && countdown.value == 0;

  /// "登录"按钮可点的条件:手机号 + 验证码都格式对
  bool get canLogin => isPhoneValid && isCodeValid;

  /// 发送验证码(stub:只启动倒计时,不调 API)
  void sendCode() {
    if (!canSendCode) return;
    // TODO: 接 SDK 后调后端发送验证码接口

    countdown.value = countdownSeconds;
    _timer?.cancel();
    _timer = Timer.periodic(tickInterval, (_) {
      countdown.value--;
      if (countdown.value <= 0) {
        _timer?.cancel();
      }
    });
  }

  /// 登录(stub:直接 Get.back() 模拟登录成功)
  void login() {
    if (!canLogin) return;
    // TODO: 接 SDK 后调后端登录接口 + 存 token + Get.back()
    Get.back();
  }
}

/// 登录页 binding:跟 SearchPageBinding 同款
///
/// 由调用方在 Get.to(..., binding: LoginPageBinding()) 时按需注入
class LoginPageBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<LoginController>(() => LoginController());
  }
}