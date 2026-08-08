import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:get/get.dart';

import '../models/Album.dart';
import '../models/Song.dart';
import '../sdk/api_exception.dart';
import '../sdk/netease_api.dart';
import 'Artist.dart';

/// 艺人页 controller
///
/// - 一位艺人一个实例(由 [artistId] 区分);路由 pop 时随 binding 自动销毁
/// - [load] 并行拉 `artists` / `artist_album` / `artist_songs` 三个接口
class ArtistController extends GetxController {
  ArtistController({required this.artistId});

  /// 路由传进来的艺人 ID
  final String artistId;

  final Rxn<Artist> artist = Rxn<Artist>();
  final RxList<Album> albums = <Album>[].obs;
  final RxList<Song> songs = <Song>[].obs;
  final RxBool isLoading = false.obs;
  final RxnString errorMessage = RxnString();
  final RxBool isFollowing = false.obs;

  /// 0 = 专辑 / EP 网格;1 = 所有歌曲列表
  final RxInt viewIndex = 0.obs;

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
    final api = Get.find<NeteaseApi>();
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
        final m = r.body;
        if (m.isNotEmpty) artist.value = Artist.fromNeteaseJson(m);
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

  void setView(int index) => viewIndex.value = index;

  void toggleFollow() {
    isFollowing.toggle();
  }

  void toggleFavorite(String songId) {
    // TODO: 接 PlayListController 持久化 + 联动 PlayerController
  }

  void playSong(Song song) {
    // TODO: 联动 PlayListController + PlayerController
  }
}
