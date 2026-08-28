import 'package:get/get.dart';

import '../sdk/api_call.dart';
import '../sdk/api_exception.dart';
import '../sdk/netease_api.dart';
import 'liked_collection_service.dart';

/// 全局"我收藏的歌单"服务。
class LikedPlaylistsService extends LikedCollectionService {
  static const _storageKey = 'liked_playlists_v1';

  @override
  final RxSet<String> ids = <String>{}.obs;

  @override
  String get storageKey => _storageKey;

  LikedPlaylistsService(NeteaseApi api) : super(api);

  RxSet<String> get likedPlaylistIds => ids;

  @override
  Future<void> loadFromServer() async {
    final uid = api.currentUid.value;
    if (uid == null) return;
    try {
      final r = await apiCall(
        () => api.raw.user_playlist(uid.toString()),
        what: '拉收藏歌单',
      );
      final list = r.body['playlist'];
      if (list is! List) return;
      ids.assignAll(
        list
            .whereType<Map>()
            .where((m) => m['subscribed'] == true)
            .map((m) => m['id']?.toString() ?? '')
            .where((s) => s.isNotEmpty),
      );
    } on ApiException {
      // 静默
    }
  }

  @override
  Future<void> toggleApi(String id, bool next) async {
    await apiCall(
      () => api.raw.playlist_subscribe(next ? '1' : '2', id),
      what: next ? '收藏歌单' : '取消收藏',
    );
  }
}
