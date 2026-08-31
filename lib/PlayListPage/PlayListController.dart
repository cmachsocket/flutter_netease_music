import 'package:get/get.dart';

import '../models/Song.dart';
import '../PlayPage/PlayerController.dart';
import '../services/LikedService.dart';
import '../services/PlayQueueService.dart';

/// 播放列表页的 controller
///
/// - 只负责播放列表页的渲染和交互
/// - 实际队列数据由 [PlayQueueService] 维护
/// - like/dislike 走全局 [LikedService] (LikedType.song) (跟 SongListController 同思路)
class PlayListController extends GetxController {
  final PlayQueueService queue = Get.find<PlayQueueService>();
  final LikedService _likedService = Get.find<LikedService>();

  RxList<Song> get playlist => queue.playlist;
  RxInt get currentIndex => queue.currentIndex;
  Rx<PlayMode> get mode => queue.mode;

  /// 选某一首开始播放 —— 走 PlayerController.selectIndex
  ///
  /// - **不直接调 queue.selectIndex**:那个只改 currentIndex,如果值没变
  ///   (`ever<int>` worker 不补 fire,常见场景:点当前正在播的 / 从缓存恢复后
  ///   点 currentIndex 那首),永远不触发 `_syncQueueState` → 不播
  /// - PlayerController.selectIndex 改完 currentIndex 后手动调 `_scheduleQueueSync`,
  ///   无论值变没变都触发一次同步
  void selectIndex(int index) => Get.find<PlayerController>().selectIndex(index);
  void setMode(PlayMode m) => queue.setMode(m);
  int nextIndex() => queue.nextIndex();
  int prevIndex() => queue.prevIndex();
  Future<void> playSong(Song song) => queue.playSong(song);
  Future<void> playSongs(List<Song> songs, {Song? startSong}) =>
      queue.playSongs(songs, startSong: startSong);
  void removeSong(int index) => queue.removeSong(index);

  /// 喜爱切换 → 走全局 [LikedService.toggle](LikedType.song)(乐观更新 + 后端持久化)
  ///
  /// - 跟 [SongListController.toggleFavorite] 同思路
  /// - PlayQueueService 不管喜爱,喜爱是个人状态,不该绑在播放队列上
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
