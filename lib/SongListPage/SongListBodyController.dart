import 'package:get/get.dart';

import '../models/Song.dart';
import '../services/LikedController.dart';
import '../services/AudioPlayerWrapper.dart';
import '../models/ApiException.dart';
import 'LongPressDialog.dart';
import '../services/repositories/AlbumRepository.dart';
import '../services/repositories/ArtistRepository.dart';
import '../services/repositories/PlaylistRepository.dart';
import '../models/LibrarySummary.dart' show PlaylistSource;

/// 歌单详情页 body 区 controller。
///
/// **职责**:歌曲列表(整张专辑 / 整张歌单的所有曲目)、加载状态、错误信息。
///
/// **不存**:head 行的标题 / 封面 / 描述 / playlistSource —— 那归 [SongListHeadController] 管。
///
/// body 跟 head 是 sibling controller,各存一份 `playlistId`,完全独立。
/// binding 时同时注入两个,head 的 `onPlayAll` 钩子指向 body.playAll,
/// 这样 head 是纯命令执行器,不需要知道 body 实现细节。
///
/// **id 形式**:`playlistId` 是 String(网易云 API 入参要求 String),
/// 专辑 / 歌单的区分通过 [source] enum,**不再**用 `'album-'` 前缀字符串
/// 判别。
class SongListBodyController extends GetxController {
  SongListBodyController({
    required this.playlistId,
    required this.source,
    this.loadSongsCustom,
  });

  /// 路由传进来的歌单 ID —— body 跟 head 各存一份(独立,不互引)
  final String playlistId;
  final PlaylistSource source;

  /// 自定义加载钩子。
  ///
  /// **重要**:`onInit` 同步链中调用 `loadSongsCustom`(**没有 await 的
  /// async 函数**)会在 microtask 里触发 Obx rebuild,而 Obx rebuild 又会
  /// 调用 widget tree 里的 `_SongView.build`,`_SongView.build` 又会调
  /// `Get.put(SongListBodyController(...), tag: ...)` —— **同 tag 重复
  /// put** 又触发 `onInit` —— 无限递归 stack overflow。
  ///
  /// **解决**:
  /// 1. `onInit` 用 `Future.microtask(_loadSongs)` 推迟到下一个 microtask,
  ///    让 `Get.put` 同步链完整结束。
  /// 2. 钩子内对 `body.songs.assignAll` 也用 `Future.microtask` 包一层,
  ///    防止在 `_loadSongs` 的 microtask 内再次触发 Rx 写 → Obx rebuild。
  ///
  /// **钩子责任**:写 `songs` 字段。钩子接收 [SongListBodyController] 实例引用,
  /// **不要**自己 `Get.find(tag: ...)` —— 在 `onInit` 同步链中调用
  /// `Get.find` 同 tag 会触发 GetX reentrant 状态错乱。
  final Future<void> Function(SongListBodyController)? loadSongsCustom;

  final AudioPlayerService _queue = Get.find<AudioPlayerService>();
  final LikedController _likedService = Get.find<LikedController>();
  final PlaylistRepository _playlistRepo = Get.find<PlaylistRepository>();
  final AlbumRepository _albumRepo = Get.find<AlbumRepository>();
  final ArtistRepository _artistRepo = Get.find<ArtistRepository>();

  /// 歌曲列表(来自 /playlist/track/all 或 /album)
  final RxList<Song> songs = <Song>[].obs;

  /// body 加载状态(独立于 head 的 isLoading —— 元信息 / 歌曲列表可能错开)
  final RxBool isLoading = false.obs;

  /// body 加载失败(head 失败不影响 body 显示,反之亦然)
  final RxnString errorMessage = RxnString();

  /// `ready` future:body 拉完首屏歌曲。外部可以 `await c.ready` 等首屏数据。
  ///
  /// **不是 final**:`Obx` 在某些边缘场景下可能多次重建 `_SongView`,
  /// GetX 内部可能再次触发 `onInit`(取决于 GetX 内部状态机)。
  /// `late final` 第二次会抛 `LateInitializationError: Field already initialized`,
  /// 改成 `late` 兼容这种场景 —— 每次 `onInit` 重启一个新的 load future,
  /// widget 内部用 `controller.songs` 响应式读,语义不变。
  late Future<void> ready;

