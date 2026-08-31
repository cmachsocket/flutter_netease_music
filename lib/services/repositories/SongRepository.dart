import 'package:get/get.dart';

import '../../sdk/ApiCall.dart';
import '../../models/ApiException.dart';
import '../../sdk/NeteaseApi.dart';

/// Song repository —— 集中歌曲相关 API 调用 + URL 字段提取
///
/// 把散落在 [PlayerController.loadSong] / [SearchController._enrichSongCovers]
/// 里的 `apiCall(() => api.raw.song_url(...))` / `song_detail(...)` + URL 字段
/// 解析集中到这里。
///
/// - **不做** http→https 转换 / 空 URL 判断 / snackbar 错误提示 —— 这些是
///   业务流程, 保留在调用方 (PlayerController / SearchController)。
/// - **只做**: 调 API + 提取原始字段。
class SongRepository extends GetxService {
  final NeteaseApi _api;

  SongRepository(this._api);

  /// 拉取歌曲的临时 mp3 直链。
  ///
  /// API: `/song/url?id=X&br=YYY`, 响应:
  /// ```
  /// { data: [{ id, url, ... }, ...] }
  /// ```
  /// 取 `data[0].url` 字段。
  ///
  /// 返回 null: API 失败 / data 数组为空 / 第一项 url 缺失。
  Future<String?> fetchSongUrl(String songId, {String br = '128000'}) async {
    try {
      final r = await apiCall(
        () => _api.raw.song_url(songId, br: br),
        what: '取播放 URL',
      );
      final data = r.body['data'];
      if (data is! List || data.isEmpty) return null;
      final first = data.first;
      if (first is! Map) return null;
      return (first['url'] as String?)?.toString();
    } on ApiException {
      return null;
    }
  }

  /// 单曲封面补图: 批量调 /song/detail 拿真 coverUrl
  ///
  /// API: `/song/detail?ids=id1,id2,...`, 响应:
  /// ```
  /// { songs: [{ id, al: { picUrl }, ... }, ...] }
  /// ```
  ///
  /// 返回 `Map<songId, picUrl>` (只含 picUrl 非空的项)。
  /// 由调用方 (SearchController) 负责把 coverUrl 回填到 Song 对象。
  Future<Map<String, String>> fetchSongDetails(List<String> songIds) async {
    if (songIds.isEmpty) return {};
    try {
      final ids = songIds.join(',');
      final r = await apiCall(() => _api.raw.song_detail(ids), what: '补单曲封面');
      final songs = r.body['songs'];
      if (songs is! List) return {};
      final byId = <String, String>{};
      for (final raw in songs) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        final sid = m['id']?.toString();
        if (sid == null) continue;
        final al = m['al'] ?? m['album'];
        if (al is! Map) continue;
        final picUrl = (Map<String, dynamic>.from(al)['picUrl'] ?? '')
            .toString();
        if (picUrl.isNotEmpty) byId[sid] = picUrl;
      }
      return byId;
    } on ApiException {
      return {};
    }
  }
}
