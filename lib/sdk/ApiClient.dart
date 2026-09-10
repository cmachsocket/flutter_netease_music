/// 主 isolate 侧的 SDK worker RPC 客户端
///
/// **目的**:把阻塞 FFI 的 [NeteaseCloudMusicApi] 隔离到 worker isolate,主 isolate
/// 通过 `SendPort` 发起 RPC。SDK 实例 + cookie state + GetStorage 全在 worker 端,
/// 主 isolate 不再卡。
///
/// **生命周期**:
/// - `main.dart` 启动期调 [start]:spawn worker,等 worker `ready` ack 后 resolve
/// - `NeteaseApi.onClose` 调 [close]:发 `shutdown` op,worker 收到后 `Isolate.exit()`
/// - 重入安全:`start` 幂等,多次调只 spawn 一次
///
/// **API 形态**:
/// - [callApi] 主路,仓库层闭包 `() => _api.callApi('xxx', [...])` 直接 await
/// - [applyLoginCookie] / [applyAnonymousCookie] / [logout] / [getSavedAuthCookie] /
///   [isLoggedIn] 专口,worker 端持有 GetStorage
///
/// **跨 isolate 数据**:走 `SendPort.send`,只能传 JSON-safe 值。
/// [MusicResponse] 走 `fromJsonString` 序列化;[ApiException] 只带
/// code/message/rawBody 三元组还原。
library;

import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:musiclibrary/music_library.dart';

import '../models/ApiException.dart';
import 'ApiWorker.dart';

