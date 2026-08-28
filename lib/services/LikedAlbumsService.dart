import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../sdk/api_call.dart';
import '../sdk/api_exception.dart';
import '../sdk/netease_api.dart';

/// 全局"我收藏的专辑"服务
///
/// - **持有**: [RxSet] likedAlbumIds —— 当前登录用户收藏的专辑 id
/// - **持久化**: GetStorage 'liked_albums_v1' —— 启动 hydrate
/// - **API**:
///   - [loadFromServer]  `/album/sublist` 拉全量
///   - [toggle]          `/album/sub?id=X&t=1|0` 收藏/取消
/// - **绑定登录态**: `ever(NeteaseApi.loggedIn, ...)` → 登录自动 load,退出清空
/// - **查询**: [isLiked] —— 调用方**必须包 Obx**才能响应 likedAlbumIds 变化
class LikedAlbumsService extends GetxService {
  static const _storageKey = 'liked_albums_v1';

  /// 收藏的专辑 id 集合(响应式)
  final RxSet<String> likedAlbumIds = <String>{}.obs;

  final NeteaseApi _api = Get.find<NeteaseApi>();

  Worker? _loggedInWorker;

  @override
  void onInit() {
    super.onInit();
    _hydrate();
    _loggedInWorker = ever<bool>(_api.loggedIn, (loggedIn) {
      if (loggedIn) {
        // ignore: discarded_futures
        loadFromServer();
      } else {
        likedAlbumIds.clear();
        _persist();
      }
    });
    if (_api.loggedIn.value) {
      // ignore: discarded_futures
      loadFromServer();
    }
  }

  @override
  void onClose() {
    _loggedInWorker?.dispose();
    super.onClose();
  }

  void _hydrate() {
    final raw = GetStorage().read<List>(_storageKey);
    if (raw != null) {
      likedAlbumIds.assignAll(raw.whereType<String>());
    }
  }

  void _persist() {
    GetStorage().write(_storageKey, likedAlbumIds.toList());
  }

  /// 查询(id 是否被收藏)
  bool isLiked(String id) => likedAlbumIds.contains(id);

  /// 从后端拉一次全量 `/album/sublist`
  ///
  /// 响应:`{data: [{id, name, ...}, ...]}`(顶层 data,跟 /artist/sublist 不同)
  Future<void> loadFromServer() async {
    if (!_api.loggedIn.value) return;
    try {
      final r = await apiCall(
        () => _api.raw.album_sublist(),
        what: '拉收藏专辑',
      );
      // 网易云 /album/sublist 响应顶层 data(列表) + hasMore(分页)
      final list = r.body['data'];
      if (list is! List) return;
      likedAlbumIds.assignAll(
        list
            .whereType<Map>()
            .map((m) => m['id']?.toString() ?? '')
            .where((s) => s.isNotEmpty),
      );
      _persist();
    } on ApiException {
      // 静默:启动时拉失败不该阻塞 UI
    }
  }

  /// toggle 收藏(`/album/sub?id=X&t=1` 收藏,`t=0` 取消)
  Future<void> toggle(String albumId) async {
    final wasLiked = likedAlbumIds.contains(albumId);
    final next = !wasLiked;
    if (next) {
      likedAlbumIds.add(albumId);
    } else {
      likedAlbumIds.remove(albumId);
    }
    _persist();
    try {
      await apiCall(
        () => _api.raw.album_sub(albumId, next ? '1' : '0'),
        what: next ? '收藏专辑' : '取消收藏',
      );
    } on ApiException catch (e) {
      if (next) {
        likedAlbumIds.remove(albumId);
      } else {
        likedAlbumIds.add(albumId);
      }
      _persist();
      Get.snackbar(
        next ? '收藏失败' : '取消收藏失败',
        e.message,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }
}