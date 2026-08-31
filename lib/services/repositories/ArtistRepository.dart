import 'package:get/get.dart';

import '../../models/Artist.dart';
import '../../models/Album.dart';
import '../../models/Song.dart';
import '../../sdk/ApiCall.dart';
import '../../models/ApiException.dart';
import '../../sdk/NeteaseApi.dart';

/// 艺人 repository —— 集中 `/artists` + `/artist/album` + `/artist/songs`
/// 三个 API 调用
///
/// 把散落在 [ArtistController.load] 里的三路并行 `apiCall` + 解析集中到这里。
///
/// - **不做** 并行编排 (Future.wait + safeRun) —— 这是业务流程,保留在
///   [ArtistController]。
/// - **只做**: 调 API + 解析 + 返回强类型结果。
class ArtistRepository extends GetxService {
  final NeteaseApi _api;

  ArtistRepository(this._api);

  /// 拉艺人元信息 + 关注状态。
  ///
  /// API: `/artists?id=X`, 响应:
  /// ```
  /// { artist: { id, name, picUrl, briefDesc, ...,
  ///             musicSize, albumSize, fansCount, followed } }
  /// ```
  /// (响应是 {artist:{...}, hotSongs:[...]} 外层包了 artist)
  ///
  /// 返回 null: API 失败 / artist 字段缺失。
  Future<ArtistInfo?> fetchArtist(String artistId) async {
    try {
      final r = await apiCall(() => _api.raw.artists(artistId), what: '拉艺人信息');
      final raw = r.body['artist'];
      if (raw is! Map) return null;
      final m = Map<String, dynamic>.from(raw);
      final followed = m['followed'];
      return ArtistInfo(
        artist: Artist.fromNeteaseJson(m),
        followed: followed is bool ? followed : null,
      );
    } on ApiException {
      return null;
    }
  }

  /// 拉艺人专辑列表。
  ///
  /// API: `/artist/album?id=X`, 响应:
  /// ```
  /// { hotAlbums: [{ id, name, picUrl, ... }, ...] }
  /// ```
  /// (顶层 hotAlbums 或 albums,两种字段名都见过,优先 hotAlbums)
  ///
  /// 返回空列表: API 失败 / 列表字段缺失。
  Future<List<Album>> fetchAlbums(String artistId) async {
    try {
      final r = await apiCall(
        () => _api.raw.artist_album(artistId),
        what: '拉艺人专辑',
      );
      final list = r.body['hotAlbums'] ?? r.body['albums'];
      if (list is! List) return [];
      return list
          .whereType<Map>()
          .map((m) => Album.fromNeteaseJson(Map<String, dynamic>.from(m)))
          .toList();
    } on ApiException {
      return [];
    }
  }

  /// 拉艺人所有歌曲。
  ///
  /// API: `/artist/songs?id=X&limit=Y`, 响应:
  /// ```
  /// { songs: [{ id, name, ar, al, dt, ... }, ...] }
  /// ```
  ///
  /// 返回空列表: API 失败 / songs 字段缺失。
  Future<List<Song>> fetchSongs(String artistId, {int limit = 50}) async {
    try {
      final r = await apiCall(
        () => _api.raw.artist_songs(artistId, limit: limit.toString()),
        what: '拉艺人歌曲',
      );
      final list = r.body['songs'];
      if (list is! List) return [];
      return list
          .whereType<Map>()
          .map((m) => Song.fromNeteaseJson(Map<String, dynamic>.from(m)))
          .toList();
    } on ApiException {
      return [];
    }
  }
}

/// 艺人元信息 + 关注状态
class ArtistInfo {
  final Artist artist;

  /// 后端返回的 `followed` 字段(true/false);null = 字段缺失
  final bool? followed;

  const ArtistInfo({required this.artist, this.followed});
}
