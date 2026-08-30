import 'package:get/get.dart';

import '../../models/library_summary.dart';
import '../../sdk/api_call.dart';
import '../../models/ApiException.dart';
import '../../sdk/netease_api.dart';

/// 首页推荐 + 我的页三个 tab 的 API 集中仓库。
///
/// 原先散落在 HomeController（personalized）和
/// LibraryController（user_playlist / album_sublist / user_follow_mixed）里，
/// 这里只负责调 API + 解析 + 返回强类型列表。
///
/// - **不做** RxList / isLoading / error 写回 —— 这些是业务流程，留在 controller。
class LibraryRepository extends GetxService {
  final NeteaseApi _api;

  LibraryRepository(this._api);

  /// 首页推荐歌单。
  ///
  /// API: /personalized?limit=30
  /// 返回空列表：API 失败 / result 字段缺失。
  Future<List<PlaylistCard>> fetchPersonalized() async {
    try {
      final r = await apiCall(
        () => _api.raw.personalized(limit: '30'),
        what: '推荐歌单',
      );
      final list = r.body['result'];
      if (list is! List) return [];
      return list
          .whereType<Map>()
          .map(
            (m) => PlaylistCard.fromNeteaseJson(
              Map<String, dynamic>.from(m),
            ),
          )
          .toList();
    } on ApiException {
      return [];
    }
  }

  /// 我的歌单（含自建 + 收藏）。
  ///
  /// API: /user/playlist?uid=X&limit=50
  /// 返回空列表：API 失败 / playlist 字段缺失。
  Future<List<PlaylistSummary>> fetchPlaylists(String uid) async {
    try {
      final r = await apiCall(
        () => _api.raw.user_playlist(uid, limit: '50'),
        what: '我的歌单',
      );
      final list = r.body['playlist'];
      if (list is! List) return [];
      return list
          .whereType<Map>()
          .map(
            (m) => PlaylistSummary.fromNeteaseJson(
              Map<String, dynamic>.from(m),
            ),
          )
          .toList();
    } on ApiException {
      return [];
    }
  }

  /// 订阅的专辑。
  ///
  /// API: /album/sublist?limit=50
  /// 返回空列表：API 失败 / data 字段缺失。
  Future<List<AlbumSummary>> fetchSubscribedAlbums(String uid) async {
    try {
      final r = await apiCall(
        () => _api.raw.album_sublist(limit: '50'),
        what: '我的订阅专辑',
      );
      final list = r.body['data'] is List
          ? r.body['data'] as List
          : (r.body is List ? r.body as List : const []);
      return list
          .whereType<Map>()
          .map(
            (m) => AlbumSummary.fromNeteaseJson(
              Map<String, dynamic>.from(m),
            ),
          )
          .toList();
    } on ApiException {
      return [];
    }
  }

  /// 关注的艺人。
  ///
  /// API: /user/follow/mixed?size=50&cursor=0&scene=1
  /// 返回空列表：API 失败 / data.records 字段缺失。
  Future<List<ArtistSummary>> fetchFollowedArtists(String uid) async {
    try {
      final r = await apiCall(
        () => _api.raw.user_follow_mixed(
          size: '50',
          cursor: '0',
          scene: '1',
        ),
        what: '我的关注艺人',
      );
      final data = r.body['data'];
      final list = data is Map ? (data['records'] ?? data['list']) : data;
      if (list is! List) return [];
      return list
          .whereType<Map>()
          .map((record) => record['artistInfo'])
          .whereType<Map>()
          .map(
            (m) => ArtistSummary.fromNeteaseJson(
              Map<String, dynamic>.from(m),
            ),
          )
          .toList();
    } on ApiException {
      return [];
    }
  }
}
