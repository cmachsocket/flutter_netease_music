//掌管登录凭证

import 'package:get/get.dart';
import '../models/AuthInfo.dart';
import '../sdk/netease_api.dart';
import '../models/ApiException.dart';

class AuthController extends GetxController {
  final Rx<AuthInfo> authInfo = AuthInfo.empty().obs;
  bool get loggedIn => authInfo.value.loggedIn;
  int get currentUid => authInfo.value.currentUid;
  final NeteaseApi _auth = Get.find<NeteaseApi>();

  /// 发送验证码
  ///
  /// - 调 [NeteaseApi.sendCaptcha]
  /// - 成功 → true
  /// - 失败 → false
  Future<bool> sendCode({
    required String phoneStr,
    required String countryCode,
  }) async {
    try {
      // 2026-08-25: 匿名访客 cookie (NMTID/NMSCVT) 由 [NeteaseApi.init] 启动阶段
      // 一次性拉 (已登录 / 已缓存不重拉), 这里不再调 applyAnonymousCookie 避免重复请求。
      await _auth.sendCaptcha(phone: phoneStr, ctcode: countryCode);
      return true;
    } on ApiException {
      return false;
    }
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
  Future<bool> login({
    required String phoneStr,
    required String codeStr,
    required String countryCode,
  }) async {
    try {
      // 1. 先建访客 session
      await _auth.applyAnonymousCookie();
      // 2. 再发登录请求(此时 SDK 全局 cookie map 已有 NMTID/NMSCVT)
      final r = await _auth.loginCellphone(
        phone: phoneStr,
        captcha: codeStr,
        countrycode: countryCode,
      );
      final cookies = _auth.applyLoginCookie(r);
      await loadAuthInfo();
      if (cookies == const {} ||
          authInfo.value.currentUid == 0 ||
          !authInfo.value.loggedIn) {
        authInfo.value = AuthInfo.empty();
        return false;
      }
      return true;
    } on ApiException {
      authInfo.value = AuthInfo.empty();
      return false;
    }
  }

  /// 退出登录,清理凭证
  ///
  bool logout() {
    _auth.logout();
    authInfo.value = AuthInfo.empty();
    return true;
  }

  //putAsync 的 init方法
  Future<void> loadAuthInfo() async {
    final cookies = await _auth.getCookiesByCheckLogin();
    if (cookies == const {}) {
      authInfo.value = AuthInfo.empty();
    }
    authInfo.update((val) {
      val?.cookie = cookies;
    });
    // 拉取并缓存 uid —— LibraryController 后续要调 /user/playlist 等
    final uid = await _auth.fetchCurrentUid();
    if (uid == 0) {
      authInfo.value = AuthInfo.empty();
    }
    authInfo.update((val) {
      val?.currentUid = uid;
      val?.loggedIn = true;
    });
  }
}
