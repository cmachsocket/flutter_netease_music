import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../sdk/api_call.dart';
import '../sdk/api_exception.dart';
import '../sdk/netease_api.dart';

/// 全局"我喜欢的歌曲"服务
///
/// - **持有**: [RxSet] likedIds —— 当前登录用户的喜欢 id 集合
/// - **持久化**: GetStorage 'liked_songs_v1' —— 启动 hydrate,变化即写盘
/// - **API**:
///   - [loadFromServer]  `/likelist?uid=X` 拉全量(登录后必调)
///   - [toggle]          `/like?id=X&like=true|false` toggle + 乐观更新
/// - **绑定登录态**: `ever(NeteaseApi.loggedIn, ...)` → 登录自动 load,退出清空
/// - **查询**: [isLiked] —— 调用方**必须包 Obx**才能响应 likedIds 变化
///
/// 为什么用 GetxService(不是普通 controller):
/// - 跨路由单例(SongListDetail / Player / BottomPlayer 都要查)
/// - 生命周期跟整个 app(NeteaseApi 同款)
class LikedSongsService extends GetxService {
  static const _storageKey = 'liked_songs_v1';

  /// 当前用户的喜欢 id 集合(响应式)
  final RxSet<String> likedIds = <String>{}.obs;

  final NeteaseApi _api = Get.find<NeteaseApi>();

  Worker? _loggedInWorker;

  @override
  void onInit() {
    super.onInit();
    _hydrate();
    // 登录态变化 → 自动同步 likedIds
    _loggedInWorker = ever<bool>(_api.loggedIn, (loggedIn) {
      if (loggedIn) {
        // ignore: discarded_futures
        loadFromServer();
      } else {
        likedIds.clear();
        _persist();
      }
    });
    // 启动时如果已经登录(冷启动 hydrate),主动 load 一次
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
      likedIds.assignAll(raw.whereType<String>());
    }
  }

  void _persist() {
    GetStorage().write(_storageKey, likedIds.toList());
  }

  /// 查询(id 是否在喜欢列表里)
  ///
  /// **必须在 Obx 内调用**才能响应 likedIds 变化
  bool isLiked(String id) => likedIds.contains(id);

  /// 从后端拉一次全量 likedIds(`/likelist?uid=X`)
  ///
  /// - 需要已登录(否则后端 400)
  /// - 失败:静默,保留本地 hydrate 的旧数据
  Future<void> loadFromServer() async {
    final uid = _api.currentUid.value;
    if (uid == null) return;
    try {
      final r = await apiCall(
        () => _api.raw.likelist(uid.toString()),
        what: '拉喜欢列表',
      );
      final ids = r.body['ids'];
      if (ids is! List) return;
      likedIds.assignAll(
        ids.whereType<int>().map((i) => i.toString()),
      );
      _persist();
    } on ApiException {
      // 静默:启动时拉失败不该阻塞 UI
    }
  }

  /// toggle 一首(喜欢 ↔ 取消)
  ///
  /// - **乐观更新**:本地 likedIds 先翻面,后端失败再回滚 + snackbar
  /// - 调用方 fire-and-forget,不阻塞 UI
  Future<void> toggle(String songId) async {
    final wasLiked = likedIds.contains(songId);
    final next = !wasLiked;
    // 乐观更新
    if (next) {
      likedIds.add(songId);
    } else {
      likedIds.remove(songId);
    }
    _persist();
    try {
      await apiCall(
        () => _api.raw.like(songId, like: next.toString()),
        what: next ? '喜欢歌曲' : '取消喜欢',
      );
    } on ApiException catch (e) {
      // 回滚
      if (next) {
        likedIds.remove(songId);
      } else {
        likedIds.add(songId);
      }
      _persist();
      Get.snackbar(
        next ? '喜欢失败' : '取消喜欢失败',
        e.message,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }
}