import 'package:get/get.dart';

import '../../sdk/api_call.dart';
import '../../models/ApiException.dart';
import '../../sdk/netease_api.dart';

/// Lyrics repository —— 集中歌词相关 API 调用
///
/// 把散落在 [LyricsService.fetch] 里的 `apiCall(() => api.raw.lyric_new(...))` +
/// lrc/yrc 字段解析集中到这里。
///
/// - **不持有** lyric 字符串缓存 —— 缓存逻辑保留在 LyricsService (业务层)
/// - **不持有** LyricController 实例 —— UI 状态由 LyricsService / LyricsPageController 管
/// - **只做**: 调 API + 解析 lrc/yrc 字段, 返回 String? (优先 lrc, fallback yrc)
class LyricsRepository extends GetxService {
  final NeteaseApi _api;

  LyricsRepository(this._api);

  /// 拉取 songId 的歌词 (优先 lrc, fallback yrc)。
  /// 拉失败 / 都空 → null。
  ///
  /// API: `/lyric/new` (NCM), 响应:
  /// ```
  /// { lrc: { lyric: "..." }, yrc: { lyric: "..." } }
  /// ```
  /// 优先 lrc (flutter_lyric 只支持标准 LRC), fallback yrc。
  Future<String?> _fetch(String songId) async {
    try {
      final r = await apiCall(() => _api.raw.lyric_new(songId), what: '取歌词');
      final lrc = (r.body['lrc']?['lyric'] as String?)?.toString() ?? '';
      if (lrc.trim().isNotEmpty) return lrc;
      final yrc = (r.body['yrc']?['lyric'] as String?)?.toString() ?? '';
      if (yrc.trim().isEmpty) return null;
      return yrc;
    } on ApiException {
      return null;
    }
  }

  final Map<String, String> _cache = {};

  /// 拉取 songId 的歌词 (优先 lrc, fallback yrc)。
  /// 拉失败 / 都空 → null。
  Future<String?> fetch(String songId) async {
    final cached = _cache[songId];
    if (cached != null) return cached;
    final lyric = await _fetch(songId);
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
