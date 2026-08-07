import 'package:flutter/widgets.dart' show TextEditingController;
import 'package:get/get.dart';

/// 网易云搜索 type 参数(参考 netease_cloud_music_api /search 接口)
///
/// 只取这四个(用户限定):
/// - 1 单曲
/// - 10 专辑
/// - 100 艺人
/// - 1000 歌单
///
/// 后续接 SDK 时,[typeId] 直接当 query param 传给后端
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

/// 搜索页 controller(持当前 [SearchType])
///
/// 接 SDK 后:加 [keyword] RxString + [results] / [isLoading] / [errorMessage],
/// [setType] / [setKeyword] 触发 SearchController.search(type, keyword) 拉真数据
class SearchController extends GetxController {
  final Rx<SearchType> type = SearchType.song.obs;

  /// TextField 的真实数据源 —— 必须显式绑给 [TextField.controller],
  /// 否则点清除按钮时 [TextField] 内部 state 复用了看不见的 TextEditingController,
  /// keyword 变空但输入框不会清空(看起来没反应)
  final TextEditingController textController = TextEditingController();

  /// 当前搜索关键词的观察者 —— 通过 [textController] listener 自动同步,
  /// 接 SDK 后用 `ever(keyword, ...)` debounce 触发 SearchController.search(type, keyword)
  final RxString keyword = ''.obs;

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

  void search(String Keyword) {}
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
