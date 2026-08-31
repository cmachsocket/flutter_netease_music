import 'package:get/get.dart';

import '../controller/AuthController.dart';
import '../models/ApiException.dart';
import 'repositories/liked_repository.dart';

/// 收藏类型。统一所有 liked 状态 (歌曲 / 专辑 / 艺人 / 歌单) 走同一个 service,
/// 按 type 分桶存。UI / controller 调 toggle(id, type) / isLiked(id, type)。
enum LikedType { song, album, artist, playlist }

/// 全局"我喜欢"服务 —— 合并之前的 LikedSongs/Albums/Artists/Playlists 4 个 service.
///
/// 设计要点:
///   - 单一 service, 4 个 RxSet 分桶 (likedSongIds / likedAlbumIds / ...)
///   - API 调用走 [LikedRepository] (按类型分方法,因为后端 API 各异)
///   - **不持久化**: 之前 4 个 service 各自写 GetStorage key (liked_songs_v1 etc.),
///     现在合并后不再写本地, 完全依赖 loadAll 从后端拉取
///     (之前的旧 key 保留在 GetStorage 里但永远不会再被读,等下次用户卸载/清缓存自然消失)
///   - toggle 走乐观更新 + 失败回滚 + snackbar, 跟之前 LikedCollectionService 基类一致
///   - artist 的 syncSingle 也收口到这里 (其他类型不需要单点同步)
class LikedService extends GetxService {
  final LikedRepository _repo = Get.find<LikedRepository>();
  final AuthController _auth = Get.find<AuthController>();

  // ---- 4 个分桶 ----------------------------------------------------------------

  final RxSet<String> likedSongIds = <String>{}.obs;
  final RxSet<String> likedAlbumIds = <String>{}.obs;
  final RxSet<String> likedArtistIds = <String>{}.obs;
  final RxSet<String> likedPlaylistIds = <String>{}.obs;

  // ---- 登录态联动 -------------------------------------------------------------

  Worker? _loggedInWorker;

  @override
  void onInit() {
    super.onInit();
    _loggedInWorker = ever(_auth.authInfo, (info) {
      if (info.loggedIn) {
        // ignore: discarded_futures
        loadAll();
      } else {
        _clearAll();
      }
    });
    if (_auth.loggedIn) {
      // ignore: discarded_futures
      loadAll();
    }
  }

  @override
  void onClose() {
    _loggedInWorker?.dispose();
    super.onClose();
  }

  void _clearAll() {
    likedSongIds.clear();
    likedAlbumIds.clear();
    likedArtistIds.clear();
    likedPlaylistIds.clear();
  }

  // ---- 查询 (Obx 跟踪) ---------------------------------------------------------

  /// 调用方**必须包 Obx**才能响应对应 likedXxxIds 变化
  /// (RxSet.contains 走内部 _value 不跟踪,这里返回 .value.contains 触发 Obx)
  bool isLiked(String id, LikedType type) {
    switch (type) {
      case LikedType.song:
        // ignore: invalid_use_of_protected_member
        return likedSongIds.value.contains(id);
      case LikedType.album:
        // ignore: invalid_use_of_protected_member
        return likedAlbumIds.value.contains(id);
      case LikedType.artist:
        // ignore: invalid_use_of_protected_member
        return likedArtistIds.value.contains(id);
      case LikedType.playlist:
        // ignore: invalid_use_of_protected_member
        return likedPlaylistIds.value.contains(id);
    }
  }

  // ---- 全量拉取 ---------------------------------------------------------------

  /// 登录后一次性拉所有类型的 liked id (歌曲 / 专辑 / 艺人 / 歌单)
  /// 内部 4 个 API 并发 (拉失败的不阻塞,跟之前各 service loadFromServer 的"静默"行为一致)
  Future<void> loadAll() async {
    if (!_auth.loggedIn) return;
    final uid = _auth.currentUid.toString();

    // songs + albums + artists + playlists 4 个并发拉
    final results = await Future.wait([
      _repo.fetchLikedSongIds(uid),
      _repo.fetchLikedAlbumIds(),
      _repo.fetchLikedArtistIds(),
      _repo.fetchLikedPlaylistIds(uid),
    ]);

    final songs = results[0];
    final albums = results[1];
    final artists = results[2];
    final playlists = results[3];

    if (songs != null) likedSongIds.assignAll(songs);
    if (albums != null) likedAlbumIds.assignAll(albums);
    if (artists != null) likedArtistIds.assignAll(artists);
    if (playlists != null) likedPlaylistIds.assignAll(playlists);
  }

  // ---- toggle (乐观更新 + 失败回滚 + snackbar) -------------------------------

  /// toggle 收藏 (乐观更新 + 失败回滚 + snackbar)
  ///
  /// 对应类型的 RxSet 立刻 add/remove, 后端 API 失败时回滚并 snackbar 报错
  Future<void> toggle(String id, LikedType type) async {
    final bucket = _bucket(type);
    final wasLiked = bucket.contains(id);
    final next = !wasLiked;
    if (next) {
      bucket.add(id);
    } else {
      bucket.remove(id);
    }
    try {
      await _toggleApi(id, next, type);
    } on ApiException {
      if (next) {
        bucket.remove(id);
      } else {
        bucket.add(id);
      }
    }
  }

  Future<void> _toggleApi(String id, bool next, LikedType type) {
    switch (type) {
      case LikedType.song:
        return _repo.toggleLike(id, next);
      case LikedType.album:
        return _repo.toggleAlbumSub(id, next);
      case LikedType.artist:
        return _repo.toggleArtistSub(id, next);
      case LikedType.playlist:
        return _repo.togglePlaylistSubscribe(id, next);
    }
  }

  RxSet<String> _bucket(LikedType type) {
    switch (type) {
      case LikedType.song:
        return likedSongIds;
      case LikedType.album:
        return likedAlbumIds;
      case LikedType.artist:
        return likedArtistIds;
      case LikedType.playlist:
        return likedPlaylistIds;
    }
  }

  // ---- artist 单点同步 --------------------------------------------------------

  /// 同步单个艺人的关注状态 (跟之前的 LikedArtistsService.syncSingle 同语义)
  ///
  /// 业务: LibraryPage 关注艺人列表 card 首次 build 时调一次
  /// (loadAll 拉 /artist/sublist 全量,单点 id 不在里面)
  Future<void> syncArtistLike(String artistId) async {
    final followed = await _repo.fetchFollowed(artistId);
    if (followed == null) return; // 静默
    final alreadyIn = likedArtistIds.contains(artistId);
    if (followed == alreadyIn) return;
    if (followed) {
      likedArtistIds.add(artistId);
    } else {
      likedArtistIds.remove(artistId);
    }
  }
}
