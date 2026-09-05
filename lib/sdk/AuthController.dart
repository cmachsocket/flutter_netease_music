//掌管登录凭证

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:get/get.dart';
import '../models/AuthInfo.dart';
import 'NeteaseApi.dart';
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
    } catch (_) {
      // 非 ApiException (e.g. PlatformException / 网络栈异常) 也兜底,
      // 否则会沿 LoginController.login 冒泡 → UI 看不到 snackbar 也不知道失败
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
  /// 3. 成功 → 把 Set-Cookie 灌进 SDK + 持久化 GetStorage + loadAuthInfo 补 uid
  /// 4. 失败 → 弹 SnackBar(常见:验证码错 / 风控要求扫码 / 频繁登录)
  ///
  /// 成功判定: 登录 API 返 cookie 非空 (即 [applyLoginCookie] 返回了身份 cookie)
  /// —— cookie 是登录态的最小充分条件, uid 拿不到只影响 Library 页拉数据,
  /// 不阻断登录本身 (见 [loadAuthInfo] 注释)。
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
      // 3. 灌 cookie + 持久化 GetStorage + 写 loggedInKey (applyLoginCookie 内)
      final cookies = _auth.applyLoginCookie(r);
      if (cookies.isEmpty) {
        // 没拿到身份 cookie: 视为登录失败 (后端响应里没 Set-Cookie, 多半
        // 是云盾拦截 / 风控重定向, 业务 code 200 但 cookie 缺失)
        authInfo.value = AuthInfo.empty();
        return false;
      }
      // 4. 补 uid + 从持久化读 cookie 同步到 Rx (供 UI 订阅)
      //    uid 拿不到不算失败 —— 不阻断登录态, 只在 Library 那边拉不到数据
      await loadAuthInfo();
      return authInfo.value.loggedIn;
    } on ApiException {
      authInfo.value = AuthInfo.empty();
      return false;
    } catch (_) {
      // 非 ApiException (e.g. PlatformException / FFI 异常 / 解析失败)
      // 也兜底返回 false + 清状态, 否则 LoginController.login 那边的 await
      // 会被 finally 之外的部分 (snackbar/back) 跳过, UI 看不到任何反馈。
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

  /// 加载当前登录态的 uid + cookie, 同步到 [authInfo] Rx
  ///
  /// - 登录态来源: SDK 自己写的 `_loggedInKey` (applyLoginCookie → true,
  ///   logout → false), 走 [NeteaseApi.isLoggedIn] 读, 单一真相源
  /// - cookie 来源: SDK 持久化的 `_cookieStorageKey`, 走 [NeteaseApi.getSavedAuthCookie]
  ///   (旧实现走 `getCookiesByCheckLogin` 调 `/login/status`, 那个接口不 Set-Cookie,
  ///   永远空 Map, 导致 cookies 永远 isEmpty, 登录态判定走偏)
  /// - uid 拿不到 (网络/格式问题) 不阻断登录 —— 只在 Library 那边拉不到数据
  ///
  /// 调用方:
  /// - [NeteaseApi.init] 启动时 (恢复已登录用户的 uid)
  /// - [login] 成功后补一次 (刚登录的 uid)
  Future<void> loadAuthInfo() async {
    // 1. 是否登录: SDK 自己写的 flag, 不靠接口响应
    final loggedIn = _auth.isLoggedIn();
    // 2. cookie: 从 SDK GetStorage 读 (applyLoginCookie 写入的)
    final cookies = _auth.getSavedAuthCookie();
    // 3. uid: 拉 /user/account (可能因网络/格式返回 0)
    //    fetchCurrentUid 内部 try/catch 不抛, 失败返 0
    final uid = await _auth.fetchCurrentUid();

    if (loggedIn && cookies.isNotEmpty) {
      authInfo.value = AuthInfo(
        cookie: cookies,
        currentUid: uid, // 可能为 0 —— 不算失败, Library 那边会退化
        loggedIn: true,
      );
    } else {
      // cookies/flag 不全: 不强制清空 (用户可能只是当前没网, 等下重试),
      // 也不硬写 loggedIn=true (旧实现的 bug, 会让"登录失败但 SDK 没清 cookie"
      // 的场景显示为已登录)。保留现有 Rx 内容, 由调用方根据业务决定 [logout]。
      if (kDebugMode) {
        // ignore: avoid_print
        print(
          '[AuthController] loadAuthInfo: not fully logged in '
          '(loggedIn=$loggedIn, cookies=${cookies.length}, uid=$uid), '
          'keeping previous authInfo',
        );
      }
    }
  }
}