/// 单例 (主 isolate 持一份)
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  SendPort? _workerPort;
  ReceivePort? _fromWorker;
  Isolate? _isolate;
  bool _starting = false;
  bool _started = false;

  /// next request id (主 isolate 单调递增)
  int _nextId = 0;
  final Map<int, Completer<Map<String, Object?>>> _pending = {};

  bool get isStarted => _started;

  /// Spawn worker + 等 ready ack
  ///
  /// 幂等:已 started 直接返回;并发 start 也只跑一次。
  Future<void> start() async {
    if (_started) return;
    if (_starting) {
      while (!_started) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      return;
    }
    _starting = true;

    // 单一 port 走完整握手 + 业务消息。
    // 协议:
    //   1. worker 启动后发 {id:-1, op:'ready', ok:true/false}
    //   2. 同 port 上,worker 再推一个 SendPort(业务用),主 isolate 接管
    //   3. 后续所有 RPC reply 都走这条通道
    final fromWorker = ReceivePort();
    _fromWorker = fromWorker;
    fromWorker.listen(_onWorkerMessage);

    final handshakeCompleter = Completer<void>();
    _handshakeCompleter = handshakeCompleter;

    final isolate = await Isolate.spawn<_WorkerSpawnArgs>(
      _workerEntryPoint,
      _WorkerSpawnArgs(
        replyPort: fromWorker.sendPort,
        libraryDirOverride: libraryDirOverride,
      ),
      debugName: 'NeteaseApiWorker',
    );
    _isolate = isolate;

    await handshakeCompleter.future;
    _handshakeCompleter = null;

    if (_workerPort == null) {
      throw ApiException(
        ApiException.localUnexpected,
        'worker 启动后未回传业务 sendPort',
      );
    }
    _started = true;
    _starting = false;
    if (kDebugMode) {
      // ignore: avoid_print
      print('[ApiClient] worker started');
    }
  }

  static Completer<void>? _handshakeCompleter;

  /// 测试钩子:覆盖 worker 端 SDK 解析 native library 的路径。
  /// flutter test 环境下 `Platform.resolvedExecutable` 指向 test runner 而非
  /// 真实 app bundle,SDK 找不到 .so;测试用这个字段直接指定路径。
  static String? libraryDirOverride;

  void _onWorkerMessage(dynamic msg) {
    if (msg is SendPort) {
      // worker 推过来的业务 sendPort
      _workerPort = msg;
      // 业务 sendPort 已到:resolve handshake(若还没 resolve)
      final h = _handshakeCompleter;
      if (h != null && !h.isCompleted) h.complete();
      return;
    }
    if (msg is! Map) return;
    final id = msg['id'];
    if (id is! int) return;
    // 启动握手消息
    if (id == -1 && msg['op'] == 'ready') {
      final h = _handshakeCompleter;
      if (h == null || h.isCompleted) return;
      if (msg['ok'] == true) {
        // 等 worker 紧接着推业务 sendPort 再 resolve
        return;
      }
      h.completeError(
        ApiException(
          ApiException.localUnexpected,
          'worker 启动失败: ${msg['error']}',
        ),
      );
      return;
    }
    // 业务 reply
    final pending = _pending.remove(id);
    if (pending == null) return;
    pending.complete(msg.cast<String, Object?>());
  }

  /// 通用 RPC 调用
  ///
  /// [op] 操作名 (见 [ApiWorker] _handler 表)
  /// [args] op 自带的参数字典
  ///
  /// 返回 worker 回传的 `data` 字段 (op-specific shape)
  Future<Object?> _rpc(String op, Map<String, Object?> args) async {
    final port = _workerPort;
    if (port == null) {
      throw ApiException(
        ApiException.localUnexpected,
        'ApiClient 未启动: 先调 ApiClient.instance.start()',
      );
    }
    final id = _nextId++;
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    port.send(<String, Object?>{'id': id, 'op': op, ...args});

    final reply = await completer.future;
    if (reply['ok'] == true) {
      return reply['data'];
    } else {
      final err = reply['error'];
      if (err is Map) {
        throw _decodeApiException(err);
      }
      throw ApiException(
        ApiException.localUnexpected,
        'worker 未知错误: $reply',
      );
    }
  }

  /// 调 SDK 方法
  ///
  /// [method] SDK 方法名 (e.g. 'playlist_detail')
  /// [params] 参数列表 (positional,worker 端 dispatcher 按位置解构)
  Future<MusicResponse> callApi(String method, List<Object?> params) async {
    final data = await _rpc('call', <String, Object?>{
      'method': method,
      'params': params,
    });
    if (data is! String) {
      throw ApiException(
        ApiException.localUnexpected,
        'callApi($method) 返回非字符串: $data',
      );
    }
    return MusicResponse.fromJsonString(data);
  }

  /// 把登录响应的 Set-Cookie 写入 SDK + GetStorage
  Future<Map<String, String>> applyLoginCookie(MusicResponse response) async {
    final data = await _rpc('applyLoginCookie', <String, Object?>{
      'response': response.toString(),
    });
    return _decodeCookieMap(data);
  }

  /// 拉取并应用游客 cookie (内部 SDK 调用 + 持久化)
  Future<bool> applyAnonymousCookie() async {
    final data = await _rpc('applyAnonymousCookie', const <String, Object?>{});
    return data is bool && data;
  }

  /// 退出登录:清 SDK cookie + GetStorage
  Future<void> logout() async {
    await _rpc('logout', const <String, Object?>{});
  }

  /// 读 GetStorage 持久化的身份 cookie map
  Future<Map<String, String>> getSavedAuthCookie() async {
    final data = await _rpc('getSavedAuthCookie', const <String, Object?>{});
    return _decodeCookieMap(data);
  }

  /// 读 GetStorage 持久化的 loggedIn flag
  Future<bool> isLoggedIn() async {
    final data = await _rpc('isLoggedIn', const <String, Object?>{});
    return data is bool && data;
  }

  /// 关闭 worker (发 shutdown op)
  Future<void> close() async {
    final isolate = _isolate;
    _isolate = null;
    _workerPort = null;
    _started = false;
    if (isolate != null) {
      try {
        isolate.kill(priority: Isolate.immediate);
      } catch (_) {}
    }
    _fromWorker?.close();
    _fromWorker = null;
    // 清掉未完成的 completer,避免泄漏
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.completeError(
          ApiException(
            ApiException.localUnexpected,
            'ApiClient 已关闭',
          ),
        );
      }
    }
    _pending.clear();
  }

  // ---- helpers ----

  Map<String, String> _decodeCookieMap(Object? data) {
    if (data is! Map) return <String, String>{};
    return <String, String>{
      for (final e in data.entries)
        e.key.toString(): (e.value ?? '').toString(),
    };
  }

  ApiException _decodeApiException(Map err) {
    return ApiException(
      err['code'] is int ? err['code'] as int : ApiException.localUnexpected,
      (err['message'] ?? '未知错误').toString(),
      rawBody: err['rawBody'] is Map
          ? (err['rawBody'] as Map).cast<String, dynamic>()
          : null,
    );
  }
}

/// worker entry point(从 [ApiClient.start] 调 [Isolate.spawn] 启动)
///
/// 单独放在 isolate spawn 时调用的函数,签名 `(T) => void`。
void _workerEntryPoint(_WorkerSpawnArgs args) {
  ApiWorker.entryPoint(args.replyPort, libraryDirOverride: args.libraryDirOverride);
}

/// Isolate.spawn 跨 isolate 传的对象 (Dart 静态字段是 per-isolate 的,不能靠
/// 主 isolate 设字段 worker 读—— 必须通过 spawn 参数传)。
class _WorkerSpawnArgs {
  final SendPort replyPort;
  final String? libraryDirOverride;
  const _WorkerSpawnArgs({required this.replyPort, this.libraryDirOverride});
}