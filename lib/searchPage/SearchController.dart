import 'dart:async' show unawaited;

import 'package:flutter/widgets.dart' show TextEditingController;
import 'package:get/get.dart';

import '../models/Album.dart';
import '../models/Song.dart';
import '../ArtistPage/Artist.dart';
import '../sdk/api_exception.dart';
import '../sdk/netease_api.dart';
import '../services/LikedSongsService.dart';
import '../services/PlayQueueService.dart';
import '../services/LikedAlbumsService.dart';
import '../services/LikedArtistsService.dart';
import '../services/LikedPlaylistsService.dart';

/// 网易云搜索 type 参数(参考 netease_cloud_music_api /search 接口)
///
/// 只取这四个(用户限定):
/// - 1 单曲
/// - 10 专辑
/// - 100 艺人
/// - 1000 歌单
///
/// 直接当 query param 传给后端
enum SearchType {
  song(1, '单曲'),
  album(10, '专辑'),
  artist(100, '艺人'),
  playlist(1000, '歌单');

  const SearchType(this.typeId, this.label);

  /// 对应网易云 search API 的 type 参数
  final int typeId;

  /// UI 显示标签(segmented button 上用)
  final String label;
}

/// 搜索页 controller
///
/// - 4 个 [SearchType] 各自维护一份结果(切 tab 不丢旧结果)
/// - [search] 调 SDK /search,**只查当前 type**(省钱 + 响应快)
/// - [setType] 切 tab 时如果有当前 keyword 就**自动重搜**(旧结果跨 type 不能复用)
class SearchController extends GetxController {
  final Rx<SearchType> type = SearchType.song.obs;

  final NeteaseApi api = Get.find<NeteaseApi>();
  final PlayQueueService queue = Get.find<PlayQueueService>();
  final LikedSongsService _likedService = Get.find<LikedSongsService>();

  /// TextField 的真实数据源 —— 必须显式绑给 [TextField.controller],
  /// 否则点清除按钮时 [TextField] 内部 state 复用了看不见的 TextEditingController,
  /// keyword 变空但输入框不会清空(看起来没反应)
  final TextEditingController textController = TextEditingController();

  /// 当前输入框的关键词 (TextField onChanged 同步,只反映输入框文本)
  ///
  /// **不要**用这个判"是否搜过"——用户键入字符 keyword 就变,但还没提交。
  /// 判"搜过"请用 [submittedKeyword](只有 search() 调用时才写)。
  final RxString keyword = ''.obs;

  /// 已提交的关键词(search() 调用时写入)
  ///
  /// - 跟 [keyword] 解耦:TextField 实时输入不影响结果视图,
  ///   只有回车/点搜索图标触发的 search() 才更新它
  /// - 切 tab 用这个判断要不要自动重搜(旧结果跨 type 不能复用,但同 keyword 重搜是 O(1))
  /// - 判"未搜过"用 `submittedKeyword.value.isEmpty` —— 避开"键入几个字符但没提交"的陷阱
  final RxString submittedKeyword = ''.obs;

  /// 4 份结果(切 tab 不丢;只有同 type 才覆盖)
  final RxList<Song> songResults = <Song>[].obs;
  final RxList<Album> albumResults = <Album>[].obs;
  final RxList<Artist> artistResults = <Artist>[].obs;
  final RxList<PlaylistSummary> playlistResults = <PlaylistSummary>[].obs;

  /// 搜索进行中
  final RxBool isLoading = false.obs;

  /// 错误信息
  final RxnString errorMessage = RxnString();

  @override
  void onClose() {
    textController.dispose();
    super.onClose();
  }

  void setKeyword(String k) => keyword.value = k;

  /// 清除按钮
  void clearKeyword() {
    textController.clear();
    keyword.value = '';
    submittedKeyword.value = '';   // 同步清提交状态,UI 回"输入关键词"提示
    _clearCurrent();
  }

  /// 切换 tab:有 keyword 就自动重搜,空 keyword 直接清空对应结果
  ///
  /// 读 [keyword](输入框文本)而非 [submittedKeyword]——用户键入了字但没提交,
  /// 切 tab 时按输入框内容重搜,符合"用户期望"。
  void setType(SearchType t) {
    type.value = t;
    final k = keyword.value.trim();
    if (k.isEmpty) {
      _clearCurrent();
    } else {
      search(k);
    }
  }

