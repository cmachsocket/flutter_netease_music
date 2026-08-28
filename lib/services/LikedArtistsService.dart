import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../sdk/api_call.dart';
import '../sdk/api_exception.dart';
import '../sdk/netease_api.dart';

/// 全局"我关注的艺人"服务
///
/// - **持有**: [RxSet] likedArtistIds —— 当前登录用户关注的艺人 id
/// - **持久化**: GetStorage 'liked_artists_v1' —— 启动 hydrate
/// - **API**:
///   - [loadFromServer]  `/artist/sublist?uid=X` 拉全量
///   - [toggle]          `/artist/sub?id=X&t=1|0` 关注/取消
/// - **绑定登录态**: `ever(NeteaseApi.loggedIn, ...)` → 登录自动 load,退出清空
/// - **查询**: [isLiked] —— 调用方**必须包 Obx**才能响应 likedArtistIds 变化
class LikedArtistsService extends GetxService {
  static const _storageKey = 'liked_artists_v1';

  /// 关注的艺人 id 集合(响应式)
  final RxSet<String> likedArtistIds = <String>{}.obs;

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
        likedArtistIds.clear();
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
      likedArtistIds.assignAll(raw.whereType<String>());
    }
  }

  void _persist() {
    GetStorage().write(_storageKey, likedArtistIds.toList());
  }

  /// 查询(id 是否被关注)
  ///
  /// **必须在 Obx 内调用**才能响应 likedArtistIds 变化
  bool isLiked(String id) => likedArtistIds.contains(id);

  /// 从后端拉一次全量 `/artist/sublist?uid=X`
  ///
  /// - 需要已登录
  /// - 响应:`{artists: [{id, name, ...}, ...]}`
  /// - 失败:静默,保留本地 hydrate 的旧数据
  Future<void> loadFromServer() async {
    final uid = _api.currentUid.value;
    if (uid == null) return;
    try {
      final r = await apiCall(
        () => _api.raw.artist_sublist(),
        what: '拉关注艺人',
      );
      final artists = r.body['artists'];
      if (artists is! List) return;
      likedArtistIds.assignAll(
        artists
            .whereType<Map>()
            .map((m) => m['id']?.toString() ?? '')
            .where((s) => s.isNotEmpty),
      );
      _persist();
    } on ApiException {
      // 静默:启动时拉失败不该阻塞 UI
    }
  }

  /// 同步单个艺人的关注状态(从 `/artists?id=X` 响应读 `followed` 字段)
///
/// - **场景**:艺人卡片首次显示时调用一次,把后端真值同步到 [likedArtistIds]
///   (service 启动 hydrate 只拉 `/artist/sublist` 全量,单点 id 没在里面)
/// - **不重复拉**:如果 likedArtistIds 已经包含该 id 且与后端一致,跳过
///   (依靠 likedArtistIds.add/remove 后 likedArtistIds 变,与本方法无关;
///    本方法本身不做节流,调用方保证调用频率合理——例如 widget 首次 build)
/// - **静默失败**:catch ApiException 不拋——同步失败不阻塞 UI
  Future<void> syncSingle(String artistId) async {
    try {
      final r = await apiCall(
        () => _api.raw.artists(artistId),
        what: '同步艺人关注状态',
      );
      final raw = r.body['artist'];
      if (raw is! Map) return;
      final m = Map<String, dynamic>.from(raw);
      final followed = m['followed'];
      if (followed is! bool) return;
      final alreadyIn = likedArtistIds.contains(artistId);
      if (followed && alreadyIn) return;
      if (!followed && !alreadyIn) return;
      if (followed) {
        likedArtistIds.add(artistId);
      } else {
        likedArtistIds.remove(artistId);
      }
      _persist();
    } on ApiException {
      // 静默
    }
  }

  /// toggle 关注(`/artist/sub?id=X&t=1` 关注,`t=0` 取消)
  ///
  /// - 乐观更新:本地先翻面,失败回滚
  /// - 调用方 fire-and-forget
  Future<void> toggle(String artistId) async {
    final wasLiked = likedArtistIds.contains(artistId);
    final next = !wasLiked;
    if (next) {
      likedArtistIds.add(artistId);
    } else {
      likedArtistIds.remove(artistId);
    }
    _persist();
    try {
      await apiCall(
        () => _api.raw.artist_sub(artistId, next ? '1' : '0'),
        what: next ? '关注艺人' : '取消关注',
      );
    } on ApiException catch (e) {
      if (next) {
        likedArtistIds.remove(artistId);
      } else {
        likedArtistIds.add(artistId);
      }
      _persist();
      Get.snackbar(
        next ? '关注失败' : '取消关注失败',
        e.message,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }
}