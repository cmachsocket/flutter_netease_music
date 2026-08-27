import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'SongListBody.dart';
import 'SongListController.dart';

/// 歌单详情页(主页 [SongListCard] 点进来后看到)
///
/// - 进入路由时绑定的 [SongListController] 已按 [playlistId] 完成初始化,这里只消费
/// - 数据来自 [SongListController.songs],目前是 stub 假数据,后续接 musiclibrary SDK
/// - 列表渲染走 [SongListBody] (→ 内部用 [SongRowTile]),业务侧零硬编码
class SongListDetail extends StatelessWidget {
  const SongListDetail({
    super.key,
    required this.playlistId,
    this.displayTitle,
  });

  final String playlistId;
  final String? displayTitle;

  static const mainTextMaxLines = 4;
  static const subTextMaxLines = 1;
  @override
  Widget build(BuildContext context) {
    final controller = Get.find<SongListController>();
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Obx(() {
          final remoteTitle = controller.title.value?.trim() ?? '';
          final fallbackTitle = displayTitle?.trim() ?? '歌单';
          final title = remoteTitle.isNotEmpty ? remoteTitle : fallbackTitle;
          final isAlbum = playlistId.startsWith('album-');
          final prefix = isAlbum ? '专辑' : '歌单';
          return Text('$prefix · $title');
        }),
      ),
      body: Obx(() {
        // 读取 likedIds 触发重建，使每个 SongRowTile 的 isLiked 回调重新计算

        final list = controller.songs;
        return Column(
          children: [
            if (list.isNotEmpty &&
                !controller.isLoading.value &&
                controller.errorMessage.value == null)
              Row(
                children: [
                  Expanded(
                    child: Obx(() {
                      final description =
                          controller.description.value?.trim() ?? '';
                      return Text(
                        description.isEmpty ? '暂无描述' : description,
                        style: textTheme.bodyMedium,
                        maxLines: mainTextMaxLines,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.left,
                      );
                    }),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.play_arrow),
                        onPressed: controller.playAll,
                        label: Text(
                          '播放',
                          style: textTheme.bodyMedium,
                          maxLines: subTextMaxLines,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton.icon(
                        icon: Obx(
                          () => Icon(
                            controller.isPlaylistFavorite()
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color: controller.isPlaylistFavorite()
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                        ),
                        onPressed: controller.togglePlaylistFavorite,
                        label: Text(
                          '收藏',
                          style: textTheme.bodyMedium,
                          maxLines: subTextMaxLines,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            Expanded(
              child: SongListBody(
                songs: list.toList(),
                isLoading: controller.isLoading.value,
                errorMessage: controller.errorMessage.value,
                onToggleFavorite: (song) => controller.toggleFavorite(song.id),
                onPlay: controller.playSong,
                isLiked: (song) => controller.isLiked(song.id),
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
