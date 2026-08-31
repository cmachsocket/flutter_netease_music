import 'package:get/get.dart';

import '../models/Song.dart';
import '../services/LikedController.dart';
import '../services/AudioPlayerWrapper.dart';
import '../models/ApiException.dart';
import '../services/repositories/AlbumRepository.dart';
import '../services/repositories/PlaylistRepository.dart';

/// 歌单详情页 controller
///
/// - 一张歌单一个实例(由 [playlistId] 区分);路由 pop 时随 binding 自动销毁
/// - 数据模型走 [Song](已抽到 ../models/Song.dart)
/// - 接 SDK 后:[load] 调 `/playlist/detail` 拿歌单元信息 + `/playlist/track/all`
///   拿所有曲目(因为 playlist_detail 只返前 1000 首,track_all 才能拿全)
class SongListController extends GetxController {
  SongListController({required this.playlistId});

  /// 路由传进来的歌单 ID
  final String playlistId;

  final AudioPlayerService queue = Get.find<AudioPlayerService>();
  final LikedController _likedService = Get.find<LikedController>();
  final PlaylistRepository _playlistRepo = Get.find<PlaylistRepository>();
  final AlbumRepository _albumRepo = Get.find<AlbumRepository>();

  final RxList<Song> songs = <Song>[].obs;
  final RxBool isLoading = false.obs;
  final RxnString errorMessage = RxnString();

  /// 歌单标题(从 playlist_detail 取)
  final RxnString title = RxnString();

  /// 歌单封面(从 playlist_detail 取)
  final RxnString coverUrl = RxnString();

  /// 歌单描述(从 playlist_detail 取)
  final RxnString description = RxnString();

  /// 首次 [load] 完成的 future(由 [onInit] 赋值)
  ///
  /// 外部可以 `await c.ready` 同步等首屏数据(不重复触发 load)
  late final Future<void> ready;

  @override
  void onInit() {
    super.onInit();
    ready = load();
  }

  /// 拉当前 ([playlistId]) 的元信息 + 曲目
  ///
  /// **id 形态**:
  /// - 普通歌单:`纯数字`,走 `/playlist/detail` + `/playlist/track/all`
  /// - 专辑:`'album-<id>'` 前缀(由调用方拼,见 [SongListCard] / [linked_detail_text]),
  ///   走 `/album?id=<id>`(一次性拿全:album 项 + songs 数组)
  ///
  /// 为什么 1 个 controller 接两种 id:
  /// - 详情页 UI 完全一致,业务字段(title/coverUrl/description/songs)走同一套 Rx
  /// - 差异化只在拉数据阶段,所以分流放在 controller 里不放在 widget
  Future<void> load() async {
    isLoading.value = true;
    errorMessage.value = null;
    final id = playlistId;
    try {
      if (id.startsWith(_albumPrefix)) {
        await _loadAlbum(id.substring(_albumPrefix.length));
      } else {
        await _loadPlaylist(id);
      }
    } on ApiException catch (e) {
      errorMessage.value = e.message;
    } finally {
      isLoading.value = false;
    }
  }

  static const String _albumPrefix = 'album-';

  /// 歌单分支:`/playlist/detail`(元信息) + `/playlist/track/all`(曲目)
  ///
  /// - API 调用集中到 [PlaylistRepository]。
  /// - 元信息允许失败(只丢标题/封面,不影响曲目展示);曲目失败抛 [ApiException]
  ///   让 [load] 走顶层 catch 写 errorMessage。
  Future<void> _loadPlaylist(String id) async {
    // 1. 元信息(标题/封面/描述)—— Repository 内部已 try/catch,失败返回 null
    final meta = await _playlistRepo.fetchMeta(id);
    if (meta != null) {
      title.value = meta.name;
      coverUrl.value = meta.coverUrl;
      description.value = meta.description;
    }
    // 元信息失败不影响曲目展示

    // 2. 拉所有曲目(track_all 而非 detail.tracks,后者只返前 1000 首)
    final fetched = await _playlistRepo.fetchTracks(id);
    songs.assignAll(fetched);
  }

  /// 专辑分支:`/album?id=X`(响应同时含 album 项 + songs 数组,一次拿全)
  Future<void> _loadAlbum(String id) async {
    final content = await _albumRepo.fetch(id);
    if (content == null) {
      throw ApiException(0, '专辑内容拉取失败');
    }
    title.value = content.name;
    coverUrl.value = content.coverUrl;
    description.value = content.description;
    songs.assignAll(content.songs);
  }

  /// 喜爱切换 → 走全局 [LikedController.toggle](LikedType.song)(乐观更新 + 后端持久化)
  void toggleFavorite(String songId) {
    // ignore: discarded_futures
    _likedService.toggle(songId, LikedType.song);
  }

  /// 查询某首歌是否被喜欢
  ///
  /// - 调用方**必须包 Obx**才能响应 likedSongIds 变化
  /// - 转发到 [LikedController.isLiked] (LikedType.song)
  bool isLiked(String songId) => _likedService.isLiked(songId, LikedType.song);

  /// toggle 当前 playlistId 的收藏(按 [playlistId] 前缀分流)
  ///
  /// - `'album-<id>'` → LikedType.album
  /// - 纯数字 → LikedType.playlist
  /// - controller 是"playlistId 是什么"唯一知道的地方,widget 不用分流
  void togglePlaylistFavorite() {
    if (playlistId.startsWith(_albumPrefix)) {
      // ignore: discarded_futures
      _likedService.toggle(
        playlistId.substring(_albumPrefix.length),
        LikedType.album,
      );
    } else {
      // ignore: discarded_futures
      _likedService.toggle(playlistId, LikedType.playlist);
    }
  }

  /// 查询当前 playlistId 是否被收藏
  ///
  /// - 调用方**必须包 Obx**才能响应 likedAlbumIds / likedPlaylistIds 变化
  bool isPlaylistFavorite() {
    if (playlistId.startsWith(_albumPrefix)) {
      return _likedService.isLiked(
        playlistId.substring(_albumPrefix.length),
        LikedType.album,
      );
    }
    return _likedService.isLiked(playlistId, LikedType.playlist);
  }

  /// 播放当前歌单里的某首歌:把整个歌单作为播放列表，再从这首开始播。
  Future<void> playSong(Song song) {
    return queue.playSongs(songs.toList(), startSong: song);
  }

  /// 播放整张歌单:从第一首开始。
  Future<void> playAll() {
    return queue.playSongs(songs.toList());
  }

  /// 按 [playlistId] 拉歌 + 整张播放
  ///
  /// 用于卡片"播放"按钮:不进入详情页直接播放整张歌单
  ///
  /// 临时 put 一个 [SongListController] 实例,等首屏 load 完 → 调 [playAll] → 销毁
  static Future<void> playPlaylistById(String playlistId) async {
    final tag = 'preview-$playlistId';
    if (Get.isRegistered<SongListController>(tag: tag)) {
      Get.delete<SongListController>(tag: tag);
    }
    final c = Get.put(SongListController(playlistId: playlistId), tag: tag);
    await c.ready;
    if (c.songs.isNotEmpty) await c.playAll();
    Get.delete<SongListController>(tag: tag);
  }
}

class SongListBinding extends Bindings {
  @override
  void dependencies() {
    // 不带参数:参数在 [SongListDetailBinding] 里走(那边拿 playlistId)
  }
}
