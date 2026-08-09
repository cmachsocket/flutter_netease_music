import 'package:get/get.dart';

import '../models/Song.dart';
import '../PlayListPage/PlayQueueService.dart';
import '../sdk/api_exception.dart';
import '../sdk/netease_api.dart';

/// 歌单详情页 controller
///
/// - 一张歌单一个实例(由 [playlistId] 区分);路由 pop 时随 binding 自动销毁
/// - 数据模型走 [Song](已抽到 ../models/Song.dart)
/// - 接 SDK 后:[load] 调 `/playlist/detail` 拿歌单元信息 + `/playlist/track/all`
///   拿所有曲目(因为 playlist_detail 只返前 1000 首,track_all 才能拿全)
class SongListController extends GetxController {
  SongListController({required this.playlistId});

  /// 路由传进来的歌单 ID
  final String playlistId;

  final NeteaseApi api = Get.find<NeteaseApi>();
  final PlayQueueService queue = Get.find<PlayQueueService>();

  final RxList<Song> songs = <Song>[].obs;
  final RxBool isLoading = false.obs;
  final RxnString errorMessage = RxnString();

  /// 歌单标题(从 playlist_detail 取)
  final RxnString title = RxnString();

  /// 歌单封面(从 playlist_detail 取)
  final RxnString coverUrl = RxnString();

  /// 歌单描述(从 playlist_detail 取)
  final RxnString description = RxnString();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  /// 拉当前歌单 ([playlistId]) 的元信息 + 曲目
  ///
  /// 两个调用并行(互不依赖):detail 拿标题/封面,track_all 拿完整曲目
  Future<void> load() async {
    isLoading.value = true;
    errorMessage.value = null;
    final id = playlistId;
    try {
      // 1. 拉歌单元信息(标题/封面/描述)
      try {
        final detail = await api.call(
          (a) => a.playlist_detail(id),
          what: '拉歌单详情',
        );
        final playlist = detail.body['playlist'];
        if (playlist is Map) {
          final p = Map<String, dynamic>.from(playlist);
          title.value = (p['name'] ?? '').toString();
          coverUrl.value = (p['coverImgUrl'] ?? '').toString();
          description.value = (p['description'] ?? '').toString();
        }
      } on ApiException {
        // 元信息失败不影响曲目展示,继续往下走
      }

      // 2. 拉所有曲目(track_all 而非 detail.tracks,后者只返前 1000 首)
      final tracks = await api.call(
        (a) => a.playlist_track_all(id),
        what: '拉歌单曲目',
      );
      final songsList = tracks.body['songs'];
      if (songsList is List) {
        songs.assignAll(
          songsList
              .whereType<Map>()
              .map((m) => Song.fromNeteaseJson(Map<String, dynamic>.from(m)))
              .toList(),
        );
      }
    } on ApiException catch (e) {
      errorMessage.value = e.message;
    } finally {
      isLoading.value = false;
    }
  }

  /// 喜爱切换(占位)。后续可挂 [RxSet<String>] 持久化 + 联动 PlayListController 真正切换
  void toggleFavorite(String songId) {
    // TODO: 接 controller.toggleFavorite(songId);接 player 那边通知
  }

  /// 播放当前歌单里的某首歌:把整个歌单作为播放列表，再从这首开始播。
  Future<void> playSong(Song song) {
    return queue.playSongs(songs.toList(), startSong: song);
  }

  /// 播放整张歌单:从第一首开始。
  Future<void> playAll() {
    return queue.playSongs(songs.toList());
  }
}

class SongListBinding extends Bindings {
  @override
  void dependencies() {
    // 不带参数:参数在 [SongListDetailBinding] 里走(那边拿 playlistId)
  }
}
