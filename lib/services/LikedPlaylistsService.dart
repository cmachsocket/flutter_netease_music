import 'package:get/get.dart';

import 'liked_collection_service.dart';
import '../controller/AuthController.dart';
import 'repositories/liked_repository.dart';

/// 全局"我收藏的歌单"服务。
///
/// API 调用 (`user_playlist` / `playlist_subscribe`) 集中在
/// [LikedPlaylistsRepository]。service 只保留 likedPlaylistIds RxSet + 持久化 +
/// 登录态联动 + 乐观更新 + snackbar。
class LikedPlaylistsService extends LikedCollectionService {
  static const _storageKey = 'liked_playlists_v1';

  @override
  final RxSet<String> ids = <String>{}.obs;

  @override
  String get storageKey => _storageKey;

  late final LikedRepository _repo = Get.find<LikedRepository>();
  late final AuthController _auth = Get.find<AuthController>();

  LikedPlaylistsService() : super();

  RxSet<String> get likedPlaylistIds => ids;

  @override
  Future<void> loadFromServer() async {
    final uid = _auth.currentUid;
    if (uid == 0) return;
    final fetched = await _repo.fetchLikedPlaylistIds(uid.toString());
    if (fetched == null) return; // 静默
    ids.assignAll(fetched);
  }

  @override
  Future<void> toggleApi(String id, bool next) =>
      _repo.togglePlaylistSubscribe(id, next);
}
