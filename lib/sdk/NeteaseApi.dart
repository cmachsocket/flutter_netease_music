import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:musiclibrary/music_library.dart';

import 'ApiCall.dart';
import 'ApiClient.dart';

/// 全局网易云 API facade — 仓库层 / UI 层的入口
///
/// **职责**(2026-09 改造):
/// - 持有 [ApiClient] 单例引用,所有 SDK 操作经 RPC 发到 worker isolate
/// - 持有 [loggedIn] 等 UI 关心的状态 Rx
/// - 启动期负责拉匿名 cookie、灌回持久化 cookie(走 RPC)
///
/// **不再持有 [NeteaseCloudMusicApi] 实例**:SDK + cookie state + GetStorage 全部
/// 在 worker isolate 里(见 [ApiWorker])。这个类退化成纯 facade,主 isolate 只
/// 关心 RPC 结果。
///
/// **生命周期**:在 [main] 里先 `await ApiClient.instance.start()` 拉起 worker,
/// 再 `await initNeteaseApi()` 初始化 facade + 灌回 cookie。仓库层 / UI 层
/// 拿 `Get.find<NeteaseApi>()` 调 SDK 方法。
class NeteaseApi extends GetxService {
  static const _loggedInKey = 'netease_logged_in_v1';

  final ApiClient _client = ApiClient.instance;

  // region 登录流程 API

  /// 发送验证码。
  ///
  /// API: `/captcha/sent?phone=X&ctcode=Y`
  /// 抛 [ApiException] (调用方决定是否 snackbar)。
  Future<void> sendCaptcha({
    required String phone,
    String ctcode = '86',
  }) async {
    await apiCall(
      () => _client.callApi('captcha_sent', <Object?>[phone, ctcode]),
      what: '发送验证码',
    );
  }

  /// 登录 (走 captcha 验证码分支)。
  ///
  /// API: `/login/cellphone?phone=X&captcha=Y&countrycode=Z`
  /// 响应 raw 交给调用方处理 ([applyLoginCookie] 灌 Set-Cookie)。
  ///
  /// 抛 [ApiException] (调用方决定是否 snackbar)。
  Future<MusicResponse> loginCellphone({
    required String phone,
    required String captcha,
    String countrycode = '86',
  }) async {
    return apiCall(
      () => _client.callApi('login_cellphone', <Object?>[phone, captcha, countrycode]),
      what: '登录',
    );
  }

  // endregion

