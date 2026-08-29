import 'package:get/get.dart';

import '../models/ApiException.dart';
import '../sdk/netease_api.dart';

/// 首页 controller
///
/// - **推荐歌单**:调 `/personalized`(无需登录),默认拉 30 张
/// - **每日推荐 / 私人 FM**:需登录,本地有 [NeteaseApi.loggedIn] 时展示入口卡,
///   未登录展示"请先登录"占位
class HomeController extends GetxController {
  final RxBool isLoading = false.obs;
  final RxnString errorMessage = RxnString();

  final NeteaseApi api = Get.find<NeteaseApi>();

  /// 推荐歌单卡片数据
  final RxList<PlaylistCard> recommended = <PlaylistCard>[].obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  /// 拉推荐歌单(无需登录)
  Future<void> load() async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
      final r = await api.call(
        (a) => a.personalized(limit: '30'),
        what: '推荐歌单',
      );
      final list = r.body['result'];
      if (list is List) {
        recommended.assignAll(
          list
              .whereType<Map>()
              .map(
                (m) =>
                    PlaylistCard.fromNeteaseJson(Map<String, dynamic>.from(m)),
              )
              .toList(),
        );
      }
    } on ApiException catch (e) {
      errorMessage.value = e.message;
    } finally {
      isLoading.value = false;
    }
  }
}

/// 推荐歌单卡片数据(给 HomePage 用)
class PlaylistCard {
  final String id;
  final String name;
  final String picUrl;

  const PlaylistCard({
    required this.id,
    required this.name,
    required this.picUrl,
  });

  /// 网易云 `/personalized` 返回的 `result` 数组元素:
  /// - id: u64 / str
  /// - name: 歌单名
  /// - picUrl: 封面图(可空)
  factory PlaylistCard.fromNeteaseJson(Map<String, dynamic> json) =>
      PlaylistCard(
        id: json['id'].toString(),
        name: (json['name'] ?? '').toString(),
        picUrl: (json['picUrl'] ?? '').toString(),
      );
}
