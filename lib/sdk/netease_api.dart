import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:musiclibrary/music_library.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import 'api_call.dart';

/// 全局网易云 API 单例 + cookie 持久化
///
/// - **持有** [NeteaseCloudMusicApi] 实例(同一进程内,所有 controller 共享)
/// - **持久化** cookie 到 GetStorage,启动时自动灌回 SDK
/// - **暴露** [loggedIn] 给 UI 反映登录态
///
/// **生命周期**:在 [main] 里 await `NeteaseApi.init()` 启动初始化;
/// 业务代码通过 `Get.find<NeteaseApi>()` 拿实例,或者直接 `NeteaseApi.instance`
/// 静态访问。
class NeteaseApi extends GetxService {
  static const _cookieStorageKey = 'netease_cookie_v1';
  static const _loggedInKey = 'netease_logged_in_v1';
  static const _anonCookieStorageKey = 'netease_anon_cookie_v1';
  static const _uidStorageKey = 'netease_uid_v1';

  /// 网易云 API 实例(同步阻塞 FFI)
  final NeteaseCloudMusicApi raw = NeteaseCloudMusicApi(
    libraryDir: _resolveLibraryDir(),
  );

  // region 登录流程 API

  /// 发送验证码。
  ///
  /// API: `/captcha/sent?phone=X&ctcode=Y`
  /// 抛 [ApiException] (调用方决定是否 snackbar)。
  Future<void> sendCaptcha({
    required String phone,
    String ctcode = '86',
  }) async {
    await apiCall(() => raw.captcha_sent(phone, ctcode: ctcode), what: '发送验证码');
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
      () => raw.login_cellphone(
        phone,
        captcha: captcha,
        countrycode: countrycode,
      ),
      what: '登录',
    );
  }

  // endregion
  /// 启动初始化:从 GetStorage 读 cookie + 登录标记灌进 SDK
  ///
  /// 必须在 `GetStorage.init()` 之后调用
  ///
  /// 2026-08-25: 未登录且本地也没保存访客 cookie 时,启动阶段主动拉一次
  /// `applyAnonymousCookie()` 拿 NMTID/NMSCVT 访客 session,避免后续 /captcha/sent
  /// / /login/cellphone 被云盾返 502 (裸 IP 风控)。仅调用一次,持久化进 GetStorage,
  /// 下次启动从 cache 读, 不重复请求。
  Future<void> init() async {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[NeteaseApi] libraryDir = $_libraryDirForLog');
    }
    final box = GetStorage();
    final loggedIn = box.read<bool>(_loggedInKey) ?? false;
    // 优先级:auth cookie > anonymous cookie > 空
    // auth(MUSIC_U 等)登录后才有,anonymous(NMTID/NMSCVT)是 register_anonimous
    // 拿到的访客会话;两者一般不会同时存在(auth 走了会覆盖 anonymous)
    final savedAuth = box.read<Map>(_cookieStorageKey);
    final savedAnon = box.read<Map>(_anonCookieStorageKey);
    final Map toApply = (savedAuth != null && savedAuth.isNotEmpty)
        ? savedAuth
        : (savedAnon != null && savedAnon.isNotEmpty ? savedAnon : const {});
    if (toApply.isNotEmpty) {
      final cookies = <String, String>{
        for (final e in toApply.entries) e.key.toString(): e.value.toString(),
      };
      raw.set_cookie(cookies);
    }
    // 未登录 且 本地没缓存 anonymous cookie: 主动拉一次,
    // 拿到 NMTID/NMSCVT 走后续风控路子 (applyAnonymousCookie 内部 try/catch,
    // 拉失败也不阻断启动, 退到老路径最坏被云盾挡)。
    if (!loggedIn && (savedAnon == null || savedAnon.isEmpty)) {
      await applyAnonymousCookie();
    }
  }

  /// 把登录响应里的 Set-Cookie 持久化 + 灌进 SDK
  ///
  /// - 解析 `headers['Set-Cookie']` 字符串(多 cookie 用逗号分隔)
  /// - 写到 GetStorage
  /// - 调用 [raw.set_cookie] 让后续请求带身份
  ///  - 返回 false: 没拿到任何 cookie,不写入 SDK / GetStorage
  Map<String, String> applyLoginCookie(MusicResponse response) {
    final cookies = parseCookieString(response.cookies);
    if (cookies.isEmpty) return const {};
    raw.set_cookie(cookies);
    final box = GetStorage();
    box.write(_cookieStorageKey, cookies);
    box.write(_loggedInKey, true);
    return cookies;
  }

  /// 拉取并缓存当前登录用户的 uid(/user/account)
  ///
  /// - 必须已登录(否则后端返 400)
  /// - 成功后写 [currentUid] + GetStorage,后续 [user_playlist] / [user_follows] 直接拿
  /// - 失败仅打日志,不抛 —— uid 拿不到只是 Library 页拿不到数据,登录态本身不受影响
  Future<int> fetchCurrentUid() async {
    try {
      final r = await apiCall(() => raw.user_account(), what: '获取当前用户 uid');
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

      GetStorage().write(_uidStorageKey, uid);
      return uid;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[NeteaseApi] fetchCurrentUid failed: $e');
      }
      return 0;
    }
  }

  /// 获取当前登录状态
  ///
  /// SDK: `/login/status` —— 调用此接口, 可获取登录状态 (含 profile / account 等)
  ///
  /// 只返回响应 header 里的 Set-Cookie 解析后的 cookie map。
  /// 调用方关心 cookie (e.g. 检查 cookie 是否过期 / 拼出身份 cookie)
  /// 直接拿返回 Map 即可。
  ///
  /// 抛 [ApiException] (HTTP 200 但业务 code 错, 例如已退出 / cookie 过期)。
  Future<Map<String, String>> getCookiesByCheckLogin() async {
    final r = await apiCall(() => raw.login_status(), what: '获取登录状态');
    return parseCookieString(r.cookies);
  }

  /// 对 `_loggedInKey = true/false`,必须update包裱！！！！
  /// 退出登录:清掉 SDK cookie + 本地持久化
  bool logout() {
    raw.set_cookie(const {});
    final box = GetStorage();
    box.remove(_cookieStorageKey);
    box.remove(_anonCookieStorageKey);
    box.remove(_uidStorageKey);
    box.write(_loggedInKey, false);
    return true;
  }

  /// 获取并应用**游客 cookie**(`/register/anonimous`)
  ///
  /// 用途:网易云对**裸 IP**(没任何 session cookie)的请求做风控,新 IP 直
  /// 接发 `login_cellphone` 会返 10004 + `phoneReuse` 重定向(参见 MUSICLIBRARY.md 6.2)。
  /// 先调一次 `register_anonimous` 拿到 NMTID / NMSCVT 等 session cookie 再
  /// 发登录请求,后端会把这次请求当成"已有会话的设备",避开云盾拦截。
  ///
  /// - 写入 SDK 全局 cookie map(不影响现有 _cookieStorageKey 的 auth cookie)
  /// - 持久化到 [GetStorage] 的 [\_anonCookieStorageKey] —— 启动时 [init] 会自动灌回
  /// - 不更新 [loggedIn]:游客态不算"已登录"
  ///
  /// **失败处理**:内部走 try/catch,失败仅打日志不抛 —— 登录流程即使这一步挂了
  /// 也会继续尝试 captcha(回到老路径,最坏情况跟之前一样被云盾挡)
  Future<void> applyAnonymousCookie() async {
    try {
      final r = await apiCall(() => raw.register_anonimous(), what: '游客登录');
      // 两个位置可能携带 cookie:
      // 1. Set-Cookie header(成功响应常见路径,parseCookieString 提取)
      // 2. body.cookie JSON 数组(["NMTID=...","NMSCVT=..."],失败响应也常见)
      final cookies = <String, String>{};
      cookies.addAll(parseCookieString(r.cookies));
      _mergeBodyCookies(r.body['cookie'], cookies);
      // 2026-08-25: 加诊断日志。网易云返 200 但 body 里可能没有 cookie 字段,
      // 静默 return 让上层以为成功了, 后续请求带不上 NMTID/NMSCVT 还是要被云盾返 502。
      // 启动阶段 print, 用户下次跑能在 logcat 里看到。
      if (cookies.isEmpty) {
        if (kDebugMode) {
          // ignore: avoid_print
          print(
            '[NeteaseApi] applyAnonymousCookie: register_anonimous 返 200 但没拿到 cookie '
            '(body.keys=${r.body.keys.toList()}, status=${r.status})',
          );
        }
        return;
      }
      raw.set_cookie(cookies);
      final box = GetStorage();
      box.write(_anonCookieStorageKey, cookies);
      if (kDebugMode) {
        // ignore: avoid_print
        print(
          '[NeteaseApi] applyAnonymousCookie OK: 拿到 ${cookies.keys.toList()}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[NeteaseApi] applyAnonymousCookie failed: $e');
      }
    }
  }

  /// 解析 body.cookie JSON 数组 → 写入目标 cookie map
  ///
  /// 数组元素形如 `"NMTID=00OW1vR7yv...; Max-Age=315360000; Expires=...; Path=/"`,
  /// 只取 `;` 分割的第一段作为 `key=value`,后续 Path/Expires 等属性丢弃。
  /// 已有 key 不覆盖(调用方传入的 cookies 优先,通常是 Set-Cookie 里更完整的版本)。
  static void _mergeBodyCookies(dynamic raw, Map<String, String> target) {
    if (raw is! List) return;
    for (final c in raw) {
      if (c is! String) continue;
      final first = c.split(';').first.trim();
      final eq = first.indexOf('=');
      if (eq <= 0) continue;
      final key = first.substring(0, eq).trim();
      final value = first.substring(eq + 1).trim();
      if (key.isEmpty) continue;
      target.putIfAbsent(key, () => value);
    }
  }

  /// 整个 app 退出时调用
  @override
  void onClose() {
    raw.dispose();
    super.onClose();
  }

  /// 解析 `Set-Cookie` 字符串为 key/value map
  ///
  /// 输入可能是:
  /// - `MUSIC_U=xxx; Path=/, __csrf=yyy; Path=/`(多个 cookie 用逗号分隔)
  /// - 多个值用 `;` 分隔属性,`=` 分隔键值对
  ///
  /// 只取 `key=value` 形式,丢弃 `Path`、`HttpOnly`、`Expires` 等属性
  static Map<String, String> parseCookieString(String s) {
    final result = <String, String>{};
    if (s.isEmpty) return result;
    // 按逗号分多个 cookie(每个 cookie 自己内部用分号)
    for (final raw in s.split(',')) {
      final parts = raw.split(';');
      for (final p in parts) {
        final t = p.trim();
        final eq = t.indexOf('=');
        if (eq <= 0) continue;
        var key = t.substring(0, eq).trim();
        final value = t.substring(eq + 1).trim();
        // 清洗 key 首尾非法字符(如 cookie 串里莫名出现的 '[')。
        key = key.replaceAll(RegExp(r'^[^A-Za-z0-9_]+'), '');
        key = key.replaceAll(RegExp(r'[^A-Za-z0-9_]+$'), '');
        // 跳过属性名(不含 = 或 key 看起来像属性)
        if (key.isEmpty) continue;
        // 大写开头的属性名(Expires/Path/HttpOnly 等)跳过
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

/// 解析 native library 路径(传给 [NeteaseCloudMusicApi(libraryDir:)])
///
/// Linux 桌面下:
/// - 可执行文件:`build/linux/x64/debug/bundle/flutter_netease_music`
/// - .so 位置:同一 bundle 下的 `lib/` 子目录
///   (由 `linux/CMakeLists.txt` 的 install step 复制,RPATH `"$ORIGIN/lib"` 自动找)
///
/// Windows / macOS 同理(`bundle/lib/`)。
/// Android / iOS 不需要(走各自平台的 native 库加载机制)。
String _resolveLibraryDir() {
  if (Platform.isAndroid || Platform.isIOS) {
    return ''; // SDK 走 jniLibs / Frameworks,不需要 libraryDir
  }
  // 桌面平台:从可执行文件位置推算 bundle/lib/
  final exe = Platform.resolvedExecutable;
  final exeDir = File(exe).parent.path;
  return '$exeDir${Platform.pathSeparator}lib';
}

/// 给 [init] 用的 debug 日志:打印当前解析到的 libraryDir
String get _libraryDirForLog => _resolveLibraryDir();

/// 一次性 init 入口(给 main.dart 用)
Future<void> initNeteaseApi() async {
  if (Get.isRegistered<NeteaseApi>()) return;
  Get.put<NeteaseApi>(NeteaseApi(), permanent: true);
  await Get.find<NeteaseApi>().init();
}

/// 便利别名:让 controller 直接 `await api.something(...)` 也行
extension NeteaseApiCall on NeteaseApi {
  /// [apiCall] 的便利别名 —— NeteaseApi.raw 调用
  ///
  /// ```dart
  /// final r = await api.call((a) => a.captcha_sent('138xxx'), what: '发送验证码');
  /// ```
  Future<MusicResponse> call(
    MusicResponse Function(NeteaseCloudMusicApi api) fn, {
    String? what,
  }) => apiCall(() => fn(raw), what: what);
}
