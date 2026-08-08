import 'package:get/get.dart';

import '../sdk/api_call.dart';
import '../sdk/api_exception.dart';
import '../sdk/netease_api.dart';

/// Library 页 controller
///
/// 三个 tab 分别对应网易云"我的":
/// - tab 1 (歌单): /user/playlist(uid)
/// - tab 2 (专辑): /album/sublist
/// - tab 3 (艺人): /user/follows(uid)
///
/// **未登录时**:不调接口,展示"请先登录"占位卡
/// **uid 缺失时**:拉一次 /user/account,缓存到 [NeteaseApi.currentUid]
class LibraryController extends GetxController {
  final RxInt tabIndex = 1.obs;

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

  void setTabIndex(int index) {
    tabIndex.value = index;
    // 切换时按需触发加载(只在未加载过且未在加载中时)
    switch (index) {
      case 1:
        if (playlists.isEmpty && !playlistsLoading.value) loadPlaylists();
        break;
      case 2:
        if (albums.isEmpty && !albumsLoading.value) loadAlbums();
        break;
      case 3:
        if (artists.isEmpty && !artistsLoading.value) loadArtists();
        break;
    }
  }

  Future<void> loadPlaylists() async {
    if (playlistsLoading.value) return;
    playlistsLoading.value = true;
    playlistsError.value = null;
    final api = Get.find<NeteaseApi>();
    final uid = await _ensureUid(api);
    if (uid == null) {
      playlistsLoading.value = false;
      return;
    }
    try {
      final r = await api.call(
        (a) => a.user_playlist(uid.toString(), limit: '50'),
        what: '我的歌单',
      );
      final list = r.body['playlist'];
      if (list is List) {
        playlists.assignAll(
          list
              .whereType<Map>()
              .map((m) => PlaylistSummary.fromNeteaseJson(
                    Map<String, dynamic>.from(m),
                  ))
              .toList(),
        );
      }
    } on ApiException catch (e) {
      playlistsError.value = e.message;
    } finally {
      playlistsLoading.value = false;
    }
  }

  Future<void> loadAlbums() async {
    if (albumsLoading.value) return;
    albumsLoading.value = true;
    albumsError.value = null;
    final api = Get.find<NeteaseApi>();
    try {
      final r = await api.call(
        (a) => a.album_sublist(limit: '50'),
        what: '我的订阅专辑',
      );
      // /album/sublist 返回 data 数组(也有 body 直接是数组的,都试一下)
      final list = r.body['data'] is List
          ? r.body['data'] as List
          : (r.body is List ? r.body as List : const []);
      if (list.isNotEmpty) {
        albums.assignAll(
          list
              .whereType<Map>()
              .map((m) => AlbumSummary.fromNeteaseJson(
                    Map<String, dynamic>.from(m),
                  ))
              .toList(),
        );
      }
    } on ApiException catch (e) {
      albumsError.value = e.message;
    } finally {
      albumsLoading.value = false;
    }
  }

  Future<void> loadArtists() async {
    if (artistsLoading.value) return;
    artistsLoading.value = true;
    artistsError.value = null;
    final api = Get.find<NeteaseApi>();
    final uid = await _ensureUid(api);
    if (uid == null) {
      artistsLoading.value = false;
      return;
    }
    try {
      final r = await api.call(
        (a) => a.user_follows(uid.toString(), limit: '50'),
        what: '我的关注艺人',
      );
      final list = r.body['follow'];
      if (list is List) {
        artists.assignAll(
          list
              .whereType<Map>()
              .map((m) => ArtistSummary.fromNeteaseJson(
                    Map<String, dynamic>.from(m),
                  ))
              .toList(),
        );
      }
    } on ApiException catch (e) {
      artistsError.value = e.message;
    } finally {
      artistsLoading.value = false;
    }
  }

  /// 确保当前 uid 有缓存,没有就拉一次
  Future<int?> _ensureUid(NeteaseApi api) async {
    if (api.currentUid.value != null) return api.currentUid.value;
    await api.fetchCurrentUid();
    return api.currentUid.value;
  }
}

/// 歌单摘要(tab 1)
class PlaylistSummary {
  final String id;
  final String name;
  final String picUrl;
  final int trackCount;

  const PlaylistSummary({
    required this.id,
    required this.name,
    required this.picUrl,
    required this.trackCount,
  });

  /// /user/playlist.playlist[] 元素:
  /// - id, name, coverImgUrl, trackCount
  factory PlaylistSummary.fromNeteaseJson(Map<String, dynamic> json) =>
      PlaylistSummary(
        id: json['id'].toString(),
        name: (json['name'] ?? '').toString(),
        picUrl: (json['coverImgUrl'] ?? '').toString(),
        trackCount: (json['trackCount'] as int?) ?? 0,
      );
}

/// 专辑摘要(tab 2)
class AlbumSummary {
  final String id;
  final String name;
  final String artist;
  final String picUrl;

  const AlbumSummary({
    required this.id,
    required this.name,
    required this.artist,
    required this.picUrl,
  });

  /// /album/sublist.data[] 元素(具体字段名按实际响应调整):
  /// - id, name, artists[0].name, picUrl
  factory AlbumSummary.fromNeteaseJson(Map<String, dynamic> json) {
    final artists = (json['artists'] as List?) ?? const [];
    final firstArtist = artists.isNotEmpty
        ? Map<String, dynamic>.from(artists.first as Map)
        : null;
    return AlbumSummary(
      id: json['id'].toString(),
      name: (json['name'] ?? '').toString(),
      artist: (firstArtist?['name'] ?? '').toString(),
      picUrl: (json['picUrl'] ?? '').toString(),
    );
  }
}

/// 艺人摘要(tab 3)
class ArtistSummary {
  final String id;
  final String name;
  final String picUrl;

  const ArtistSummary({
    required this.id,
    required this.name,
    required this.picUrl,
  });

  /// /user/follows.follow[] 元素:
  /// - id, name, picUrl
  factory ArtistSummary.fromNeteaseJson(Map<String, dynamic> json) =>
      ArtistSummary(
        id: json['id'].toString(),
        name: (json['name'] ?? '').toString(),
        picUrl: (json['picUrl'] ?? '').toString(),
      );
}

/// Library tab binding:跟 SearchPageBinding 同款,在 AppShell._bindingForTab 触发
class LibraryBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<LibraryController>(() => LibraryController());
  }
}