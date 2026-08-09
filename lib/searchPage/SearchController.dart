import 'package:flutter/widgets.dart' show TextEditingController;
import 'package:get/get.dart';

import '../models/Album.dart';
import '../models/Song.dart';
import '../ArtistPage/Artist.dart';
import '../sdk/api_exception.dart';
import '../sdk/netease_api.dart';

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

  /// TextField 的真实数据源 —— 必须显式绑给 [TextField.controller],
  /// 否则点清除按钮时 [TextField] 内部 state 复用了看不见的 TextEditingController,
  /// keyword 变空但输入框不会清空(看起来没反应)
  final TextEditingController textController = TextEditingController();

  /// 当前输入框的关键词
  final RxString keyword = ''.obs;

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
  }

  /// 切换 tab:有 keyword 就自动重搜,空 keyword 直接清空对应结果
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
      return;
    }
    isLoading.value = true;
    errorMessage.value = null;
    final api = Get.find<NeteaseApi>();
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
