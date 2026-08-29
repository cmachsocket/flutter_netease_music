import 'package:get/get.dart';

import 'liked_collection_service.dart';
import '../controller/AuthController.dart';
import 'repositories/liked_repository.dart';

/// 全局"我喜欢的歌曲"服务。
///
/// API 调用 (`likelist` / `like`) 集中在 [LikedSongsRepository]。
/// service 只保留 likedIds RxSet + 持久化 + 登录态联动 + 乐观更新 + snackbar。
class LikedSongsService extends LikedCollectionService {
  static const _storageKey = 'liked_songs_v1';

  @override
  final RxSet<String> ids = <String>{}.obs;

  @override
  String get storageKey => _storageKey;

  late final LikedRepository _repo = Get.find<LikedRepository>();
  late final AuthController _auth = Get.find<AuthController>();

  LikedSongsService() : super();

  RxSet<String> get likedIds => ids;

  @override
  Future<void> loadFromServer() async {
    final uid = _auth.currentUid;
    if (uid == 0) return;
    final fetched = await _repo.fetchLikedSongIds(uid.toString());
    if (fetched == null) return; // 静默
    ids.assignAll(fetched);
  }

  @override
  Future<void> toggleApi(String id, bool next) => _repo.toggleLike(id, next);
}
