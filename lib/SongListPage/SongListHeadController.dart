import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../LibraryPage/LibraryController.dart';
import '../models/LibrarySummary.dart' show PlaylistSource;
import '../models/ApiException.dart';
import '../services/LikedController.dart';
import '../services/repositories/AlbumRepository.dart';
import '../services/repositories/PlaylistRepository.dart';

/// 歌单详情页 head 行 controller。
///
/// **职责**:`SongListDetail` 顶部 head 行所有状态与命令 —— 标题、封面、描述、
/// `playlistSource`(决定按钮),以及播放/收藏/删除按钮对应的命令。
///
/// **不存**:歌曲列表(songs / isLoading / errorMessage) —— 那归 [SongListBodyController] 管。
///
/// head / body 是 sibling controller,各存一份 `playlistId`(同一首歌单),
/// 这样 head 跟 body 完全独立,可以分别销毁 / 重建。代价是 `/album` 多调一次
/// HTTP(head 跟 body 都 fetch) —— 实际场景走同一个 API,服务器端 cache 命中,
/// 延迟几乎为零。如果以后发现浪费,可改成 head 监听 body 的 `albumContent`。
class SongListHeadController extends GetxController {
  SongListHeadController({
    required this.playlistId,
    required this.source,
    this.onPlayAll,
  });

  /// 路由传进来的歌单 ID
  final int playlistId;

  /// 歌单来源(专辑 / 自建 / 收藏等),替代旧的 'album-' 字符串前缀判断
  final PlaylistSource source;

  /// 收藏 / 取消订阅走全局 [LikedController](LikedType.playlist / album 分流)。
  final LikedController _likedService = Get.find<LikedController>();

  /// 详情拉元信息(标题/封面/描述 + source)。
  final PlaylistRepository _playlistRepo = Get.find<PlaylistRepository>();

  /// 专辑分支拉元信息(从 `/album` 响应里取 name/coverUrl/description,
  /// 忽略 songs —— songs 归 body controller 用)。
  final AlbumRepository _albumRepo = Get.find<AlbumRepository>();

  // ---- head 行的 UI 状态 -----------------------------------------------------

  /// 歌单标题(从 playlist_detail / album 取)
  final RxnString title = RxnString();

  /// 歌单封面
  final RxnString coverUrl = RxnString();

  /// 歌单描述
  final RxnString description = RxnString();

  /// 歌单来源(详情页唯一真相源)。
  ///
  /// - 构造时(同步):根据 `playlistId` 前缀判断
  ///   - `album-` 前缀 → [PlaylistSource.album]
  ///   - 其它 → `null`(loading 状态)
  /// - 加载完(异步):`_loadMeta` 拿到 `/playlist/detail` 响应的
  ///   `subscribed` 后写入
  final Rxn<PlaylistSource> playlistSource = Rxn<PlaylistSource>();

  /// head 行整体加载状态(只反映元信息加载 —— 不反映歌曲列表加载,
  /// 那是 body controller 的事)。
  final RxBool isLoading = false.obs;

  /// head 行加载失败信息(body 失败不影响 head 显示)。
  final RxnString errorMessage = RxnString();

  /// `ready` future:head 元信息拉完。外部可以 `await c.ready` 等首屏 head 数据。
  late final Future<void> ready;

  @override
  void onInit() {
    super.onInit();
    // 同步预填:专辑等可同步确定的 source 直接写入,其它等后端响应后覆盖
    playlistSource.value = source;
    ready = _loadMeta();
  }

  /// 拉歌单元信息(标题/封面/描述 + source)。
  ///
  /// album 分支(`/album?id=X`):走 AlbumRepository 拿元信息。
  /// playlist 分支(`/playlist/detail?id=X`):走 PlaylistRepository.fetchMeta。
  Future<void> _loadMeta() async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
      if (source == PlaylistSource.album) {
        await _loadAlbumMeta(playlistId);
      } else {
        await _loadPlaylistMeta(playlistId);
      }
    } on ApiException catch (e) {
      errorMessage.value = e.message;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _loadPlaylistMeta(String id) async {
    final meta = await _playlistRepo.fetchMeta(id);
    if (meta != null) {
      title.value = meta.name;
      coverUrl.value = meta.coverUrl;
      description.value = meta.description;
      playlistSource.value = meta.source;
    }
    // meta 失败 → playlistSource 保持 null,widget 不渲染按钮
  }

  Future<void> _loadAlbumMeta(String id) async {
    // 专辑分支:AlbumRepository.fetch 同时返回元信息 + songs。
    // head 只取元信息,songs 字段忽略(body controller 会自己再 fetch 一次)。
    final content = await _albumRepo.fetch(id);
    if (content != null) {
      title.value = content.name;
      coverUrl.value = content.coverUrl;
      description.value = content.description;
    }
    // fetch 失败 → title/coverUrl/description 保持 null,widget 显示空
  }

  // ---- head 命令 ------------------------------------------------------------

  /// 播放整张歌单:head 只暴露 onPlayAll 钩子,由 binding 注入
  /// body controller 的具体实现 —— head 自己不知道 songs 在哪。
  ///
  /// 为什么不在 head 里直接 Get.find body:head 跟 body 是 sibling,
  /// 不应该有硬依赖。binding 时把 body.playAll 注入 head,head 是纯命令执行器。
  Future<void> Function()? onPlayAll;

  /// 收藏 / 取消订阅(按 id 前缀分流到 LikedType)。
  void toggleFavorite() {
    if (source == PlaylistSource.album) {
      // ignore: discarded_futures
      _likedService.toggle(playlistId, LikedType.album);
    } else {
      // ignore: discarded_futures
      _likedService.toggle(playlistId, LikedType.playlist);
    }
  }

  /// 查询当前 playlistId 是否被收藏(调用方必须包 Obx 才能响应变化)
  bool isPlaylistFavorite() {
    if (source == PlaylistSource.album) {
      return _likedService.isLiked(playlistId, LikedType.album);
    }
    return _likedService.isLiked(playlistId, LikedType.playlist);
  }

  /// 删除当前歌单(自建歌单)。
  Future<void> deletePlaylist() async {
    if (source == PlaylistSource.album) {
      Get.snackbar('提示', '专辑不能删除');
      return;
    }
    final confirmed = await _confirmDelete();
    if (confirmed != true) return;

    final ok = await _playlistRepo.deletePlaylist(playlistId);
    if (!ok) {
      Get.snackbar('删除失败', '稍后重试');
      return;
    }
    // reload Library 列表(LazyPut 可能未注册,守卫)
    if (Get.isRegistered<LibraryController>()) {
      await Get.find<LibraryController>().loadPlaylists();
    }
    // pop 回上一页
    final ctx = Get.context;
    if (ctx != null && Navigator.of(ctx).canPop()) {
      Navigator.of(ctx).pop();
    }
  }

  Future<bool?> _confirmDelete() {
    return Get.dialog<bool>(
      AlertDialog(
        title: const Text('删除歌单'),
        content: Text('确定要删除歌单"${title.value ?? ''}"吗?此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Get.back<bool>(result: false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Get.back<bool>(result: true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
      barrierDismissible: true,
    );
  }
}
