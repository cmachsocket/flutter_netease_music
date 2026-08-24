import 'dart:async';

import 'package:flutter/widgets.dart' show TextEditingController;
import 'package:musiclibrary/music_library.dart';
import 'package:get/get.dart';

import '../sdk/api_call.dart';
import '../sdk/api_exception.dart';
import '../sdk/netease_api.dart';

/// 登录页 controller(手机 + 验证码)
///
/// - 输入框数据源统一走 [phoneController] / [codeController] + listener 同步到 RxString,
///   理由同 [SearchController.textController]:不显式绑 controller 的话清除/回填 TextField
///   没反应(因为 Flutter 复用 TextField 内部看不见的 TextEditingController state)
/// - **接 SDK 后**:
///   - [sendCode] 调 `/captcha/sent` 发送验证码
///   - [login] 调 `/login/cellphone` 登录 + 提取 Set-Cookie + 持久化到 GetStorage
class LoginController extends GetxController {
  // 业务常量集中放这里(单一来源,View 也引用)
  static const int phoneLength = 11;
  static const int codeLength = 4;
  static const int countdownSeconds = 60;
  static const Duration tickInterval = Duration(seconds: 1);

  // 中国大陆手机号 / 6 位数字验证码
  static final RegExp _phonePattern = RegExp(r'^1\d{10}$');

  final TextEditingController phoneController = TextEditingController();
  final TextEditingController codeController = TextEditingController();

  final RxString phone = ''.obs;
  final RxString code = ''.obs;

  /// 倒计时剩余秒数;>0 表示冷却中
  final RxInt countdown = 0.obs;

  /// 发送验证码 / 登录请求进行中(用于 UI loading)
  final RxBool isSendingCode = false.obs;
  final RxBool isLoggingIn = false.obs;

  final NeteaseApi api = Get.find<NeteaseApi>();

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

  /// "获取验证码"按钮可点的条件:手机号格式对 + 不在冷却中 + 不在请求中
  bool get canSendCode =>
      isPhoneValid && countdown.value == 0 && !isSendingCode.value;

  /// "登录"按钮可点的条件:手机号 + 验证码都格式对 + 不在请求中
  bool get canLogin => isPhoneValid && !isLoggingIn.value;

  /// 发送验证码
  ///
  /// - 调 [NeteaseCloudMusicApi.captcha_sent]
  /// - 成功 → 启动 60s 倒计时(期间按钮置灰,文案显示 "重新发送(60s)")
  /// - 失败 → 弹 SnackBar 显示 [ApiException.message]
  void sendCode() async {
    if (!canSendCode) return;
    isSendingCode.value = true;
    final phoneStr = phone.value;
    try {
      // 2026-08-25: 匿名访客 cookie (NMTID/NMSCVT) 由 [NeteaseApi.init] 启动阶段
      // 一次性拉 (已登录 / 已缓存不重拉), 这里不再调 applyAnonymousCookie 避免重复请求。
      // 同步阻塞调用;SDK 文档里也说 compute 会跨 isolate 拿 native handle
      apiCall(
        () => api.raw.captcha_sent(phoneStr, ctcode: '86'),
        what: '发送验证码',
      );
      _startCountdown();
    } on ApiException catch (e) {
      Get.snackbar('发送失败', e.message, snackPosition: SnackPosition.BOTTOM);
    } finally {
      isSendingCode.value = false;
    }
  }

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

  /// 登录
  ///
  /// 流程:
  /// 1. 先调 [NeteaseApi.applyAnonymousCookie] —— 拿 `/register/anonimous`
  ///    的访客 session cookie(NMTID/NMSCVT),让后端把这次请求当成"已有会话
  ///    的设备",避开裸 IP 直连触发云盾 10004 + phoneReuse 重定向
  ///    (MUSICLIBRARY.md 6.2,2026-08-09 实测确认)
  /// 2. 调 [NeteaseCloudMusicApi.login_cellphone] (走 captcha 验证码分支)
  /// 3. 成功 → 把 Set-Cookie 灌进 SDK + 持久化 GetStorage + Get.back() 回到 Settings
  /// 4. 失败 → 弹 SnackBar(常见:验证码错 / 风控要求扫码 / 频繁登录)
  ///
  /// 注意:第 1 步失败不阻断第 2 步(applyAnonymousCookie 内部 try/catch),
  /// 最坏情况就是回到老路径被云盾挡。
  void login() async {
    if (!canLogin) return;
    isLoggingIn.value = true;
    final phoneStr = phone.value;
    final codeStr = code.value;
    try {
      // 1. 先建访客 session
      await api.applyAnonymousCookie();
      // 2. 再发登录请求(此时 SDK 全局 cookie map 已有 NMTID/NMSCVT)
      final r = await api.call(
        (a) => a.login_cellphone(phoneStr, captcha: codeStr, countrycode: '86'),
        what: '登录',
      );
      api.applyLoginCookie(r);
      // 拉取并缓存 uid —— LibraryController 后续要调 /user/playlist 等
      await api.fetchCurrentUid();
      Get.back();
      Get.snackbar(
        '登录成功',
        '已保存登录状态,下次启动自动恢复',
        snackPosition: SnackPosition.BOTTOM,
      );
    } on ApiException catch (e) {
      Get.snackbar(
        '登录失败 (code ${e.code})',
        e.message,
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      isLoggingIn.value = false;
    }
  }

  /// 退出登录(供本 controller 内调,SettingsPage 直接走 [NeteaseApi.logout])
  ///
  /// - 清 SDK cookie + GetStorage 持久化
  /// - SnackBar 提示
  void logout() {
    api.logout();
    Get.snackbar('已退出', '本地登录态已清除', snackPosition: SnackPosition.BOTTOM);
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
