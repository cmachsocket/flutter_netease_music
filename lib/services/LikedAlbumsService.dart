import 'package:get/get.dart';

import 'liked_collection_service.dart';
import '../controller/AuthController.dart';
import 'repositories/liked_repository.dart';

/// 全局"我收藏的专辑"服务。
///
/// API 调用 (`album_sublist` / `album_sub`) 集中在 [LikedAlbumsRepository]。
/// service 只保留 likedAlbumIds RxSet + 持久化 + 登录态联动 + 乐观更新 + snackbar。
class LikedAlbumsService extends LikedCollectionService {
  static const _storageKey = 'liked_albums_v1';

  @override
  final RxSet<String> ids = <String>{}.obs;

  @override
  String get storageKey => _storageKey;

  late final LikedRepository _repo = Get.find<LikedRepository>();
  late final AuthController _auth = Get.find<AuthController>();

  LikedAlbumsService() : super();

  RxSet<String> get likedAlbumIds => ids;

  @override
  Future<void> loadFromServer() async {
    if (!_auth.loggedIn) return;
    final fetched = await _repo.fetchLikedAlbumIds();
    if (fetched == null) return; // 静默:启动时拉失败不该阻塞 UI
    ids.assignAll(fetched);
  }

  @override
  Future<void> toggleApi(String id, bool next) =>
      _repo.toggleAlbumSub(id, next);
}
