import 'package:get/get.dart';

import 'repositories/lyrics_repository.dart';

/// 被动歌词服务 —— 只提供"按 song id 取 lyric 字符串"的能力
///
/// 设计原则 (跟项目其他 service 一致):
/// - **不订阅任何 Rx**, 不持有 lyric 状态
/// - **不依赖具体 widget / controller / player**
/// - 缓存拉过的 lyric (按 songId) 避免切歌/重进 PlayPage 时重复打 API
/// - 谁需要 lyric 谁主动 await (典型用法见 [LyricsController])
///
/// API 调用 (`/lyric/new` + lrc/yrc 字段解析) 集中在 [LyricsRepository],
/// service 只保留缓存 + 解析失败兜底。
class LyricsService extends GetxService {
  final LyricsRepository _repo = Get.find<LyricsRepository>();
  final Map<String, String> _cache = {};

  /// 拉取 songId 的歌词 (优先 lrc, fallback yrc)。
  /// 拉失败 / 都空 → null。
  Future<String?> fetch(String songId) async {
    final cached = _cache[songId];
    if (cached != null) return cached;
    final lyric = await _repo.fetch(songId);
    if (lyric != null) {
      _cache[songId] = lyric;
    }
    return lyric;
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