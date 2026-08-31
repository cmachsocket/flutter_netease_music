import 'package:flutter/material.dart' show IconData, Icons;
import 'package:get/get.dart';

import '../models/LibrarySummary.dart';
import '../services/LikedController.dart';
import '../services/repositories/LibraryRepository.dart';
import '../sdk/AuthController.dart';

enum LibraryTab {
  playlists(1, '歌单', Icons.playlist_play),
  albums(2, '专辑', Icons.album),
  artists(3, '艺人', Icons.person);

  const LibraryTab(this.id, this.label, this.icon);

  /// 网易云后端的 tab id (供 SDK / 个人中心等接口引用)
  final int id;

  /// UI 显示文案
  final String label;
  final IconData icon;
}

/// Library 页 controller
///
/// 三个 tab 分别对应网易云"我的"：
/// - tab 1 (歌单): /user/playlist(uid)
/// - tab 2 (专辑): /album/sublist
/// - tab 3 (艺人): /user/follow/mixed(scene=1)
///
/// **未登录时**：不调接口，展示"请先登录"占位卡
class LibraryController extends GetxController {
  /// 当前 tab (默认歌单)
  ///
  /// **不用裸 int** —— enum 在编译期挡住 setTab(99) 这种垃圾值，
  /// switch 也带 exhaustiveness 检查（加新 tab 时漏一个 case 编译器报错）。
  final Rx<LibraryTab> tab = LibraryTab.playlists.obs;
  Worker? _loginWorker;

  final LibraryRepository _repo = Get.find<LibraryRepository>();
  final LikedController _likedService = Get.find<LikedController>();
  final AuthController _auth = Get.find<AuthController>();

  // tab 1: 歌单
  final RxBool playlistsLoading = false.obs;
  final RxnString playlistsError = RxnString();
  final RxList<PlaylistSummary> playlists = <PlaylistSummary>[].obs;

  // tab 2: 专辑
  final RxBool albumsLoading = false.obs;
  final RxnString albumsError = RxnString();
  final RxList<AlbumSummary> albums = <AlbumSummary>[].obs;

  // tab 3: 艺人
  final RxBool artistsLoading = false.obs;
  final RxnString artistsError = RxnString();
  final RxList<ArtistSummary> artists = <ArtistSummary>[].obs;

  @override
  void onInit() {
    super.onInit();
    _loginWorker = ever(_auth.authInfo, (info) {
      if (info.loggedIn) {
        _loadVisibleTab();
      }
    });
    if (_auth.loggedIn) {
      _loadVisibleTab();
    }
  }

  void setTab(LibraryTab t) {
    tab.value = t;
    // 切换时按需触发加载（只在未加载过且未在加载中时）
    _loadVisibleTab();
  }

  void _loadVisibleTab() {
    switch (tab.value) {
      case LibraryTab.playlists:
        if (playlists.isEmpty && !playlistsLoading.value) loadPlaylists();
        break;
      case LibraryTab.albums:
        if (albums.isEmpty && !albumsLoading.value) loadAlbums();
        break;
      case LibraryTab.artists:
        if (artists.isEmpty && !artistsLoading.value) loadArtists();
        break;
    }
  }

  Future<void> loadPlaylists() async {
    if (playlistsLoading.value) return;
    playlistsLoading.value = true;
    playlistsError.value = null;
    final uid = _auth.currentUid;
    if (uid == 0) {
      playlistsLoading.value = false;
      return;
    }
    final list = await _repo.fetchPlaylists(uid.toString());
    playlists.assignAll(list);
    playlistsLoading.value = false;
  }

  Future<void> loadAlbums() async {
    if (albumsLoading.value) return;
    albumsLoading.value = true;
    albumsError.value = null;
    final list = await _repo.fetchSubscribedAlbums(_auth.currentUid.toString());
    albums.assignAll(list);
    albumsLoading.value = false;
  }

  Future<void> loadArtists() async {
    if (artistsLoading.value) return;
    artistsLoading.value = true;
    artistsError.value = null;
    final list = await _repo.fetchFollowedArtists(_auth.currentUid.toString());
    artists.assignAll(list);
    artistsLoading.value = false;
  }

  /// 查询某歌单 id 是否被当前用户收藏
  ///
  /// - 调用方**必须包 Obx**才能响应 likedPlaylistIds 变化
  /// - 转发到 [LikedController.isLiked] (LikedType.playlist)
  bool isPlaylistLiked(String playlistId) =>
      _likedService.isLiked(playlistId, LikedType.playlist);

  /// toggle 收藏（转发到 [LikedController.toggle], LikedType.playlist）
  void togglePlaylistLike(String playlistId) {
    // ignore: discarded_futures
    _likedService.toggle(playlistId, LikedType.playlist);
  }

  /// 查询某专辑 id 是否被收藏
  bool isAlbumLiked(String albumId) =>
      _likedService.isLiked(albumId, LikedType.album);

  /// toggle 专辑收藏
  void toggleAlbumLike(String albumId) {
    // ignore: discarded_futures
    _likedService.toggle(albumId, LikedType.album);
  }

  /// 查询某艺人 id 是否被关注
  bool isArtistLiked(String artistId) =>
      _likedService.isLiked(artistId, LikedType.artist);

  /// toggle 关注 + 主动同步后端真值
  ///
  /// 在 LibraryPage 关注艺人列表的 card 首次 build 时，onFirstBuild 注入 syncSingle
  /// （本 controller 不再负责卡片首次 build 触发，那是 widget 层职责）
  void toggleArtistLike(String artistId) {
    // ignore: discarded_futures
    _likedService.toggle(artistId, LikedType.artist);
  }

  /// 主动同步单点艺人的后端关注状态
  ///
  /// LibraryPage 关注艺人列表 card 首次 build 时调一次
  /// （Service 启动 loadAll 只拉 /artist/sublist 全量，单点 id 不在里面）
  Future<void> syncArtistFollowState(String artistId) {
    // ignore: discarded_futures
    return _likedService.syncArtistLike(artistId);
  }

  @override
  void onClose() {
    _loginWorker?.dispose();
    super.onClose();
  }
}

/// Library tab binding:跟 SearchPageBinding 同款,在 AppShell._bindingForTab 触发
class LibraryBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<LibraryController>(() => LibraryController());
  }
}
