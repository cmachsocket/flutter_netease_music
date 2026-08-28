import 'package:get/get.dart';

import '../sdk/api_exception.dart';
import '../sdk/netease_api.dart';

/// 被动歌词服务 —— 只提供"按 song id 取 lyric 字符串"的能力
///
/// 设计原则 (跟项目其他 service 一致):
/// - **不订阅任何 Rx**, 不持有 lyric 状态
/// - **不依赖具体 widget / controller / player**
/// - 缓存拉过的 lyric (按 songId) 避免切歌/重进 PlayPage 时重复打 API
/// - 谁需要 lyric 谁主动 await (典型用法见 [LyricsController])
///
/// API:
/// - `/lyric/new` (NCM): 返回 yrc (逐字) + lrc (普通) 两个字段
///   优先 lrc (flutter_lyric 只支持标准 LRC), fallback 到 yrc
/// - 两者都空 → 返回 null (UI 显示"暂无歌词")
class LyricsService extends GetxService {
  final NeteaseApi _api = Get.find<NeteaseApi>();
  final Map<String, String> _cache = {};

  /// 拉取 songId 的歌词 (优先 yrc, fallback lrc)。
  /// 拉失败 / 都空 → null。
  Future<String?> fetch(String songId) async {
    final cached = _cache[songId];
    if (cached != null) return cached;
    try {
      final r = await _api.call(
        (a) => a.lyric_new(songId),
        what: '取歌词',
      );
      final lrc = (r.body['lrc']?['lyric'] as String?)?.toString() ?? '';
      if (lrc.trim().isNotEmpty) {
        _cache[songId] = lrc;
        return lrc;
      }
      final yrc = (r.body['yrc']?['lyric'] as String?)?.toString() ?? '';
      if (yrc.trim().isEmpty) return null;
      _cache[songId] = yrc;
      return yrc;
    } on ApiException {
      return null;
    }
  }

  /// 清缓存 (e.g. 用户手动刷新歌词时)
  void invalidate([String? songId]) {
    if (songId == null) {
      _cache.clear();
    } else {
      _cache.remove(songId);
    }
  }
}
