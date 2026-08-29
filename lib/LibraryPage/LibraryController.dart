import 'dart:convert';
import 'package:flutter/material.dart' show IconData, Icons;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:get/get.dart';

import '../models/ApiException.dart';
import '../sdk/netease_api.dart';
import '../services/LikedAlbumsService.dart';
import '../services/LikedArtistsService.dart';
import '../services/LikedPlaylistsService.dart';
import '../controller/AuthController.dart';

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
/// 三个 tab 分别对应网易云"我的":
/// - tab 1 (歌单): /user/playlist(uid)
/// - tab 2 (专辑): /album/sublist
/// - tab 3 (艺人): /user/follow/mixed(scene=1)
///
/// **未登录时**:不调接口,展示"请先登录"占位卡
/// **uid 缺失时**:拉一次 /user/account,缓存到 [NeteaseApi.currentUid]
class LibraryController extends GetxController {
  /// 当前 tab (默认歌单)
  ///
  /// **不用裸 int** —— enum 在编译期挡住 setTab(99) 这种垃圾值,
  /// switch 也带 exhaustiveness 检查(加新 tab 时漏一个 case 编译器报错)。
  final Rx<LibraryTab> tab = LibraryTab.playlists.obs;
  Worker? _loginWorker;

  final NeteaseApi api = Get.find<NeteaseApi>();
  final LikedPlaylistsService _likedPlaylists =
      Get.find<LikedPlaylistsService>();
  final LikedAlbumsService _likedAlbums = Get.find<LikedAlbumsService>();
  final LikedArtistsService _likedArtists = Get.find<LikedArtistsService>();
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
    // 切换时按需触发加载(只在未加载过且未在加载中时)
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
              .map(
                (m) => PlaylistSummary.fromNeteaseJson(
                  Map<String, dynamic>.from(m),
                ),
              )
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
              .map(
                (m) =>
                    AlbumSummary.fromNeteaseJson(Map<String, dynamic>.from(m)),
              )
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
    try {
      final r = await api.call(
        (a) => a.user_follow_mixed(size: '50', cursor: '0', scene: '1'),
        what: '我的关注艺人',
      );
      debugPrint(
        '[LibraryController] /user/follow/mixed raw body = ${jsonEncode(r.body)}',
      );
      final data = r.body['data'];
      final list = data is Map ? (data['records'] ?? data['list']) : data;
      if (list is List) {
        artists.assignAll(
          list
              .whereType<Map>()
              .map((record) => record['artistInfo'])
              .whereType<Map>()
              .map(
                (m) =>
                    ArtistSummary.fromNeteaseJson(Map<String, dynamic>.from(m)),
              )
              .toList(),
        );
      }
    } on ApiException catch (e) {
      artistsError.value = e.message;
    } finally {
      artistsLoading.value = false;
    }
  }

  /// 查询某歌单 id 是否被当前用户收藏
  ///
  /// - 调用方**必须包 Obx**才能响应 likedPlaylistIds 变化
  /// - 读 .value 触发 Obx 跟踪(contains 走内部 _value 不跟踪)
  bool isPlaylistLiked(String playlistId) {
    // ignore: invalid_use_of_protected_member
    return _likedPlaylists.likedPlaylistIds.value.contains(playlistId);
  }

  /// toggle 收藏(转发到 LikedPlaylistsService)
  void togglePlaylistLike(String playlistId) {
    // ignore: discarded_futures
    _likedPlaylists.toggle(playlistId);
  }

  /// 查询某专辑 id 是否被收藏
  bool isAlbumLiked(String albumId) {
    // ignore: invalid_use_of_protected_member
    return _likedAlbums.likedAlbumIds.value.contains(albumId);
  }

  /// toggle 专辑收藏
  void toggleAlbumLike(String albumId) {
    // ignore: discarded_futures
    _likedAlbums.toggle(albumId);
  }

  /// 查询某艺人 id 是否被关注
  bool isArtistLiked(String artistId) {
    // ignore: invalid_use_of_protected_member
    return _likedArtists.likedArtistIds.value.contains(artistId);
  }

  /// toggle 关注 + 主动同步后端真值
  ///
  /// 在 LibraryPage 关注艺人列表的 card 首次 build 时,onFirstBuild 注入 syncSingle
  /// (本 controller 不再负责卡片首次 build 触发,那是 widget 层职责)
  void toggleArtistLike(String artistId) {
    // ignore: discarded_futures
    _likedArtists.toggle(artistId);
  }

  /// 主动同步单点艺人的后端关注状态
  ///
  /// LibraryPage 关注艺人列表 card 首次 build 时调一次
  /// (Service 启动 hydrate 只拉 /artist/sublist 全量,单点 id 不在里面)
  Future<void> syncArtistFollowState(String artistId) {
    // ignore: discarded_futures
    return _likedArtists.syncSingle(artistId);
  }

  /// 确保当前 uid 有缓存,没有就拉一次
  // Future<int?> _ensureUid() async {
  //   if (_auth.currentUid.value != null) return _auth.currentUid.value;
  //   await _auth.fetchCurrentUid();
  //   return _auth.currentUid.value;
  // }

  @override
  void onClose() {
    _loginWorker?.dispose();
    super.onClose();
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
