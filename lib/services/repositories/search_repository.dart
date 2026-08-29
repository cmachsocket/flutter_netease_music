import 'package:get/get.dart';

import '../../models/Artist.dart';
import '../../models/Album.dart';
import '../../models/Song.dart';
import '../../sdk/api_call.dart';
import '../../models/ApiException.dart';
import '../../sdk/netease_api.dart';

/// Search type 参数(参考 netease_cloud_music_api /search 接口)
///
/// 只取这四个(用户限定):
/// - 1 单曲
/// - 10 专辑
/// - 100 艺人
/// - 1000 歌单
enum SearchType {
  song(1, 'songs', '单曲'),
  album(10, 'albums', '专辑'),
  artist(100, 'artists', '艺人'),
  playlist(1000, 'playlists', '歌单');

  const SearchType(this.typeId, this.resultKey, this.label);

  /// 对应网易云 search API 的 type 参数
  final int typeId;

  /// /search 响应 `result.<key>` 的 key
  final String resultKey;

  /// UI 显示标签(SegmentedButton 上用)
  final String label;
}

/// Search repository —— 集中 `/search` + 4 种 type 字段解析
///
/// 把散落在 [SearchController.search] + [_parseAndStore] 里的
/// `apiCall(() => api.raw.search(...))` + `result[type]key` 提取 +
/// `Song/Album/Artist/SearchPlaylistSummary` 解析集中到这里。
///
/// - **不做** RxList / isLoading / snackbar / 竞争处理 —— 这些是业务流程,
///   保留在 [SearchController]。
/// - **只做**: 调 API + 解析 + 返回强类型结果。
class SearchRepository extends GetxService {
  final NeteaseApi _api;

  SearchRepository(this._api);

  /// 拉搜索结果。返回 null: API 失败 / 响应结构缺失。
  ///
  /// API: `/search?keywords=X&type=Y&limit=Z`, 响应:
  /// ```
  /// { result: { songs|albums|artists|playlists: [...] } }
  /// ```
  /// 顶层 result 是 Map, 内部根据 type 走不同 key。
  Future<SearchResult?> search({
    required String keywords,
    required SearchType type,
    int limit = 30,
  }) async {
    try {
      final r = await apiCall(
        () => _api.raw.search(
          keywords,
          type: type.typeId.toString(),
          limit: limit.toString(),
        ),
        what: '搜索',
      );
      final result = r.body['result'];
      if (result is! Map) return null;
      final list = result[type.resultKey];
      if (list is! List) return null;
      final items = list.whereType<Map>().toList();
      switch (type) {
        case SearchType.song:
          return SearchResult(
            songs: items
                .map((m) => Song.fromNeteaseJson(Map<String, dynamic>.from(m)))
                .toList(),
          );
        case SearchType.album:
          return SearchResult(
            albums: items
                .map((m) => Album.fromNeteaseJson(Map<String, dynamic>.from(m)))
                .toList(),
          );
        case SearchType.artist:
          // 搜索接口的 artists[] 项是直接 artist(无 wrap),跟 /artists 接口不同
          return SearchResult(
            artists: items
                .map(
                  (m) => Artist.fromNeteaseJson(Map<String, dynamic>.from(m)),
                )
                .toList(),
          );
        case SearchType.playlist:
          return SearchResult(
            playlists: items
                .map(
                  (m) => SearchPlaylistSummary.fromNeteaseJson(
                    Map<String, dynamic>.from(m),
                  ),
                )
                .toList(),
          );
      }
    } on ApiException {
      return null;
    }
  }
}

/// 搜索结果 —— 4 种 type 各自一份 nullable List
///
/// 调用方根据 [SearchType] 读对应字段 (其他字段为 null)。
class SearchResult {
  final List<Song>? songs;
  final List<Album>? albums;
  final List<Artist>? artists;
  final List<SearchPlaylistSummary>? playlists;

  const SearchResult({this.songs, this.albums, this.artists, this.playlists});
}

/// 搜索结果里的歌单摘要(轻量,跟 LibraryController 的 PlaylistSummary
/// 字段有重合但来源不同 —— 搜索结果没有 userId 等 user-only 字段,放一起会污染)
class SearchPlaylistSummary {
  final String id;
  final String name;
  final String coverUrl;
  final int trackCount;
  final String creatorName;

  const SearchPlaylistSummary({
    required this.id,
    required this.name,
    required this.coverUrl,
    required this.trackCount,
    required this.creatorName,
  });

  /// 网易云 /search?type=1000 返回的 `result.playlists[]` 元素:
  /// - id, name, coverImgUrl, trackCount, creator.nickname
  factory SearchPlaylistSummary.fromNeteaseJson(Map<String, dynamic> json) {
    final creator = json['creator'] is Map
        ? Map<String, dynamic>.from(json['creator'] as Map)
        : null;
    return SearchPlaylistSummary(
      id: json['id'].toString(),
      name: (json['name'] ?? '').toString(),
      coverUrl: (json['coverImgUrl'] ?? '').toString(),
      trackCount: (json['trackCount'] as int?) ?? 0,
      creatorName: (creator?['nickname'] ?? '').toString(),
    );
  }
}