  @override
  void onInit() {
    super.onInit();
    // **异步推迟到下一个 microtask**:避免在 `Get.put` 同步创建链中
    // 触发的 `onInit` 里同步执行 async 代码 —— 那会 reentrant 调 `Get.find`
    // 同 tag controller,GetX 内部状态错乱 → 无限递归 onInit → stack overflow。
    ready = Future.microtask(_loadSongs);
  }

  /// 拉曲目:按 [source] enum 分流
  ///
  /// **关键**:`_loadSongs` 通过 `Future.microtask` 推迟到 onInit 同步链外执行。
  /// 这样 `loadSongsCustom` 内的 Rx 写(assignAll)不会在 `Get.put` 同步创建链
  /// 中触发 Obx rebuild → `_SongView.build` → `Get.put` 同 tag → 重复 onInit
  /// → stack overflow。
  Future<void> _loadSongs() async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
      // 自定义钩子优先(用例:搜索结果直接用 SearchController.songResults)
      if (loadSongsCustom != null) {
        await loadSongsCustom!(this);
        return;
      }
      switch (source) {
        case PlaylistSource.pure:
          // pure 没自定义钩子 → 用 playlist 路径(实际场景不会走到)
          await _loadPlaylistSongs(playlistId);
        case PlaylistSource.album:
          await _loadAlbumSongs(playlistId);
        case PlaylistSource.artist:
          await _loadArtistSongs(playlistId);
        case PlaylistSource.created:
        case PlaylistSource.collected:
          await _loadPlaylistSongs(playlistId);
      }
    } on ApiException catch (e) {
      errorMessage.value = e.message;
    } finally {
      isLoading.value = false;
    }
  }

  /// 歌单分支:`/playlist/track/all?id=X`
  Future<void> _loadPlaylistSongs(String id) async {
    final fetched = await _playlistRepo.fetchTracks(id);
    songs.assignAll(fetched);
  }

  /// 专辑分支:`/album?id=X`(响应同时含 album 项 + songs 数组,一次拿全)
  Future<void> _loadAlbumSongs(String id) async {
    final content = await _albumRepo.fetch(id);
    if (content == null) {
      throw ApiException(0, '专辑内容拉取失败');
    }
    songs.assignAll(content.songs);
  }

  /// 艺人分支:`/artist/songs?id=X`(艺人所有歌曲)
  Future<void> _loadArtistSongs(String id) async {
    final fetched = await _artistRepo.fetchSongs(id);
    songs.assignAll(fetched);
  }

  // ---- body 命令 ------------------------------------------------------------

  /// 播放整张歌单:head 的 onPlayAll 钩子指向这里。
  Future<void> playAll() {
    return _queue.playSongs(songs.toList());
  }

  /// 播放某首歌:从这首开始播整张歌单。
  Future<void> playSong(Song song) {
    return _queue.playSongs(songs.toList(), startSong: song);
  }

  /// toggle 单首歌的喜欢状态(每首歌是 song 类型 LikedType)。
  void toggleFavorite(String songId) {
    // ignore: discarded_futures
    _likedService.toggle(songId, LikedType.song);
  }

  void onSongLongPress(Song song, int index) {
    Get.dialog(
      LongPressDialog(
        song: song,
        index: index,
        source: source,
        playlistId: playlistId,
      ),
    );
  }

  /// 查询某首歌是否被喜欢(调用方必须包 Obx 才能响应变化)
  bool isLiked(String songId) => _likedService.isLiked(songId, LikedType.song);

  /// 按 [playlistId] 拉歌 + 整张播放
  ///
  /// 用于卡片"播放"按钮:不进入详情页直接播放整张歌单
  ///
  /// 临时 put 一个 [SongListBodyController] 实例,等首屏 load 完 →
  /// 调 [playAll] → 销毁。完成后这个临时 controller 跟详情页那个没关系。
  static Future<void> playPlaylistById(String playlistId) async {
    final tag = 'preview-$playlistId';
    if (Get.isRegistered<SongListBodyController>(tag: tag)) {
      Get.delete<SongListBodyController>(tag: tag);
    }
    final c = Get.put(
      SongListBodyController(
        playlistId: playlistId,
        source: PlaylistSource.pure,
      ),
      tag: tag,
    );
    await c.ready;
    if (c.songs.isNotEmpty) await c.playAll();
    Get.delete<SongListBodyController>(tag: tag);
  }
}
