import 'package:get/get.dart';

import '../models/Song.dart';
import 'PlayQueueService.dart';

/// 播放列表页的 controller
///
/// - 只负责播放列表页的渲染和交互
/// - 实际队列数据由 [PlayQueueService] 维护
class PlayListController extends GetxController {
  final PlayQueueService queue = Get.find<PlayQueueService>();

  RxList<Song> get playlist => queue.playlist;
  RxInt get currentIndex => queue.currentIndex;

  void selectIndex(int index) => queue.selectIndex(index);
  Future<void> playSong(Song song) => queue.playSong(song);
  Future<void> playSongs(List<Song> songs, {Song? startSong}) =>
      queue.playSongs(songs, startSong: startSong);
  void removeSong(int index) => queue.removeSong(index);
}
