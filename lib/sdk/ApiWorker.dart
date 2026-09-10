/// SDK worker isolate
///
/// **职责**:在 worker isolate 内部
/// 1. 唯一创建 [NeteaseCloudMusicApi] 实例 (持有 cookie state)
/// 2. 维护 GetStorage (持久化 cookie / loggedIn flag / uid)
/// 3. 监听主 isolate 的 RPC 请求,调 SDK + 回传响应
///
/// **协议**:
/// - 主 → worker: `{id: int, op: String, ...op-specific}`
/// - worker → 主: `{id: int, ok: bool, data|error}`
///
/// **跨 isolate 数据**:走 `SendPort.send`,JSON-safe only。
/// [MusicResponse] 序列化: `jsonEncode(r)` ↔ `MusicResponse.fromJsonString`
/// [ApiException] 只带 code/message/rawBody 三元组。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:musiclibrary/music_library.dart';

import '../models/ApiException.dart';

/// 纯文件持久化 —— worker isolate 不能用 GetStorage (init 调
/// `WidgetsFlutterBinding.ensureInitialized()` 在 worker 抛 "UI actions are only
/// available on root isolate"),但仍要跟主 isolate 共用一份 cookie / loggedIn
/// / uid 持久化文件,绕过方式: 直接 `dart:io` 读写
/// `<app docs>/GetStorage.gs` 这份 JSON 文件。
///
/// **格式兼容**: GetStorage 的 `storage/io.dart` 把整个 container 序列化成单个
/// JSON object (`{key: value}`),文件随机读 + flush 时覆盖写。我们读
/// 整个文件、修改、回写,跟主 isolate 并发写可能丢字段 —— 但 GetStorage 内部
/// 是 random-access lock,严格说我们这个简化版会跟主 isolate 抢文件。考虑到
/// 应用场景(登录态变更稀少且都是同进程写),实际并发可忽略。
class _WorkerStorage {
  static const _fileName = 'GetStorage';

  /// GetStorage 在 desktop (Linux/macOS/Windows) 用 `getApplicationDocumentsDirectory()`
  /// 即 `~/Documents` 作为根。读这里。
  static File _file({bool backup = false}) {
    final docs = Platform.environment['HOME'] != null
        ? Directory(
            '${Platform.environment['HOME']}${Platform.pathSeparator}Documents',
          )
        : Directory.current;
    final ext = backup ? '.bak' : '.gs';
    return File('${docs.path}${Platform.pathSeparator}$_fileName$ext');
  }

  static Map<String, dynamic>? _cache;

  /// 同步读 cache (未加载时返回空 Map)。调用方应在 startup 期 await [reload]
  /// 先触发磁盘加载。
  static Map<String, dynamic> get _data {
    _cache ??= <String, dynamic>{};
    return _cache!;
  }

  static Future<Map<String, dynamic>> _read() async {
    if (_cache != null) return _cache!;
    final f = _file();
    if (!await f.exists()) {
      _cache = <String, dynamic>{};
      return _cache!;
    }
    try {
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) {
        _cache = <String, dynamic>{};
      } else {
        _cache =
            (jsonDecode(raw) as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
      }
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[WorkerStorage] read failed: $e');
      }
      _cache = <String, dynamic>{};
    }
    return _cache!;
  }

  static Future<void> _write() async {
    final map = _cache ?? <String, dynamic>{};
    final f = _file();
    try {
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode(map), flush: true);
      // 备份 (跟 GetStorage 的 _madeBackup 同步)
      await _file(backup: true).writeAsString(jsonEncode(map), flush: true);
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[WorkerStorage] write failed: $e');
      }
    }
  }

  /// 同步读 — 调用前先 await [reload] / [ensureLoaded] 触发磁盘加载。
  T? read<T>(String key) {
    return _data[key] as T?;
  }

  /// 同步写 + fire-and-forget flush 到磁盘
  void write(String key, Object value) {
    _data[key] = value;
    unawaited(_write());
  }

  /// 同步删 + fire-and-forget flush
  void remove(String key) {
    _data.remove(key);
    unawaited(_write());
  }

  /// 启动期:从磁盘加载 (必须先 await 才能 read/write)。
  static Future<void> reload() async {
    _cache = null;
    await _read();
  }
}

/// worker isolate 主入口
///
/// 接收主 isolate 的 reply port (发回响应用),建 SDK 实例,listen RPC。
/// 收到 `shutdown` op 后 `Isolate.exit()`。
class ApiWorker {
  ApiWorker._();

