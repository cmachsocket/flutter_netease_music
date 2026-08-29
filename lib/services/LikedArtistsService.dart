import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import 'liked_collection_service.dart';
import '../controller/AuthController.dart';
import 'repositories/liked_repository.dart';

/// 全局"我关注的艺人"服务。
///
/// API 调用 (`artist_sublist` / `artist_sub` / `artists` 同步单个) 集中在
/// [LikedArtistsRepository]。service 只保留 likedArtistIds RxSet + 持久化 +
/// 登录态联动 + 乐观更新 + snackbar。
class LikedArtistsService extends LikedCollectionService {
  static const _storageKey = 'liked_artists_v1';

  @override
  final RxSet<String> ids = <String>{}.obs;

  @override
  String get storageKey => _storageKey;

  late final LikedRepository _repo = Get.find<LikedRepository>();
  late final AuthController _auth = Get.find<AuthController>();

  LikedArtistsService() : super();

  RxSet<String> get likedArtistIds => ids;

  @override
  Future<void> loadFromServer() async {
    final uid = _auth.currentUid;
    if (uid == 0) ;
    final fetched = await _repo.fetchLikedArtistIds();
    if (fetched == null) return; // 静默
    ids.assignAll(fetched);
  }

  @override
  Future<void> toggleApi(String id, bool next) =>
      _repo.toggleArtistSub(id, next);

  /// 同步单个艺人的关注状态。
  ///
  /// 业务逻辑保留在这里 (id 在 RxSet 里的修改 + 持久化);
  /// API 调用 (`artists`) 在 [LikedArtistsRepository.fetchFollowed]。
  Future<void> syncSingle(String artistId) async {
    final followed = await _repo.fetchFollowed(artistId);
    if (followed == null) return; // 静默
    final alreadyIn = ids.contains(artistId);
    if (followed == alreadyIn) return;
    if (followed) {
      ids.add(artistId);
    } else {
      ids.remove(artistId);
    }
    GetStorage().write(storageKey, ids.toList());
  }
}
