import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../sdk/api_call.dart';
import '../sdk/api_exception.dart';
import '../sdk/netease_api.dart';

/// 全局"我收藏的歌单"服务
///
/// - **持有**: [RxSet] likedPlaylistIds —— 当前登录用户收藏的歌单 id(不含自己创建)
/// - **持久化**: GetStorage 'liked_playlists_v1' —— 启动 hydrate
/// - **API**:
///   - [loadFromServer]  `/user/playlist?uid=X` 全量,过滤 `subscribed=true`
///   - [toggle]          `/playlist/subscribe?t=1|id=X` 收藏,`t=2` 取消
/// - **绑定登录态**: `ever(NeteaseApi.loggedIn, ...)` → 登录自动 load,退出清空
/// - **查询**: [isLiked] —— 调用方**必须包 Obx**才能响应 likedPlaylistIds 变化
///
/// 为什么用 `/user/playlist` 而不是单独的"收藏歌单"接口:
/// 网易云没单独的 `/playlist/collected`,但 `/user/playlist` 同时返回自建+收藏,
/// 每项带 `subscribed` 标志(自建=false,收藏=true)—— 过滤一次就行
class LikedPlaylistsService extends GetxService {
  static const _storageKey = 'liked_playlists_v1';

  /// 收藏的歌单 id 集合(响应式)
  final RxSet<String> likedPlaylistIds = <String>{}.obs;

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
        likedPlaylistIds.clear();
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
      likedPlaylistIds.assignAll(raw.whereType<String>());
    }
  }

  void _persist() {
    GetStorage().write(_storageKey, likedPlaylistIds.toList());
  }

  /// 查询(id 是否被收藏)
  bool isLiked(String id) => likedPlaylistIds.contains(id);

  /// 从 `/user/playlist?uid=X` 拉全量,过滤 `subscribed=true`
  Future<void> loadFromServer() async {
    final uid = _api.currentUid.value;
    if (uid == null) return;
    try {
      final r = await apiCall(
        () => _api.raw.user_playlist(uid.toString()),
        what: '拉收藏歌单',
      );
      final list = r.body['playlist'];
      if (list is! List) return;
      likedPlaylistIds.assignAll(
        list
            .whereType<Map>()
            .where((m) => m['subscribed'] == true)
            .map((m) => m['id']?.toString() ?? '')
            .where((s) => s.isNotEmpty),
      );
      _persist();
    } on ApiException {
      // 静默
    }
  }

  /// toggle 收藏(`/playlist/subscribe?t=1&id=X` 收藏,`t=2&id=X` 取消)
  Future<void> toggle(String playlistId) async {
    final wasLiked = likedPlaylistIds.contains(playlistId);
    final next = !wasLiked;
    if (next) {
      likedPlaylistIds.add(playlistId);
    } else {
      likedPlaylistIds.remove(playlistId);
    }
    _persist();
    try {
      await apiCall(
        () => _api.raw.playlist_subscribe(next ? '1' : '2', playlistId),
        what: next ? '收藏歌单' : '取消收藏',
      );
    } on ApiException catch (e) {
      if (next) {
        likedPlaylistIds.remove(playlistId);
      } else {
        likedPlaylistIds.add(playlistId);
      }
      _persist();
      Get.snackbar(
        next ? '收藏歌单失败' : '取消收藏失败',
        e.message,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }
}