  static const _cookieStorageKey = 'netease_cookie_v1';
  static const _loggedInKey = 'netease_logged_in_v1';
  static const _anonCookieStorageKey = 'netease_anon_cookie_v1';

  static late NeteaseCloudMusicApi _raw;
  static late SendPort _replyPort;

  /// Isolate.spawn 入口
  static void entryPoint(
    SendPort replyPort, {
    String? libraryDirOverride,
  }) async {
    _replyPort = replyPort;
    try {
      // worker 用 _WorkerStorage 直接读 GetStorage 的文件,绕开
      // GetStorage.init() 内部的 WidgetsFlutterBinding.ensureInitialized()
      // (在 worker isolate 会抛 "UI actions are only available on root isolate")
      await _WorkerStorage.reload();
      final libDir = libraryDirOverride ?? _resolveLibraryDir();
      _raw = NeteaseCloudMusicApi(libraryDir: libDir);
      if (kDebugMode) {
        // ignore: avoid_print
        print('[ApiWorker] started, libraryDir=$libDir');
      }
      // 启动期灌回持久化 cookie (login 或 anon 哪个非空用哪个)
      await _restorePersistedCookie();
      // ack: 已就绪
      _replyPort.send(<String, Object?>{'id': -1, 'op': 'ready', 'ok': true});
      // 进入主循环:listen RPC
      final port = ReceivePort();
      _replyPort.send(port.sendPort); // 把 worker 的 receive port 给主 isolate
      port.listen((msg) async {
        if (msg is! Map) return;
        await _handle(msg.cast<String, Object?>());
      });
    } catch (e, st) {
      _replyPort.send(<String, Object?>{
        'id': -1,
        'op': 'ready',
        'ok': false,
        'error': {
          'code': ApiException.localUnexpected,
          'message': 'worker 启动失败: $e',
        },
      });
      if (kDebugMode) {
        // ignore: avoid_print
        print('[ApiWorker] startup failed: $e\n$st');
      }
    }
  }

  // ---- 主循环 dispatch ----

  static Future<void> _handle(Map<String, Object?> req) async {
    final id = req['id'];
    final op = req['op'];
    if (id is! int || op is! String) return;
    try {
      switch (op) {
        case 'call':
          final data = await _handleCall(req);
          _send(id, true, data: data);
          break;
        case 'applyLoginCookie':
          final data = await _handleApplyLoginCookie(req);
          _send(id, true, data: data);
          break;
        case 'applyAnonymousCookie':
          final data = await _handleApplyAnonymousCookie();
          _send(id, true, data: data);
          break;
        case 'logout':
          await _handleLogout();
          _send(id, true);
          break;
        case 'getSavedAuthCookie':
          _send(id, true, data: _handleGetSavedAuthCookie());
          break;
        case 'isLoggedIn':
          _send(id, true, data: _handleIsLoggedIn());
          break;
        case 'shutdown':
          _send(id, true);
          Isolate.exit();
        default:
          _send(
            id,
            false,
            error: <String, Object?>{
              'code': ApiException.localUnexpected,
              'message': '未知 op: $op',
            },
          );
      }
    } catch (e, st) {
      // ApiException: 还原结构
      if (e is ApiException) {
        _send(
          id,
          false,
          error: <String, Object?>{
            'code': e.code,
            'message': e.message,
            if (e.rawBody != null) 'rawBody': e.rawBody,
          },
        );
        return;
      }
      // 其他: 兜底
      _send(
        id,
        false,
        error: <String, Object?>{
          'code': ApiException.localUnexpected,
          'message': '$op 调用失败: $e',
        },
      );
      if (kDebugMode) {
        // ignore: avoid_print
        print('[ApiWorker] $op failed: $e\n$st');
      }
    }
  }

  static void _send(
    int id,
    bool ok, {
    Object? data,
    Map<String, Object?>? error,
  }) {
    _replyPort.send(<String, Object?>{
      'id': id,
      'ok': ok,
      if (data != null) 'data': data,
      if (error != null) 'error': error,
    });
  }

  // ---- op handlers ----

