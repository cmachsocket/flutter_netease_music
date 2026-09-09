import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/Song.dart';
import '../SongListPage/SongRowTile.dart';
import 'PlayListController.dart';

/// 播放列表页 —— 显示当前 AudioPlayerService.playlist(已加载的播放队列)。
///
/// **数据源**:`PlayListController.playlist` getter 转发到 `AudioPlayerService.playlist`
/// (RxList&lt;Song&gt;)。wrapper 是真相源,handler 的 `_onQueue` 流回推时 UI 自动 rebuild。
///
/// **不调后端**:跟 [SongListBody] 走的"binding + 后端拉歌"路径完全不同
/// —— 这里是已经存在的 wrapper.playlist,直接渲染即可。
///
/// **为什么不用 [SongListBody]**:
/// `SongListBody` 设计为绑定 [SongListBodyController] + 调后端(或自定义钩子),
/// 而播放队列数据已经在 `AudioPlayerService.playlist`,硬塞进 SongListBody
/// 会让 controller 失去"唯一真相源"的清晰边界 —— 谁负责维护 songs?
/// `AudioPlayerService` 还是 `SongListBodyController`?答案是前者。
///
/// **架构边界**:
/// - AudioPlayerService.playlist: 当前播放队列(handler 维护)
/// - PlayListController: facade,转 commands 给 wrapper
/// - PlayListPage: 渲染,读 playlist + 转发点击事件
class PlayListPage extends StatelessWidget {
  const PlayListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<PlayListController>();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Get.back(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('播放列表'),
      ),
      body: Obx(() {
        // 整个播放队列:每次 handler 的 _onQueue emit 都会触发 rebuild
        final List<Song> playlist = controller.playlist.toList(growable: false);
        final int currentIndex = controller.currentIndex.value;

        if (playlist.isEmpty) {
          return const Center(child: Text('暂无歌曲'));
        }
        return ListView.builder(
          itemCount: playlist.length,
          itemBuilder: (context, index) {
            final song = playlist[index];
            return SongRowTile(
              song: song,
              selected: index == currentIndex,
              onPlay: () => controller.selectIndex(index),
              onToggleFavorite: () => controller.toggleFavorite(song.id),
              isLiked: () => controller.isLiked(song.id),
              extraTrailing: () => RemoveIconButton(
                song: song,
                index: index,
              ),
            );
          },
        );
      }),
    );
  }
}

/// 队列内"移除"按钮 —— 不在 SongRowTile 默认 trailing 里(那是 ❤️+▶),
/// 这里队列内移除用单独的 ✕ 图标,语义跟详情页不一样。
class RemoveIconButton extends StatelessWidget {
  const RemoveIconButton({super.key, required this.song, required this.index});
  final Song? song;
  final int index;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.remove_circle_outline),
      onPressed: () {
        final controller = Get.find<PlayListController>();
        controller.removeSong(index);
      },
      tooltip: '移除',
    );
  }
}

class PlayListBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PlayListController>(() => PlayListController());
  }
}
