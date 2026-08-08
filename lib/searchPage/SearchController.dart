import 'package:flutter/widgets.dart' show TextEditingController;
import 'package:get/get.dart';

import '../models/Song.dart';
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

/// 搜索页 controller(持当前 [SearchType] + 搜索结果)
///
/// - [keyword] / [type] / [results] / [isLoading] 全部响应式
/// - [search] 调 SDK [NeteaseCloudMusicApi.search],结果按当前 type 解析
/// - **当前 stub**:只支持 `song` 类型结果解析(其它 type 等 SearchPage UI 加对应展示时再做)
class SearchController extends GetxController {
  final Rx<SearchType> type = SearchType.song.obs;

  /// TextField 的真实数据源 —— 必须显式绑给 [TextField.controller],
  /// 否则点清除按钮时 [TextField] 内部 state 复用了看不见的 TextEditingController,
  /// keyword 变空但输入框不会清空(看起来没反应)
  final TextEditingController textController = TextEditingController();

  // 显式 onChanged: (s) => controller.setKeyword(s), 绑定 keyword,
  // 点清除按钮时同步清空 keyword
  final RxString keyword = ''.obs;

  /// 搜索结果(只缓存当前 type 的)
  final RxList<Song> results = <Song>[].obs;

  /// 搜索进行中
  final RxBool isLoading = false.obs;

  /// 错误信息(给 UI 显示)
  final RxnString errorMessage = RxnString();

  @override
  void onClose() {
    textController.dispose();
    super.onClose();
  }

  void setType(SearchType t) => type.value = t;
  void setKeyword(String k) => keyword.value = k;

  /// 清除按钮:直接清 textController,listener 会自动同步 keyword
  void clearKeyword() {
    textController.clear();
    keyword.value = '';
  }

  /// 触发搜索
  ///
  /// - 空关键词 → 直接清空结果返回
  /// - 调 SDK /search,根据 [type] 解析对应字段(目前只实现 song)
  /// - 失败抛 [ApiException](已 SnackBar 提示),results 保留旧值
  void search(String Keyword) async {
    keyword.value = Keyword.trim();
    final k = keyword.value;
    if (k.isEmpty) {
      results.clear();
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
      results.assignAll(_parseResults(r.body, t));
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

  /// 根据 type 从 SDK 返回的 body 里取对应列表
  ///
  /// 网易云搜索返回结构:body['result']['songs' / 'albums' / 'artists' / 'playlists']
  List<Song> _parseResults(Map<String, dynamic> body, SearchType t) {
    final result = body['result'];
    if (result is! Map) return const [];
    final list = result[_resultKey(t)];
    if (list is! List) return const [];
    if (t == SearchType.song) {
      return list
          .whereType<Map>()
          .map((m) => Song.fromNeteaseJson(Map<String, dynamic>.from(m)))
          .toList();
    }
    // album / artist / playlist 类型目前只展示歌曲结果,后续 UI 加展示时再补
    return const [];
  }

  static String _resultKey(SearchType t) => switch (t) {
    SearchType.song => 'songs',
    SearchType.album => 'albums',
    SearchType.artist => 'artists',
    SearchType.playlist => 'playlists',
  };
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
