import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../SongListPage/SongListBody.dart';
import 'PlayListController.dart';

/// 播放列表页
///
/// - 数据来自 [PlayListController.playlist] (RxList,外面套 Obx 才会响应)
/// - 复用 [SongListBody] 默认 [SongRowTile] (fav + play 双按钮)
/// - 喜爱 / 不喜爱走 [PlayListController.isLiked] / [PlayListController.toggleFavorite]
///   (委托到全局 [LikedSongsService])
class PlayListPage extends StatelessWidget {
  const PlayListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<PlayListController>();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        Get.back();
        return;
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: () => Get.back(),
            icon: const Icon(Icons.arrow_back),
          ),
          title: const Text('播放列表'),
        ),
        body: Obx(() {
          // playlist / likedIds 变化都会触发整个列表重建
          // SongRowTile 内部 Obx 进一步控制 fav button 精细重建
          return SongListBody(
            songs: controller.playlist.toList(),
            isLoading: false,
            // SongListBody.onPlay 收 Song；controller.selectIndex 收 int
            onPlay: (song) {
              final list = controller.playlist;
              final i = list.indexWhere((s) => s.id == song.id);
              if (i >= 0) controller.selectIndex(i);
            },
            // 喜爱 / 不喜爱 (isLiked 内部读 likedIds.value → Obx 跟踪)
            isLiked: (song) => controller.isLiked(song.id),
            onToggleFavorite: (song) => controller.toggleFavorite(song.id),
          );
        }),
      ),
    );
  }
}

class PlayListBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PlayListController>(() => PlayListController());
  }
}
