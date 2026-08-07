import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/Song.dart';
import '../widgets/linked_detail_text.dart';
import 'SongListBody.dart';
import 'SongListController.dart';

/// 歌单详情页(主页 [SongListCard] 点进来后看到)
///
/// - 进入路由时绑定的 [SongListController] 已按 [playlistId] 完成初始化,这里只消费
/// - 数据来自 [SongListController.songs],目前是 stub 假数据,后续接 musiclibrary SDK
/// - 列表渲染走 [SongListBody] (→ 内部用 [SongRowTile]),业务侧零硬编码
class SongListDetail extends StatelessWidget {
  const SongListDetail({super.key, required this.playlistId});

  final String playlistId;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<SongListController>();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text('歌单 · $playlistId'),
      ),
      body: Obx(() {
        final list = controller.songs;
        // 顶部 header 在有数据时才显示;空/加载/错误态交给 SongListBody 单独占位
        return Column(
          children: [
            if (list.isNotEmpty &&
                !controller.isLoading.value &&
                controller.errorMessage.value == null)
              LinkedDetailText(
                song: Song(
                  id: "",
                  title: "",
                  artist: "",
                  album: "",
                  coverUrl: "",
                  duration: Duration.zero,
                ),
              ),
            Expanded(
              child: SongListBody(
                songs: list.toList(),
                isLoading: controller.isLoading.value,
                errorMessage: controller.errorMessage.value,
                onToggleFavorite: (song) => controller.toggleFavorite(song.id),
                onPlay: controller.playSong,
              ),
            ),
          ],
        );
      }),
    );
  }
}

class SongListDetailBinding extends Bindings {
  final String playlistId;

  SongListDetailBinding({required this.playlistId});

  @override
  void dependencies() {
    Get.lazyPut<SongListController>(
      () => SongListController(playlistId: playlistId),
    );
  }
}
