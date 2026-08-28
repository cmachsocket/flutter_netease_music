import 'package:get/get.dart';

import '../sdk/api_call.dart';
import '../sdk/api_exception.dart';
import '../sdk/netease_api.dart';
import 'liked_collection_service.dart';

/// 全局"我喜欢的歌曲"服务。
class LikedSongsService extends LikedCollectionService {
  static const _storageKey = 'liked_songs_v1';

  @override
  final RxSet<String> ids = <String>{}.obs;

  @override
  String get storageKey => _storageKey;

  LikedSongsService(NeteaseApi api) : super(api);

  RxSet<String> get likedIds => ids;

  @override
  Future<void> loadFromServer() async {
    final uid = api.currentUid.value;
    if (uid == null) return;
    try {
      final r = await apiCall(
        () => api.raw.likelist(uid.toString()),
        what: '拉喜欢列表',
      );
      final rawIds = r.body['ids'];
      if (rawIds is! List) return;
      ids.assignAll(rawIds.whereType<int>().map((i) => i.toString()));
    } on ApiException {
      // 静默
    }
  }

  @override
  Future<void> toggleApi(String id, bool next) async {
    await apiCall(
      () => api.raw.like(id, like: next.toString()),
      what: next ? '喜欢歌曲' : '取消喜欢',
    );
  }
}