  /// 调 SDK 方法 (worker 内仍是阻塞 FFI)
  ///
  /// dispatcher 表按位置参数解构。每个 entry 接收 `List<Object?>`,
  /// 强转各位置成 SDK 方法期望的类型,调 SDK,序列化 `MusicResponse` 成
  /// JSON 字符串回主 isolate。
  static Future<String> _handleCall(Map<String, Object?> req) async {
    final method = req['method'];
    final params = req['params'];
    if (method is! String) {
      throw ApiException(ApiException.localUnexpected, 'call 缺 method');
    }
    if (params is! List) {
      throw ApiException(ApiException.localUnexpected, 'call 缺 params 列表');
    }
    final args = params.cast<Object?>();

    // 22 个 SDK 方法的 dispatcher — 按 SDK 原签名 (netease_cloud_music_api.dart) 解构
    switch (method) {
      case 'captcha_sent':
        // captcha_sent(String phone, {String ctcode = '86'})
        return _encode(
          _raw.captcha_sent(
            args[0]! as String,
            ctcode: (args.length > 1 ? args[1] : null) as String? ?? '86',
          ),
        );
      case 'login_cellphone':
        // login_cellphone(String phone, {required String captcha, String countrycode = '86'})
        return _encode(
          _raw.login_cellphone(
            args[0]! as String,
            captcha: args[1]! as String,
            countrycode: (args.length > 2 ? args[2] : null) as String? ?? '86',
          ),
        );
      case 'register_anonimous':
        return _encode(_raw.register_anonimous());
      case 'user_account':
        return _encode(_raw.user_account());
      case 'login_status':
        return _encode(_raw.login_status());
      case 'playlist_detail':
        return _encode(_raw.playlist_detail(args[0]! as String));
      case 'playlist_track_all':
        return _encode(_raw.playlist_track_all(args[0]! as String));
      case 'playlist_create':
        return _encode(_raw.playlist_create(args[0]! as String));
      case 'playlist_tracks':
        // playlist_tracks(String op, String pid, String tracks)
        //   tracks 是逗号分隔的歌曲 id 字符串 (SDK 内部直接拼 query)
        return _encode(
          _raw.playlist_tracks(
            args[0]! as String,
            args[1]! as String,
            args[2]! as String,
          ),
        );
      case 'playlist_delete':
        return _encode(_raw.playlist_delete(args[0]! as String));
      case 'playlist_subscribe':
        // playlist_subscribe(String t, String id)  (t: '1' 订阅, '2' 取消)
        return _encode(
          _raw.playlist_subscribe(args[0]! as String, args[1]! as String),
        );
      case 'album':
        return _encode(_raw.album(args[0]! as String));
      case 'album_sublist':
        // album_sublist({String limit = '50'})
        return _encode(
          _raw.album_sublist(
            limit: (args.isNotEmpty ? args[0] : null) as String? ?? '50',
          ),
        );
      case 'album_sub':
        // album_sub(String id, String t)
        return _encode(_raw.album_sub(args[0]! as String, args[1]! as String));
      case 'artists':
        return _encode(_raw.artists(args[0]! as String));
      case 'artist_sublist':
        return _encode(_raw.artist_sublist());
      case 'artist_sub':
        return _encode(_raw.artist_sub(args[0]! as String, args[1]! as String));
      case 'artist_album':
        return _encode(_raw.artist_album(args[0]! as String));
      case 'artist_songs':
        // artist_songs(String id, {String limit = '50'})
        return _encode(
          _raw.artist_songs(
            args[0]! as String,
            limit: (args.length > 1 ? args[1] : null) as String? ?? '50',
          ),
        );
      case 'likelist':
        return _encode(_raw.likelist(args[0]! as String));
      case 'like':
        // like(String id, {required String like})
        return _encode(_raw.like(args[0]! as String, like: args[1]! as String));
      case 'lyric_new':
        return _encode(_raw.lyric_new(args[0]! as String));
      case 'search':
        // search(String keywords, {String type = '1', String limit = '30'})
        return _encode(
          _raw.search(
            args[0]! as String,
            type: (args.length > 1 ? args[1] : null) as String? ?? '1',
            limit: (args.length > 2 ? args[2] : null) as String? ?? '30',
          ),
        );
      case 'song_url':
        // song_url(String id, {String br = '999000'})
        return _encode(
          _raw.song_url(
            args[0]! as String,
            br: (args.length > 1 ? args[1] : null) as String? ?? '999000',
          ),
        );
      case 'song_detail':
        return _encode(_raw.song_detail(args[0]! as String));
      case 'personalized':
        // personalized({String limit = '30'})
        return _encode(
          _raw.personalized(
            limit: (args.isNotEmpty ? args[0] : null) as String? ?? '30',
          ),
        );
      case 'user_playlist':
        // user_playlist(String uid, {String limit = '50'})
        return _encode(
          _raw.user_playlist(
            args[0]! as String,
            limit: (args.length > 1 ? args[1] : null) as String? ?? '50',
          ),
        );
      case 'user_follow_mixed':
        // user_follow_mixed({String size = '50', String cursor = '0', String scene = '1'})
        return _encode(
          _raw.user_follow_mixed(
            size: (args.isNotEmpty ? args[0] : null) as String? ?? '50',
            cursor: (args.length > 1 ? args[1] : null) as String? ?? '0',
            scene: (args.length > 2 ? args[2] : null) as String? ?? '1',
          ),
        );
      default:
        throw ApiException(ApiException.localUnexpected, '未知 SDK 方法: $method');
    }
  }

