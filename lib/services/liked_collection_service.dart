import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../models/ApiException.dart';
import '../controller/AuthController.dart';

/// 收藏集合基类 —— 抽出 Liked Songs/Albums/Artists/Playlists 的公共骨架。
///
/// 子类只需提供:
/// - [ids] 响应式 id 集合 (子类自己的 RxSet)
/// - [storageKey] 持久化 key
/// - [loadFromServer] 全量拉取
/// - [toggleApi] 单个 toggle 的 API 调用
///
/// 公共逻辑 (hydrate / persist / 登录态联动 / isLiked / toggle 乐观更新) 全部在基类。
abstract class LikedCollectionService extends GetxService {
  final AuthController _auth = Get.find<AuthController>();

  LikedCollectionService();

  /// 子类持有的响应式 id 集合。
  abstract final RxSet<String> ids;

  /// GetStorage 持久化 key。
  abstract final String storageKey;

  Worker? _loggedInWorker;

  @override
  void onInit() {
    super.onInit();
    _hydrate();
    _loggedInWorker = ever(_auth.authInfo, (info) {
      if (info.loggedIn) {
        // ignore: discarded_futures
        loadFromServer();
      } else {
        ids.clear();
        _persist();
      }
    });
    if (_auth.loggedIn) {
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
    final raw = GetStorage().read<List>(storageKey);
    if (raw != null) {
      ids.assignAll(raw.whereType<String>());
    }
  }

  void _persist() {
    GetStorage().write(storageKey, ids.toList());
  }

  /// 查询 id 是否已收藏。调用方必须在 Obx 内调用才能响应式刷新。
  bool isLiked(String id) => ids.contains(id);

  /// 从后端拉全量收藏 id。
  Future<void> loadFromServer();

  /// 执行单个收藏/取消收藏 API 调用。
  Future<void> toggleApi(String id, bool next);

  /// toggle 收藏（乐观更新 + 失败回滚 + snackbar）。
  Future<void> toggle(String id) async {
    final wasLiked = ids.contains(id);
    final next = !wasLiked;
    if (next) {
      ids.add(id);
    } else {
      ids.remove(id);
    }
    _persist();
    try {
      await toggleApi(id, next);
    } on ApiException catch (e) {
      if (next) {
        ids.remove(id);
      } else {
        ids.add(id);
      }
      _persist();
      Get.snackbar(
        next ? '操作失败' : '取消失败',
        e.message,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }
}
