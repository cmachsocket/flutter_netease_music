import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../widgets/song_cover.dart';
import 'PlayListController.dart';

/// 播放列表页
///
/// - 数据来自 [PlayListController.playlist]
/// - 复用 [ListTile]:封面尺寸 / padding / 行距全部走 M3 默认,业务侧零硬编码
/// - 当前选中项用 ListTile.selected + selectedTileColor 高亮
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
          final list = controller.playlist;
          final selected = controller.currentIndex.value;
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, index) {
              final song = list[index];
              return ListTile(
                selected: index == selected,
                onTap: () => controller.selectIndex(index),
                leading: SongCover(url: song.coverUrl),
                title: Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${song.artist} - ${song.album}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(song.durationLabel),
                    IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => controller.removeSong(index),
                    ),
                  ],
                ),
              );
            },
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
