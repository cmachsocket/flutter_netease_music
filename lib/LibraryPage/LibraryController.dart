import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/LibrarySummary.dart';
import '../services/LikedController.dart';
import '../services/PlaylistEventsController.dart';
import '../services/repositories/LibraryRepository.dart';
import '../services/repositories/PlaylistRepository.dart';
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
  final PlaylistRepository _playlistRepo = Get.find<PlaylistRepository>();
  final LikedController _likedService = Get.find<LikedController>();
  final AuthController _auth = Get.find<AuthController>();

  // 创建歌单 UI 状态
  //
  // - isCreating: dialog 显示中(防止用户重复点 FAB 触发多个 dialog)
  // - createError: 上一次创建失败的提示(reload 后清空)
  //
  // 真正的"返回新歌单 id"在 addPlaylist() 内是局部 Future<String?> 不暴露,
  // 调用方只需要 reload playlists 列表(响应: _playlistRepo.createPlaylist
  // 成功后 SDK 已经写盘,LibraryRepository 重新拉会带上新歌单)。
  final RxBool isCreating = false.obs;
  final RxnString createError = RxnString();

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
    // **重置 delta**:全量 reload 后 playlist.trackCount 是后端真值,
    // 本地累计的 delta 已包含在新值里 —— 不重置会重复叠加 + 显示错。
    // 用 resetDelta 而不是 applyDelta(-X):不需要知道当前 delta 值。
    final events = Get.find<PlaylistEventsController>();
    for (final p in list) {
      events.resetDelta(p.id);
    }
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

  /// 创建新歌单 —— 由 LibraryPage FAB 触发
  ///
  /// 流程:
  /// 1. 登录态自检(未登录直接 toast 退出,不弹 dialog 免得用户输入完才发现没用)
  /// 2. 弹 AlertDialog 输入名字(空 / 取消 → 退出)
  /// 3. 调 [_playlistRepo.createPlaylist]
  /// 4. 成功 → 重新拉 playlists 列表(新歌单会出现在 Library tab)
  /// 5. 失败 → 写 [createError] 让 dialog 显示错误文案
  ///
  /// TODO(addTracks):长按歌曲"加入歌单"对话框待实现;目前只暴露创建入口。
  /// 后续可以扩展 `showAddToPlaylistSheet(context, List<String> songIds)` 方法
  /// 走 [PlaylistRepository.addTracks],需要先拉当前用户的歌单列表(目前
  /// `playlists` 已经是),从里面选目标。
  ///
  /// 返回 Future<void] 是为了让 `// ignore: discarded_futures` 仍然成立
  /// (LibraryPage.dart:24 调用点 `onPressed: controller.addPlaylist`,
  ///  void 改成 Future<void] 后 IconButton.onPressed 是 `VoidCallback?`,
  /// 这里返回的是 Future, 但 onPressed 是同步 VoidCallback; Dart 会隐式
  /// 把 `Future<void> Function()` 转成 `VoidCallback` 但 lint 会警告。
  /// 当前调用点已写 `// ignore: discarded_futures` 兜底,所以保留 Future)。
  void addPlaylist() async {
    if (isCreating.value) return;
    if (!_auth.loggedIn) {
      Get.snackbar('提示', '请先登录');
      return;
    }
    final name = await _promptPlaylistName();
    if (name == null || name.isEmpty) return;

    isCreating.value = true;
    createError.value = null;
    try {
      final newId = await _playlistRepo.createPlaylist(name);
      if (newId == null) {
        createError.value = '创建失败,稍后重试';
        return;
      }
      // 成功 → reload 当前 tab(playlist tab)列表
      await loadPlaylists();
    } finally {
      isCreating.value = false;
    }
  }

  /// 弹一个简单 AlertDialog 让用户输入歌单名字。
  ///
  /// 返回:
  /// - 非空字符串(用户确认)
  /// - `null`(用户取消)
  Future<String?> _promptPlaylistName() async {
    final controller = TextEditingController();
    final result = await Get.dialog<String>(
      AlertDialog(
        title: const Text('新建歌单'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '歌单名称'),
          onSubmitted: (_) => Get.back<String>(result: controller.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back<String>(result: null),
            child: const Text('取消'),
          ),
          Obx(() {
            // dialog 上展示上一次的错误(createError)
            final err = createError.value;
            if (err == null) return const SizedBox.shrink();
            return Text(err, style: const TextStyle(color: Colors.red));
          }),
          TextButton(
            onPressed: () => Get.back<String>(result: controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
      barrierDismissible: true,
    );
    controller.dispose();
    return result;
  }
}

/// Library tab binding:跟 SearchPageBinding 同款,在 AppShell._bindingForTab 触发
class LibraryBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<LibraryController>(() => LibraryController());
  }
}
