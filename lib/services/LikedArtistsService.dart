import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../sdk/api_call.dart';
import '../sdk/api_exception.dart';
import '../sdk/netease_api.dart';
import 'liked_collection_service.dart';

/// 全局"我关注的艺人"服务。
class LikedArtistsService extends LikedCollectionService {
  static const _storageKey = 'liked_artists_v1';

  @override
  final RxSet<String> ids = <String>{}.obs;

  @override
  String get storageKey => _storageKey;

  LikedArtistsService(NeteaseApi api) : super(api);

  RxSet<String> get likedArtistIds => ids;

  @override
  Future<void> loadFromServer() async {
    final uid = api.currentUid.value;
    if (uid == null) return;
    try {
      final r = await apiCall(
        () => api.raw.artist_sublist(),
        what: '拉关注艺人',
      );
      final rawArtists = r.body['artists'];
      if (rawArtists is! List) return;
      ids.assignAll(
        rawArtists
            .whereType<Map>()
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
      () => api.raw.artist_sub(id, next ? '1' : '0'),
      what: next ? '关注艺人' : '取消关注',
    );
  }

  /// 同步单个艺人的关注状态。
  Future<void> syncSingle(String artistId) async {
    try {
      final r = await apiCall(
        () => api.raw.artists(artistId),
        what: '同步艺人关注状态',
      );
      final raw = r.body['artist'];
      if (raw is! Map) return;
      final m = Map<String, dynamic>.from(raw);
      final followed = m['followed'];
      if (followed is! bool) return;
      final alreadyIn = ids.contains(artistId);
      if (followed == alreadyIn) return;
      if (followed) {
        ids.add(artistId);
      } else {
        ids.remove(artistId);
      }
      // 通过基类持久化逻辑
      GetStorage().write(storageKey, ids.toList());
    } on ApiException {
      // 静默
    }
  }
}