  void _clearCurrent() {
    switch (type.value) {
      case SearchType.song:
        songResults.clear();
      case SearchType.album:
        albumResults.clear();
      case SearchType.artist:
        artistResults.clear();
      case SearchType.playlist:
        playlistResults.clear();
    }
  }

  /// 触发搜索(只查当前 [type] 的结果)
  void search(String keyword) async {
    final k = keyword.trim();
    this.keyword.value = k;
    if (k.isEmpty) {
      _clearCurrent();
      submittedKeyword.value = '';   // 清空提交状态 → UI 走"输入关键词"提示
      return;
    }
    submittedKeyword.value = k;       // 提交后才写,UI 判"搜过"才看这个
    isLoading.value = true;
    errorMessage.value = null;
    final t = type.value;
    try {
      final r = await api.call(
        (a) => a.search(k, type: t.typeId.toString(), limit: '30'),
        what: '搜索',
      );
      _parseAndStore(r.body, t);
    } on ApiException catch (e) {
      errorMessage.value = e.message;
      Get.snackbar(
        '搜索失败 (code ${e.code})',
        e.message,
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      isLoading.value = false;
    }
  }

  /// 按 type 分发到对应 RxList
  void _parseAndStore(Map<String, dynamic> body, SearchType t) {
    final result = body['result'];
    if (result is! Map) return;
    final list = result[_resultKey(t)];
    if (list is! List) return;
    switch (t) {
      case SearchType.song:
        songResults.assignAll(
          list
              .whereType<Map>()
              .map((m) => Song.fromNeteaseJson(Map<String, dynamic>.from(m)))
              .toList(),
        );
        // 单曲封面补图:search 接口 album 项只有 picId(数字),没 picUrl(URL)。
        // 批量调 /song/detail?ids=... 一次性拿所有歌的真 coverUrl 回填。
        unawaited(_enrichSongCovers());
      case SearchType.album:
        albumResults.assignAll(
          list
              .whereType<Map>()
              .map((m) => Album.fromNeteaseJson(Map<String, dynamic>.from(m)))
              .toList(),
        );
      case SearchType.artist:
        artistResults.assignAll(
          list
              .whereType<Map>()
              .map((m) => Artist.fromNeteaseJson(Map<String, dynamic>.from(m)))
              .toList(),
        );
      case SearchType.playlist:
        playlistResults.assignAll(
          list
              .whereType<Map>()
              .map(
                (m) => PlaylistSummary.fromNeteaseJson(
                  Map<String, dynamic>.from(m),
                ),
              )
              .toList(),
        );
    }
  }

  static String _resultKey(SearchType t) => switch (t) {
    SearchType.song => 'songs',
    SearchType.album => 'albums',
    SearchType.artist => 'artists',
    SearchType.playlist => 'playlists',
  };

  /// 单曲封面补图
  ///
  /// - **背景**:`/search?type=1` 返回的 songs[].album 只给 `picId`(数字),
  ///   不给 `picUrl`(URL);`Image.network("数字串")` 解析 URI 失败 → 占位
  /// - **方案**:批量调 `/song/detail?ids=id1,id2,...`(一次 API 拿全),
  ///   响应里 songs[].album.picUrl 是真 URL,按 songId 回填
  /// - **回填方式**:Song.coverUrl 是 `final`,不可变 → 重建 Song 对象 + assignAll
  /// - **失败处理**:catch 后静默(补图失败不阻塞搜索结果,UI 走占位)
  /// - **竞争**:补图回调时如果用户已经切走/清空,byId 跟当前 songResults 对不上,
  ///   按 id 匹配不上就不动 → 安全
  Future<void> _enrichSongCovers() async {
    final snapshot = songResults.toList();
    if (snapshot.isEmpty) return;
    final ids = snapshot.map((s) => s.id).join(',');
    try {
      final r = await api.call((a) => a.song_detail(ids), what: '补单曲封面');
      final songs = r.body['songs'];
      if (songs is! List) return;
      // 按 songId → 真 coverUrl 建索引
      final byId = <String, String>{};
      for (final raw in songs) {
        if (raw is! Map) continue;
        final m = Map<String, dynamic>.from(raw);
        final sid = m['id']?.toString();
        if (sid == null) continue;
        final al = m['al'] ?? m['album'];
        if (al is! Map) continue;
        final picUrl = (Map<String, dynamic>.from(al)['picUrl'] ?? '')
            .toString();
        if (picUrl.isNotEmpty) byId[sid] = picUrl;
      }
      if (byId.isEmpty) return;
      // 按当前 songResults 重建(若 songResults 已被换走,以当前为准,旧 id 跳过)
      final updated = <Song>[];
      var changed = false;
      for (final s in songResults) {
        final newCover = byId[s.id];
        if (newCover != null && newCover != s.coverUrl) {
          updated.add(
            Song(
              id: s.id,
              title: s.title,
              artist: s.artist,
              artistId: s.artistId,
              album: s.album,
              albumId: s.albumId,
              coverUrl: newCover,
              duration: s.duration,
            ),
          );
          changed = true;
        } else {
          updated.add(s);
        }
      }
      if (changed) songResults.assignAll(updated);
    } on ApiException {
      // 补图失败不阻塞搜索结果,UI 走 SongRowTile._Cover 空 URL 占位
    }
  }

  bool isAlbumLiked(String albumId) =>
      // ignore: invalid_use_of_protected_member
      Get.find<LikedAlbumsService>().likedAlbumIds.value.contains(albumId);

  bool isArtistLiked(String artistId) =>
      // ignore: invalid_use_of_protected_member
      Get.find<LikedArtistsService>().likedArtistIds.value.contains(artistId);

  bool isPlaylistLiked(String playlistId) =>
      // ignore: invalid_use_of_protected_member
      Get.find<LikedPlaylistsService>().likedPlaylistIds.value.contains(playlistId);

  void toggleAlbumLike(String albumId) {
    // ignore: discarded_futures
    Get.find<LikedAlbumsService>().toggle(albumId);
  }

  void toggleArtistLike(String artistId) {
    // ignore: discarded_futures
    Get.find<LikedArtistsService>().toggle(artistId);
  }

  void togglePlaylistLike(String playlistId) {
    // ignore: discarded_futures
    Get.find<LikedPlaylistsService>().toggle(playlistId);
  }

  void syncArtistLike(String artistId) {
    // ignore: discarded_futures
    Get.find<LikedArtistsService>().syncSingle(artistId);
  }

  /// 单曲点赞/收藏转发(搜索结果的 SongListBody 需要)
  ///
  /// 跟 SongListController.toggleFavorite 同语义,走全局 [LikedSongsService]
  void toggleFavorite(String songId) {
    // ignore: discarded_futures
    _likedService.toggle(songId);
  }

  /// 查询单曲点赞状态(同 SongListController.isLiked)
  ///
  /// 调用方需要包 Obx 才能响应 likedIds 变化
  bool isLiked(String songId) =>
      // ignore: invalid_use_of_protected_member
      _likedService.likedIds.value.contains(songId);

  /// 播放搜索结果里的某首歌
  ///
  /// 跟 SongListController.playSong 同语义:把当前搜索结果当作播放队列,
  /// 从这首开始播放。搜索结果有限 (limit 30)。
  Future<void> playSong(Song song) {
    return queue.playSongs(songResults.toList(), startSong: song);
  }
}

/// 搜索结果里的歌单摘要(轻量,跟 LibraryController 的 PlaylistSummary
/// 字段有重合但来源不同 —— 搜索结果没有 userId 等 user-only 字段,放一起会污染)
class PlaylistSummary {
  final String id;
  final String name;
  final String coverUrl;
  final int trackCount;
  final String creatorName;

  const PlaylistSummary({
    required this.id,
    required this.name,
    required this.coverUrl,
    required this.trackCount,
    required this.creatorName,
  });

  /// 网易云 /search?type=1000 返回的 `result.playlists[]` 元素:
  /// - id, name, coverImgUrl, trackCount, creator.nickname
  factory PlaylistSummary.fromNeteaseJson(Map<String, dynamic> json) {
    final creator = json['creator'] is Map
        ? Map<String, dynamic>.from(json['creator'] as Map)
        : null;
    return PlaylistSummary(
      id: json['id'].toString(),
      name: (json['name'] ?? '').toString(),
      coverUrl: (json['coverImgUrl'] ?? '').toString(),
      trackCount: (json['trackCount'] as int?) ?? 0,
      creatorName: (creator?['nickname'] ?? '').toString(),
    );
  }
}

/// 搜索页 binding:跟 LibraryController / ArtistController / SongListController 同款
///
/// 由 [AppShell._bindingForTab] 在切到搜索 tab 时按需注入,路由 pop 时随 binding 自动销毁
class SearchPageBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SearchController>(() => SearchController());
  }
}
