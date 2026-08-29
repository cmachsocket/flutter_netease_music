import 'package:get/get.dart';

import '../../models/Song.dart';
import '../../sdk/api_call.dart';
import '../../models/ApiException.dart';
import '../../sdk/netease_api.dart';

/// 专辑 repository —— 集中 `/album?id=X` 一个 API 调用
///
/// 把散落在 [SongListController._loadAlbum] 里的 `apiCall` + 元信息 + 曲目解析
/// 集中到这里。/album 响应同时含 album 项 + songs 数组,一次拿全,所以一个
/// fetch 就够。
///
/// - **不做** title/coverUrl/description 等 Rx 写回 —— 这些是业务状态,
///   保留在 [SongListController]。
/// - **只做**: 调 API + 解析 + 返回强类型结果。
class AlbumRepository extends GetxService {
  final NeteaseApi _api;

  AlbumRepository(this._api);

  /// 拉专辑内容(元信息 + 所有曲目)。
  ///
  /// API: `/album?id=X`, 响应:
  /// ```
  /// { album: { id, name, picUrl, description, ... },
  ///   songs: [{ id, name, ar, al, dt, ... }, ...] }
  /// ```
  ///
  /// 返回 null: API 失败。返回空数据: 成功但 album 字段缺失。
  Future<AlbumContent?> fetch(String albumId) async {
    try {
      final r = await apiCall(() => _api.raw.album(albumId), what: '拉专辑内容');
      final albumMap = r.body['album'];
      if (albumMap is! Map) return null;
      final a = Map<String, dynamic>.from(albumMap);
      final songsList = r.body['songs'];
      final songs = songsList is List
          ? songsList
                .whereType<Map>()
                .map((m) => Song.fromNeteaseJson(Map<String, dynamic>.from(m)))
                .toList()
          : <Song>[];
      return AlbumContent(
        name: (a['name'] ?? '').toString(),
        coverUrl: (a['picUrl'] ?? '').toString(),
        description: (a['description'] ?? '').toString(),
        songs: songs,
      );
    } on ApiException {
      return null;
    }
  }
}

/// 专辑内容 (name/coverUrl/description + 所有曲目)
class AlbumContent {
  final String name;
  final String coverUrl;
  final String description;
  final List<Song> songs;

  const AlbumContent({
    required this.name,
    required this.coverUrl,
    required this.description,
    required this.songs,
  });
}
