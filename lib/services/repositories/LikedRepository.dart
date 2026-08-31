import 'package:get/get.dart';

import '../../sdk/ApiCall.dart';
import '../../models/ApiException.dart';
import '../../sdk/NeteaseApi.dart';

/// "我收藏的专辑" repository —— 集中 album_sublist + album_sub 两个 API 调用
///
/// 把散落在 [LikedAlbumsService.loadFromServer] / [LikedAlbumsService.toggle]
/// 里的 `apiCall(() => api.raw.album_sublist(...))` / `album_sub(...)` 集中到这里。
///
/// - **不做** likedAlbumIds RxSet + 持久化 + 登录态联动 + snackbar 错误提示 —— 这些
///   是业务流程, 保留在 [LikedAlbumsService]。
/// - **只做**: 调 API + 解析 ids 字段。
class LikedRepository extends GetxService {
  final NeteaseApi _api;

  LikedRepository(this._api);

  /// 拉收藏的专辑 id 全量列表。
  ///
  /// API: `/album/sublist`, 响应:
  /// ```
  /// { data: [{ id, ... }, ...], hasMore: ... }
  /// ```
  /// (顶层 data, 跟 /artist/sublist 不同)
  ///
  /// 返回 null: API 失败。返回空 Set: 拉成功但无收藏 / data 字段缺失。
  Future<Set<String>?> fetchLikedAlbumIds() async {
    try {
      final r = await apiCall(() => _api.raw.album_sublist(), what: '拉收藏专辑');
      final list = r.body['data'];
      if (list is! List) return <String>{};
      return list
          .whereType<Map>()
          .map((m) => m['id']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toSet();
    } on ApiException {
      return null;
    }
  }

  /// 收藏 / 取消收藏一张专辑。
  ///
  /// API: `/album/sub?id=X&t=1|0`
  /// 抛 [ApiException] (调用方决定是否 snackbar)。
  Future<void> toggleAlbumSub(String albumId, bool next) async {
    await apiCall(
      () => _api.raw.album_sub(albumId, next ? '1' : '0'),
      what: next ? '收藏专辑' : '取消收藏',
    );
  }

  /// 拉收藏的歌单 id 全量列表。
  ///
  /// API: `/user/playlist?uid=X`, 响应:
  /// ```
  /// { playlist: [{ id, subscribed: bool, ... }, ...] }
  /// ```
  /// 只取 `subscribed == true` 的项 (用户自己创建的不算收藏)。
  ///
  /// 返回 null: API 失败。返回空 Set: 拉成功但无收藏 / playlist 字段缺失。
  Future<Set<String>?> fetchLikedPlaylistIds(String uid) async {
    try {
      final r = await apiCall(() => _api.raw.user_playlist(uid), what: '拉收藏歌单');
      final list = r.body['playlist'];
      if (list is! List) return <String>{};
      return list
          .whereType<Map>()
          .where((m) => m['subscribed'] == true)
          .map((m) => m['id']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toSet();
    } on ApiException {
      return null;
    }
  }

  /// 收藏 / 取消收藏一张歌单。
  ///
  /// API: `/playlist/subscribe?t=1|2&id=X` (t=1 收藏, t=2 取消)
  /// 抛 [ApiException] (调用方决定是否 snackbar)。
  Future<void> togglePlaylistSubscribe(String playlistId, bool next) async {
    await apiCall(
      () => _api.raw.playlist_subscribe(next ? '1' : '2', playlistId),
      what: next ? '收藏歌单' : '取消收藏',
    );
  }

  Future<Set<String>?> fetchLikedSongIds(String uid) async {
    try {
      final r = await apiCall(() => _api.raw.likelist(uid), what: '拉喜欢列表');
      final rawIds = r.body['ids'];
      if (rawIds is! List) return <String>{};
      return rawIds.whereType<int>().map((i) => i.toString()).toSet();
    } on ApiException {
      return null;
    }
  }

  /// 喜欢 / 取消喜欢一首歌曲。
  ///
  /// API: `/like?id=X&like=true|false`
  /// 抛 [ApiException] (调用方决定是否 snackbar)。
  Future<void> toggleLike(String songId, bool next) async {
    await apiCall(
      () => _api.raw.like(songId, like: next.toString()),
      what: next ? '喜欢歌曲' : '取消喜欢',
    );
  }

  /// 拉关注的艺人 id 全量列表。
  ///
  /// API: `/artist/sublist`, 响应:
  /// ```
  /// { artists: [{ id, ... }, ...] }
  /// ```
  /// (顶层 artists, 跟 /album/sublist 不同)
  ///
  /// 返回 null: API 失败。返回空 Set: 拉成功但无关注 / artists 字段缺失。
  Future<Set<String>?> fetchLikedArtistIds() async {
    try {
      final r = await apiCall(() => _api.raw.artist_sublist(), what: '拉关注艺人');
      final rawArtists = r.body['artists'];
      if (rawArtists is! List) return <String>{};
      return rawArtists
          .whereType<Map>()
          .map((m) => m['id']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toSet();
    } on ApiException {
      return null;
    }
  }

  /// 关注 / 取消关注一位艺人。
  ///
  /// API: `/artist/sub?id=X&t=1|0`
  /// 抛 [ApiException] (调用方决定是否 snackbar)。
  Future<void> toggleArtistSub(String artistId, bool next) async {
    await apiCall(
      () => _api.raw.artist_sub(artistId, next ? '1' : '0'),
      what: next ? '关注艺人' : '取消关注',
    );
  }

  /// 同步单个艺人的关注状态。
  ///
  /// API: `/artists?id=X`, 响应:
  /// ```
  /// { artist: { id, followed: bool, ... } }
  /// ```
  ///
  /// 返回 bool?: API 失败 → null; 成功 → artist.followed (缺则 null)。
  Future<bool?> fetchFollowed(String artistId) async {
    try {
      final r = await apiCall(
        () => _api.raw.artists(artistId),
        what: '同步艺人关注状态',
      );
      final raw = r.body['artist'];
      if (raw is! Map) return null;
      final m = Map<String, dynamic>.from(raw);
      final followed = m['followed'];
      if (followed is! bool) return null;
      return followed;
    } on ApiException {
      return null;
    }
  }
}
