import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:get/get.dart';

import '../models/Album.dart';
import '../models/Song.dart';
import '../services/PlayQueueService.dart';
import '../sdk/api_exception.dart';
import '../sdk/netease_api.dart';
import '../services/liked_albums_service.dart';
import '../services/liked_artists_service.dart';
import '../services/LikedSongsService.dart';
import 'Artist.dart';

/// 艺人详情页 tab 枚举
///
/// 不用裸 int — enum 在编译期挡住 setView(99) 这种垃圾值,
/// switch 也带 exhaustiveness 检查(加新 tab 时漏一个 case 编译器报错)。
enum ArtistView { albums, songs }

/// 艺人页 controller
///
/// - 一位艺人一个实例(由 [artistId] 区分);路由 pop 时随 binding 自动销毁
/// - [load] 并行拉 `artists` / `artist_album` / `artist_songs` 三个接口
class ArtistController extends GetxController {
  ArtistController({required this.artistId});

  /// 路由传进来的艺人 ID
  final String artistId;

  final NeteaseApi api = Get.find<NeteaseApi>();
  final PlayQueueService queue = Get.find<PlayQueueService>();
  final LikedSongsService _likedService = Get.find<LikedSongsService>();
  final LikedArtistsService _likedArtists = Get.find<LikedArtistsService>();

  final Rxn<Artist> artist = Rxn<Artist>();
  final RxList<Album> albums = <Album>[].obs;
  final RxList<Song> songs = <Song>[].obs;
  final RxBool isLoading = false.obs;
  final RxnString errorMessage = RxnString();
  final RxBool isFollowing = false.obs;

  /// 当前选中的 tab (albums = 专辑/EP 网格, songs = 所有歌曲列表)
  final Rx<ArtistView> view = ArtistView.albums.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  /// 并行拉艺人元信息 + 专辑列表 + 所有歌曲
  ///
  /// - 三个接口独立,任一失败不影响其它两路结果写入
  /// - 全失败才把整体错误信息写到 [errorMessage]
  Future<void> load() async {
    isLoading.value = true;
    errorMessage.value = null;
    final id = artistId;
    String? lastError;

    Future<void> safeRun(String hint, Future<void> Function() body) async {
      try {
        await body();
      } on ApiException catch (e) {
        lastError = e.message;
      }
    }

    await Future.wait([
      safeRun('拉艺人信息', () async {
        final r = await api.call((a) => a.artists(id), what: '拉艺人信息');
        debugPrint(
          '[ArtistController] /artists raw body = ${jsonEncode(r.body)}',
        );
        // /artists 响应是 {artist:{...}, hotSongs:[...]} 外层包了 artist
        // search 接口的 artists[] 项才是直接 artist(无 wrap),两种 schema 不同
        // —— 在调用方解包,不让 model 吃两种 schema
        final raw = r.body['artist'];
        if (raw is Map) {
          final m = Map<String, dynamic>.from(raw);
          artist.value = Artist.fromNeteaseJson(m);
          // /artists 响应里 artist 项有 `followed`(bool)字段——优先用后端真值
          final followed = m['followed'];
          if (followed is bool) {
            isFollowing.value = followed;
          }
          // 临时调试:打印首项所有顶层 key + artist 项所有 key,定位为什么 followed 不生效
          if (kDebugMode) {
            // ignore: avoid_print
            print(
              '[ArtistController] /artists raw top-level keys = '
              '${r.body.keys.toList()}, artist item keys = ${m.keys.toList()}, '
              'followed raw value = ${m['followed']} (${m['followed'].runtimeType}), '
              'artist.id = $artistId',
            );
          }
        }
      }),
      safeRun('拉艺人专辑', () async {
        final r = await api.call((a) => a.artist_album(id), what: '拉艺人专辑');
        debugPrint(
          '[ArtistController] /artist/album raw body = ${jsonEncode(r.body)}',
        );
        final list = r.body['hotAlbums'] ?? r.body['albums'];
        if (list is List) {
          albums.assignAll(
            list
                .whereType<Map>()
                .map((m) => Album.fromNeteaseJson(Map<String, dynamic>.from(m)))
                .toList(),
          );
        }
      }),
      safeRun('拉艺人歌曲', () async {
        final r = await api.call(
          (a) => a.artist_songs(id, limit: '50'),
          what: '拉艺人歌曲',
        );
        debugPrint(
          '[ArtistController] /artist/songs raw body = ${jsonEncode(r.body)}',
        );
        final list = r.body['songs'];
        if (list is List) {
          songs.assignAll(
            list
                .whereType<Map>()
                .map((m) => Song.fromNeteaseJson(Map<String, dynamic>.from(m)))
                .toList(),
          );
        }
      }),
    ]);

    if (artist.value == null && albums.isEmpty && songs.isEmpty) {
      // 三路都失败,展示错误
      errorMessage.value = lastError ?? '加载失败';
    }
    isLoading.value = false;
  }

  void setView(ArtistView v) => view.value = v;

  void toggleFollow() {
    // 乐观更新本地状态(纯 UI 反映,后端 toggle 交由 service)
    isFollowing.toggle();
    // ignore: discarded_futures
    _likedArtists.toggle(artistId);
  }

  void toggleFavorite(String songId) {
    // ignore: discarded_futures
    _likedService.toggle(songId);
  }

  /// 查询某首歌是否被喜欢(同 SongListController)
  ///
  /// - 读 .value 触发 Obx 跟踪(contains 走内部 _value 不跟踪)
  bool isLiked(String songId) =>
      // ignore: invalid_use_of_protected_member
      _likedService.likedIds.value.contains(songId);

  /// 查询当前艺人是否已关注
  bool isArtistLiked() => isFollowing.value;

  /// 查询某张专辑是否被收藏
  ///
  /// - 读 .value 触发 Obx 跟踪
  bool isAlbumLiked(String albumId) =>
      // ignore: invalid_use_of_protected_member
      Get.find<LikedAlbumsService>().likedAlbumIds.value.contains(albumId);

  void toggleAlbumFavorite(String albumId) {
    // ignore: discarded_futures
    Get.find<LikedAlbumsService>().toggle(albumId);
  }

  void playSong(Song song) {
    queue.playSong(song);
  }

  /// 播放该艺人所有歌曲(把当前已加载的 songs 全部入队)
  void playAll() {
    queue.playSongs(songs.toList());
  }
}