  /// 启动初始化:SDK 实例已在 worker 里(worker 自己创建 + 灌回持久化 cookie),
  /// 这里只负责触发"未登录且没匿名 cookie 时拉一次访客 cookie"。
  ///
  /// 必须在 `GetStorage.init()` 之后**且** [ApiClient.instance.start()] 之后调用。
  ///
  /// 2026-08-25: 未登录且本地也没保存访客 cookie 时,启动阶段主动拉一次
  /// `applyAnonymousCookie()` 拿 NMTID/NMSCVT 访客 session,避免后续 /captcha/sent
  /// / /login/cellphone 被云盾返 502 (裸 IP 风控)。仅调用一次,持久化进 GetStorage,
  /// 下次启动从 cache 读, 不重复请求。
  Future<void> init() async {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[NeteaseApi] init (worker-driven)');
    }
    final box = GetStorage();
    final loggedIn = box.read<bool>(_loggedInKey) ?? false;
    final savedAnon = box.read<Map>('netease_anon_cookie_v1');
    if (!loggedIn && (savedAnon == null || savedAnon.isEmpty)) {
      await _client.applyAnonymousCookie();
    }
  }

  /// 把登录响应的 Set-Cookie 持久化 + 灌进 SDK
  ///
  /// - 内部走 RPC:worker 端拿到响应后解析 cookie + `raw.set_cookie(...)` +
  ///   持久化到 GetStorage
  /// - 返回空 Map: 没拿到任何 cookie,不写入 SDK / GetStorage
  ///   (返回 `{}` 而不是 `const {}` —— 后者会被 dart 类型推断成 const empty
  ///   Map, 虽然这里使用没问题, 但避免调用方误判 `== const {}`)
  Future<Map<String, String>> applyLoginCookie(MusicResponse response) async {
    final cookies = await _client.applyLoginCookie(response);
    return cookies;
  }

  /// 拉取并缓存当前登录用户的 uid(/user/account)
  ///
  /// - 必须已登录(否则后端返 400)
  /// - 成功后写 [currentUid] + GetStorage,后续 [user_playlist] / [user_follows] 直接拿
  /// - 失败仅打日志,不抛 —— uid 拿不到只是 Library 页拿不到数据,登录态本身不受影响
  Future<int> fetchCurrentUid() async {
    try {
      final r = await apiCall(
        () => _client.callApi('user_account', const <Object?>[]),
        what: '获取当前用户 uid',
      );
      // 返回结构兼容两种常见形式:
      // - {account: {id: xxx}, profile: {...}}    (新版)
      // - {data: {account: {...}, profile: {...}}} (旧版)
      // - {id: xxx}                                (退化)
      dynamic data = r.body['data'] ?? r.body;
      int? uid;
      if (data is Map) {
        final account = data['account'];
        if (account is Map && account['id'] is int) {
          uid = account['id'] as int;
        }
        if (uid == null && data['id'] is int) {
          uid = data['id'] as int;
        }
      }
      if (uid == null || uid <= 0) {
        if (kDebugMode) {
          // ignore: avoid_print
          print(
            '[NeteaseApi] fetchCurrentUid: unexpected body shape ${r.body}',
          );
        }
        return 0;
      }
      //请保证修改
      GetStorage().write('netease_uid_v1', uid);
      return uid;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[NeteaseApi] fetchCurrentUid failed: $e');
      }
      return 0;
    }
  }

  /// 获取当前登录状态(走 RPC 调 /login/status 拿 Set-Cookie header 解析后的 cookie map)
  ///
  /// 抛 [ApiException] (HTTP 200 但业务 code 错, 例如已退出 / cookie 过期)。
  Future<Map<String, String>> getCookiesByCheckLogin() async {
    final r = await apiCall(
      () => _client.callApi('login_status', const <Object?>[]),
      what: '获取登录状态',
    );
    return _parseCookieString(r.cookies);
  }

  /// 退出登录:清 SDK cookie + 本地持久化(都走 RPC)
  Future<void> logout() async {
    await _client.logout();
  }

  /// 当前是否已登录(走 RPC 读 GetStorage flag)
  Future<bool> isLoggedIn() async => _client.isLoggedIn();

  /// 读 SDK 持久化的身份 cookie map(走 RPC)
  Future<Map<String, String>> getSavedAuthCookie() async =>
      _client.getSavedAuthCookie();

  /// 获取并应用**游客 cookie**(`/register/anonimous`)
  ///
  /// 用途:网易云对**裸 IP**(没任何 session cookie)的请求做风控,新 IP 直
  /// 接发 `login_cellphone` 会返 10004 + `phoneReuse` 重定向(参见 MUSICLIBRARY.md 6.2)。
  /// 先调一次 `register_anonimous` 拿到 NMTID / NMSCVT 等 session cookie 再
  /// 发登录请求,后端会把这次请求当成"已有会话的设备",避开云盾拦截。
  ///
  /// 走 RPC:worker 内部 register_anonimous + set_cookie + GetStorage 持久化。
  ///
  /// **失败处理**:内部走 try/catch,失败仅打日志不抛 —— 登录流程即使这一步挂了
  /// 也会继续尝试 captcha(回到老路径,最坏情况跟之前一样被云盾挡)
  Future<void> applyAnonymousCookie() async {
    await _client.applyAnonymousCookie();
  }

  /// 调 SDK 方法(仓库层闭包内部用)
  ///
  /// `method` SDK 方法名 (e.g. 'playlist_detail'),`params` 参数列表 (positional)
  Future<MusicResponse> callApi(String method, List<Object?> params) =>
      _client.callApi(method, params);

  /// 整个 app 退出时调用 — 关 worker
  @override
  void onClose() {
    _client.close();
    super.onClose();
  }

  /// 解析 `Set-Cookie` 字符串为 key/value map
  ///
  /// (主 isolate 端版本,给 [getCookiesByCheckLogin] 用——登录状态接口的 Set-Cookie
  /// 在 RPC 回主 isolate 后还需要这层解析才能 map 化。worker 端 [ApiWorker] 自己
  /// 内部也有同名实现负责 applyLoginCookie 流程,这里纯函数可独立放主 isolate)
  static Map<String, String> _parseCookieString(String s) {
    final result = <String, String>{};
    if (s.isEmpty) return result;
    for (final raw in s.split(',')) {
      final parts = raw.split(';');
      for (final p in parts) {
        final t = p.trim();
        final eq = t.indexOf('=');
        if (eq <= 0) continue;
        var key = t.substring(0, eq).trim();
        final value = t.substring(eq + 1).trim();
        key = key.replaceAll(RegExp(r'^[^A-Za-z0-9_]+'), '');
        key = key.replaceAll(RegExp(r'[^A-Za-z0-9_]+$'), '');
        if (key.isEmpty) continue;
        if (key[0].toUpperCase() != key[0]) continue;
        if (key.toLowerCase() == 'path' ||
            key.toLowerCase() == 'expires' ||
            key.toLowerCase() == 'httponly' ||
            key.toLowerCase() == 'samesite' ||
            key.toLowerCase() == 'max-age' ||
            key.toLowerCase() == 'domain' ||
            key.toLowerCase() == 'secure') {
          continue;
        }
        result[key] = value;
      }
    }
    return result;
  }
}

/// 一次性 init 入口(给 main.dart 用)
///
/// **调用顺序**(main.dart):
/// 1. `await GetStorage.init()`
/// 2. `await ApiClient.instance.start()` — 拉起 worker,SDK 在 worker 内创建
/// 3. `await initNeteaseApi()` — 创建 facade + 触发匿名 cookie 拉取
Future<void> initNeteaseApi() async {
  if (Get.isRegistered<NeteaseApi>()) return;
  Get.put<NeteaseApi>(NeteaseApi(), permanent: true);
  await Get.find<NeteaseApi>().init();
}