  /// 把登录响应的 cookie 写入 SDK + GetStorage
  static Future<Map<String, String>> _handleApplyLoginCookie(
    Map<String, Object?> req,
  ) async {
    final respStr = req['response'];
    if (respStr is! String) {
      throw ApiException(
        ApiException.localUnexpected,
        'applyLoginCookie 缺 response',
      );
    }
    final response = MusicResponse.fromJsonString(respStr);
    final cookies = _parseCookieString(response.cookies);
    if (cookies.isEmpty) return <String, String>{};
    _raw.set_cookie(cookies);
    _WorkerStorage().write(_cookieStorageKey, cookies);
    _WorkerStorage().write(_loggedInKey, true);
    return cookies;
  }

  /// 拉取并应用游客 cookie (内部 SDK 调用 + 持久化)
  ///
  /// 失败仅打日志不抛(原 [NeteaseApi.applyAnonymousCookie] 语义)
  static Future<bool> _handleApplyAnonymousCookie() async {
    try {
      final r = _raw.register_anonimous();
      final cookies = <String, String>{};
      cookies.addAll(_parseCookieString(r.cookies));
      _mergeBodyCookies(r.body['cookie'], cookies);
      if (cookies.isEmpty) {
        if (kDebugMode) {
          // ignore: avoid_print
          print(
            '[ApiWorker] applyAnonymousCookie: register_anonimous 返 200 但没拿到 cookie '
            '(body.keys=${r.body.keys.toList()}, status=${r.status})',
          );
        }
        return false;
      }
      _raw.set_cookie(cookies);
      _WorkerStorage().write(_anonCookieStorageKey, cookies);
      if (kDebugMode) {
        // ignore: avoid_print
        print('[ApiWorker] applyAnonymousCookie OK: ${cookies.keys.toList()}');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[ApiWorker] applyAnonymousCookie failed: $e');
      }
      return false;
    }
  }

  static Future<void> _handleLogout() async {
    _raw.set_cookie(const {});
    final box = _WorkerStorage();
    box.remove(_cookieStorageKey);
    box.remove(_anonCookieStorageKey);
    box.write(_loggedInKey, false);
  }

  static Map<String, String> _handleGetSavedAuthCookie() {
    final raw = _WorkerStorage().read<Map>(_cookieStorageKey);
    if (raw == null || raw.isEmpty) return <String, String>{};
    return <String, String>{
      for (final e in raw.entries) e.key.toString(): e.value.toString(),
    };
  }

  static bool _handleIsLoggedIn() {
    return _WorkerStorage().read<bool>(_loggedInKey) ?? false;
  }

  /// 启动期:从 _WorkerStorage 读 cookie 灌回 SDK
  static Future<void> _restorePersistedCookie() async {
    final box = _WorkerStorage();
    final savedAuth = box.read<Map>(_cookieStorageKey);
    final savedAnon = box.read<Map>(_anonCookieStorageKey);
    final Map toApply = (savedAuth != null && savedAuth.isNotEmpty)
        ? savedAuth
        : (savedAnon != null && savedAnon.isNotEmpty ? savedAnon : const {});
    if (toApply.isNotEmpty) {
      final cookies = <String, String>{
        for (final e in toApply.entries) e.key.toString(): e.value.toString(),
      };
      _raw.set_cookie(cookies);
    }
  }

  // ---- helpers ----

  /// [MusicResponse] → JSON 字符串(worker → 主 isolate)
  static String _encode(MusicResponse r) {
    return jsonEncode(<String, Object?>{
      'headers': r.headers,
      'body': r.body,
      'status': r.status,
    });
  }

  /// 解析 `Set-Cookie` 字符串(从原 [NeteaseApi.parseCookieString] 搬过来)
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

  /// 解析 body.cookie JSON 数组 → 写入目标 cookie map
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

  /// native library 路径(从原 [NeteaseApi._resolveLibraryDir] 搬过来)
  static String _resolveLibraryDir() {
    if (Platform.isAndroid || Platform.isIOS) {
      return '';
    }
    final exe = Platform.resolvedExecutable;
    final exeDir = File(exe).parent.path;
    return '$exeDir${Platform.pathSeparator}lib';
  }
}
