import 'package:get/get.dart';

import '../../models/Song.dart';
import '../../sdk/api_call.dart';
import '../../models/ApiException.dart';
import '../../sdk/netease_api.dart';
import '../../models/Playlist.dart';

/// 歌单 repository —— 集中 `/playlist/detail` + `/playlist/track/all`
/// 两个 API 调用
///
/// 把散落在 [SongListController._loadPlaylist] 里的两个 `apiCall` + 元信息 +
/// 曲目解析集中到这里。
///
/// - **不做** title/coverUrl/description 等 Rx 写回 —— 这些是业务状态,
///   保留在 [SongListController]。
/// - **只做**: 调 API + 解析 + 返回强类型结果。
class PlaylistRepository extends GetxService {
  final NeteaseApi _api;

  PlaylistRepository(this._api);

  /// 拉歌单元信息(标题/封面/描述)。
  ///
  /// API: `/playlist/detail?id=X`, 响应:
  /// ```
  /// { playlist: { id, name, coverImgUrl, description, ... } }
  /// ```
  ///
  /// 返回 null: API 失败。返回空数据: 成功但 playlist 字段缺失。
  Future<PlaylistMeta?> fetchMeta(String playlistId) async {
    try {
      final r = await apiCall(
        () => _api.raw.playlist_detail(playlistId),
        what: '拉歌单详情',
      );
      final playlist = r.body['playlist'];
      if (playlist is! Map) return null;
      final p = Map<String, dynamic>.from(playlist);
      return PlaylistMeta(
        name: (p['name'] ?? '').toString(),
        coverUrl: (p['coverImgUrl'] ?? '').toString(),
        description: (p['description'] ?? '').toString(),
      );
    } on ApiException {
      return null;
    }
  }

  /// 拉歌单所有曲目。
  ///
  /// API: `/playlist/track/all?id=X`, 响应:
  /// ```
  /// { songs: [{ id, name, ar, al, dt, ... }, ...] }
  /// ```
  /// (track_all 而非 detail.tracks,后者只返前 1000 首)
  ///
  /// 返回空列表: API 失败 / songs 字段缺失。
  Future<List<Song>> fetchTracks(String playlistId) async {
    try {
      final r = await apiCall(
        () => _api.raw.playlist_track_all(playlistId),
        what: '拉歌单曲目',
      );
      final songsList = r.body['songs'];
      if (songsList is! List) return [];
      return songsList
          .whereType<Map>()
          .map((m) => Song.fromNeteaseJson(Map<String, dynamic>.from(m)))
          .toList();
    } on ApiException {
      return [];
    }
  }
}
