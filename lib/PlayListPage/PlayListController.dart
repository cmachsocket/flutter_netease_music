import 'package:get/get.dart';
import '../models/Snapshot.dart' show PlayOrder;
import '../models/Song.dart';
import '../services/LikedService.dart';
import '../services/AudioPlayerWrapper.dart';

/// 播放列表页的 controller
///
/// - 只负责播放列表页的渲染和交互
/// - 实际队列数据由 [AudioPlayerService] 维护(wrapper 吸收了老 PlayQueueService)
/// - like/dislike 走全局 [LikedService] (LikedType.song) (跟 SongListController 同思路)
class PlayListController extends GetxController {
  final AudioPlayerService queue = Get.find<AudioPlayerService>();
  final LikedService _likedService = Get.find<LikedService>();

  RxList<Song> get playlist => queue.playlist;
  RxInt get currentIndex => queue.currentIndex;
  Rx<PlayOrder> get mode => queue.mode;

  /// 选某一首开始播放 —— 走 [AudioPlayerService.selectIndex],
  /// wrapper.handler 内部 skipToQueueItem → _playAt → fetch URL → setUrl
  /// → mediaItem.add 流回推 snapshot,UI 通过 snapshot.currentSong 自动刷新
  ///
  /// 之前是 Get.find<PlayerController>().selectIndex(index) (绕一层 facade),
  /// 现在 PlayerController.selectIndex 只是 wrapper 的薄转发,中间这层没意义,
  /// PlayListController 直接调 wrapper,避免业务路径拉长。
  void selectIndex(int index) => queue.selectIndex(index);
  void setMode(PlayOrder m) => queue.setPlayOrder(m);
  int nextIndex() => queue.nextIndex();
  int prevIndex() => queue.prevIndex();
  Future<void> playSong(Song song) => queue.playSong(song);
  Future<void> playSongs(List<Song> songs, {Song? startSong}) =>
      queue.playSongs(songs, startSong: startSong);
  void removeSong(int index) => queue.removeSong(index);

  /// 喜爱切换 → 走全局 [LikedService.toggle](LikedType.song)(乐观更新 + 后端持久化)
  ///
  /// - 跟 [SongListController.toggleFavorite] 同思路
  /// - wrapper 不管喜爱,喜爱是个人状态,不该绑在播放队列上
  void toggleFavorite(String songId) {
    // ignore: discarded_futures
    _likedService.toggle(songId, LikedType.song);
  }

  /// 查询某首歌是否被喜欢
  ///
  /// - 调用方**必须包 Obx**才能响应 likedSongIds 变化
  /// - 转发到 [LikedService.isLiked] (内部走 likedSongIds.value.contains 触发 Obx 跟踪)
  bool isLiked(String songId) => _likedService.isLiked(songId, LikedType.song);
}
