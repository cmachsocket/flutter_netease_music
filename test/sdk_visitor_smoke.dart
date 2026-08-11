import 'package:musiclibrary/music_library.dart';

/// Smoke test:游客 cookie + login_cellphone 流程
///
/// 跑这个脚本前先确认 build/linux/x64/debug/bundle/lib/ 里有 libncm_music_api.so
/// 和 libengine.so(由 linux/CMakeLists.txt install step 复制)。
///
/// 跑法(项目根目录):
///   dart run tool/sdk_visitor_smoke.dart <手机号> <验证码>
///
/// 期望输出:
///   1. visitor 拿到 cookie(应有 NMTID/NMSCVT 等)
///   2. login_cellphone 返回 status=200 + body.code=200
///   3. 响应里 Set-Cookie 包含 MUSIC_U 和 __csrf
///
/// 跑之前请把 PHONE / CODE 改成真实值,或者走命令行参数。
void main(List<String> args) {
  const libraryDir =
      '/home/cmach_socket/projects/flutter_netease_music/build/linux/x64/debug/bundle/lib';
  final api = NeteaseCloudMusicApi(libraryDir: libraryDir);

  // 1. 拿游客 cookie
  print('=== step 1: register_anonimous ===');
  final v = api.register_anonimous();
  print('status=${v.status} body.code=${v.body['code']}');
  print('Set-Cookie header=${v.cookies}');
  print('body.cookie=${v.body['cookie']}');
  if (v.cookies.isEmpty && v.body['cookie'] == null) {
    print('!! 游客接口没返回 cookie,看看到底返回了什么:');
    print('headers=${v.headers}');
    print('body=${v.body}');
    api.dispose();
    return;
  }

  // 2. 把 visitor cookie 灌进 SDK(模拟 LoginController.applyAnonymousCookie)
  final visitorCookies = parseCookieHeader(v.cookies);
  visitorCookies.addAll(parseCookieBody(v.body['cookie']));
  print('解析出来的 visitor cookies: $visitorCookies');
  if (visitorCookies.isEmpty) {
    print('!! 解析后还是空的,流程结束');
    api.dispose();
    return;
  }
  api.set_cookie(visitorCookies);

  // 3. 带 visitor cookie 调 login_cellphone
  final phone = args.isNotEmpty ? args[0] : '13800138000';
  final code = args.length > 1 ? args[1] : '000000';
  print('\n=== step 2: login_cellphone(phone=$phone, captcha=$code) ===');
  final r = api.login_cellphone(phone, captcha: code, countrycode: '86');
  print('status=${r.status} body.code=${r.body['code']}');
  print('message=${r.body['message'] ?? r.body['msg']}');
  print('Set-Cookie header=${r.cookies}');
  print('body.cookie=${r.body['cookie']}');

  api.dispose();
}

/// Set-Cookie header 解析(对应 NeteaseApi.parseCookieString 的简化版)
Map<String, String> parseCookieHeader(String s) {
  final r = <String, String>{};
  if (s.isEmpty) return r;
  for (final raw in s.split(',')) {
    for (final p in raw.split(';')) {
      final t = p.trim();
      final eq = t.indexOf('=');
      if (eq <= 0) continue;
      final key = t.substring(0, eq).trim();
      final value = t.substring(eq + 1).trim();
      if (key.isEmpty) continue;
      // 跳过 Path/Expires 等大写开头属性
      if (key[0].toUpperCase() != key[0]) continue;
      final lower = key.toLowerCase();
      if (lower == 'path' ||
          lower == 'expires' ||
          lower == 'httponly' ||
          lower == 'samesite' ||
          lower == 'max-age' ||
          lower == 'domain' ||
          lower == 'secure') {
        continue;
      }
      r[key] = value;
    }
  }
  return r;
}

/// body.cookie JSON 数组解析(["NMTID=...; ...", "NMSCVT=...; ..."])
Map<String, String> parseCookieBody(dynamic raw) {
  final r = <String, String>{};
  if (raw is! List) return r;
  for (final c in raw) {
    if (c is! String) continue;
    final first = c.split(';').first.trim();
    final eq = first.indexOf('=');
    if (eq <= 0) continue;
    final key = first.substring(0, eq).trim();
    final value = first.substring(eq + 1).trim();
    if (key.isEmpty) continue;
    r.putIfAbsent(key, () => value);
  }
  return r;
}
