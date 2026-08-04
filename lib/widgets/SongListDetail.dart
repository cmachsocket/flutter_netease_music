import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'SongListController.dart';

/// 歌单详情页(主页 [SongListCard] 点进来后看到)
///
/// - 进入路由时绑定的 [SongListController] 已按 [playlistId] 完成初始化,这里只消费
/// - 数据来自 [SongListController.songs],目前是 stub 假数据,后续接 musiclibrary SDK
/// - 复用 [ListTile]:封面/文字/行距全部走 M3 默认,业务侧零硬编码
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
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        if (controller.errorMessage.value != null) {
          final scheme = Theme.of(context).colorScheme;
          return Center(
            child: Text(
              '加载失败: ${controller.errorMessage.value}',
              style: TextStyle(color: scheme.error),
            ),
          );
        }
        final list = controller.songs;
        if (list.isEmpty) {
          return const Center(child: Text('空歌单'));
        }
        return Column(
          children: [
            Row(
              children: [
                Text(
                  "歌单描述",
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.left,
                ),
                Spacer(),
                Column(
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      onPressed: () {
                        // TODO: 播放歌单
                      },
                      label: Text(
                        '播放',
                        style: Theme.of(context).textTheme.bodyMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.favorite_border),
                      onPressed: () {
                        // TODO: 播放歌单
                      },
                      label: Text(
                        '收藏',
                        style: Theme.of(context).textTheme.bodyMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Expanded(
              child: ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, index) {
                  final song = list[index];
                  return ListTile(
                    leading: _Cover(url: song.coverUrl),
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
                          icon: const Icon(Icons.favorite_border),
                          onPressed: () => controller.toggleFavorite(song.id),
                          tooltip: '喜爱',
                        ),
                        IconButton(
                          icon: const Icon(Icons.play_arrow),
                          onPressed: () => controller.playSong(song),
                          tooltip: '播放',
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      }),
    );
  }
}

/// 列表封面:复用网络图,失败时退化为 M3 标准 surface 色块 + 音符图标
class _Cover extends StatelessWidget {
  const _Cover({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Container(
        color: scheme.surfaceContainerHigh,
        alignment: Alignment.center,
        child: Icon(Icons.music_note, color: scheme.onSurfaceVariant),
      ),
    );
  }
}
