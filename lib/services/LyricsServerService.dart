import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';

import '../models/Snapshot.dart' show PlayOrder;
import '../models/Song.dart';
import 'AudioPlayerWrapper.dart';
import 'repositories/LyricsRepository.dart';

/// 本地 HTTP 服务 —— 暴露当前播放状态给外部 lyric 客户端
///
/// 监听端口 `41830`,返回 `/local-asset/player` GET 端点。
/// 响应 schema 跟 YesPlayMusic 桌面 lyric 客户端约定一致(见 `templete.json`):
///
/// ```json
/// {
///   "success": true,
///   "data": {
///     "progress": 24.265941,          // 当前位置 (秒,float)
///     "playing": true,                // 是否在播放
///     "volume": 1,                    // 音量 0~1
///     "currentTrack": { ... },        // 当前歌曲(网易云 schema 字段尽量填,缺失留空)
///     "isLiked": true,                // 是否收藏
///     "repeatMode": "off" | "list" | "one",
///     "lyric": {
///       "lrc": "[00:00.000]...",
///       "tlyric": "",                 // 本项目不区分翻译歌词,固定空串
///       "romalrc": ""                 // 同上
///     }
///   }
/// }
/// ```
///
/// **生命周期**:通过 [startServer] 启动后阻塞 accept;失败 throw 让 main.dart
/// 走错误日志(默认端口冲突时退出,提示用户)。
///
/// **依赖**:`AudioPlayerService` (snapshot / lyric repo) 已通过 GetX 注册,本类
/// 只通过 `Get.find` 拿,**不在 onInit 之外阻塞构造**。
class LyricsServerService extends GetxService {
  HttpServer? _server;
  int get port => _server?.port ?? 41831;
  bool get isRunning => _server != null;

  /// 启动 HTTP server。await 完成表示 server 已 bind,后续 accept 异步跑。
  Future<void> startServer() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 41831);
    _server = server;
    // listen 一旦挂上 server 就开始 accept,不需要再 await
    server.listen(_handleRequest);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (request.method == 'GET' &&
          request.uri.path == '/local-asset/player') {
        await _respondPlayer(request);
      } else {
        await _respondError(request, 404, 'Not Found');
      }
    } catch (e, st) {
      // 不要让一个错误请求让整个 server 死掉;只 log + 返 500
      // ignore: avoid_print
      print('[LyricsServer] handler error: $e\n$st');
      try {
        await _respondError(request, 500, 'Internal Server Error');
      } catch (_) {}
    }
  }

  Future<void> _respondPlayer(HttpRequest request) async {
    final wrapper = Get.find<AudioPlayerService>();
    final snap = wrapper.snapshot.value;
    final song = snap.currentSong;

    // ---- lyric ----
    String lrc = '';
    if (song != null && song.id.isNotEmpty) {
      // LyricsRepository.fetch 已经做了 cache,重复调用不会触发 RPC
      try {
        lrc = await Get.find<LyricsRepository>().fetch(song.id) ?? '';
        lrc = _removeBeforeTimestamp(lrc);
      } catch (_) {
        lrc = '';
      }
    }

    // ---- 响应组装 ----
    final body = <String, Object?>{
      'success': true,
      'data': <String, Object?>{
        // 字段顺序按 YesPlayMusic client 期望从顶到下排列(让客户端提前 fail-fast)
        'progress': snap.position.inMilliseconds / 1000.0,
        'playing': snap.isPlaying,
        'volume': 1.0, // wrapper 不暴露音量,客户端不用,固定 1.0
        'currentTrack': _mapCurrentTrack(song),
        'isLiked': snap.isCurrentSongLiked,
        'repeatMode': _mapRepeatMode(snap.playOrder),
        'lyric': <String, Object?>{
          'lrc': lrc,
          'tlyric': '', // 本项目不区分翻译歌词
          'romalrc': '',
        },
      },
    };

    request.response.statusCode = 200;
    request.response.headers.contentType = ContentType.json;
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.write(jsonEncode(body));
    await request.response.close();
  }

  Future<void> _respondError(
    HttpRequest request,
    int code,
    String message,
  ) async {
    request.response.statusCode = code;
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode(<String, Object?>{'success': false, 'message': message}),
    );
    await request.response.close();
  }

  @override
  void onClose() {
    _server?.close(force: true);
    _server = null;
    super.onClose();
  }

  // ---- mapping helpers ----

  /// 把本地 `Song` 转 YesPlayMusic client 期望的 currentTrack 字段。
  /// 字段命名跟网易云官方 schema 对齐(`name` / `ar` / `al` / `dt` / `id`),
  /// 缺失字段给合理默认值(0 / '' / [] / null),不要编造数据。
  ///
  /// **只填 JS 客户端实际读的字段**(`progress` / `lrc` / `tlyric` / `playing`
  /// 不在 currentTrack 里,各自独立)。currentTrack 字段留给 YesPlayMusic 桌面
  /// 客户端自己用,本项目客户端不消费 —— 故采用"有则填无则删"原则,只映射
  /// `Song` 已有的字段,其他不构造。
  static Map<String, Object?> _mapCurrentTrack(Song? song) {
    if (song == null || song.id.isEmpty) {
      return <String, Object?>{};
    }
    // YesPlayMusic client 期望 `ar: [{id, name}]` + `al: {id, name, picUrl}`。
    // 本项目只有第一个艺人名/专辑名,把这两个结构补齐(无 id 时 id 字段缺省)。
    return <String, Object?>{
      'id': song.id,
      'name': song.title,
      'ar': <Map<String, Object?>>[
        if (song.artist.isNotEmpty)
          <String, Object?>{'id': song.artistId, 'name': song.artist},
      ],
      'al': <String, Object?>{
        'id': song.albumId,
        'name': song.album,
        if (song.coverUrl.isNotEmpty) 'picUrl': song.coverUrl,
      },
      'dt': song.duration.inMilliseconds,
      // 网易云 schema 的 song URL / bitrate / 各种业务字段本项目没有,不伪造。
      // 客户端读到缺失字段时回 fallback,不 crash。
    };
  }

  /// PlayOrder → YesPlayMusic client 约定的字符串
  static String _mapRepeatMode(PlayOrder order) {
    switch (order) {
      case PlayOrder.sequential:
        return 'off'; // 不循环 = 播完停(YesPlayMusic "off" = sequential)
      case PlayOrder.shuffle:
        return 'list'; // 列表循环(YesPlayMusic "list" ≈ 我们 shuffle 的"再洗一遍",差异不大)
      case PlayOrder.repeatOne:
        return 'one';
    }
  }

  static String _removeBeforeTimestamp(String text) {
    // 匹配 [数字:数字.数字]，例如 [00:42.492]
    final reg = RegExp(r'\[\d+:\d+\.\d+\]');
    final match = reg.firstMatch(text);

    // 没找到就原样返回，也可以改成 return ''
    if (match == null) return '';

    // 从时间戳开始保留
    return text.substring(match.start);
  }
}
