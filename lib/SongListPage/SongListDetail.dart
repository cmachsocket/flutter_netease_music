import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../models/default.dart';

import 'SongListBody.dart';
import 'SongListController.dart';
import '../models/LibrarySummary.dart' show PlaylistSource;

/// 歌单详情页(主页 [SongListCard] 点进来后看到)
///
/// - 进入路由时绑定的 [SongListController] 已按 [playlistId] 完成初始化,这里只消费
/// - 数据来自 [SongListController.songs],目前是 stub 假数据,后续接 musiclibrary SDK
/// - 列表渲染走 [SongListBody] (→ 内部用 [SongRowTile]),业务侧零硬编码
///
/// **按钮显示规则**(由调用方在跳详情页时传入 [playlistSource]):
/// - [PlaylistSource.created]   → 🗑 删除 (自建歌单)
/// - [PlaylistSource.collected] → ❤️ 收藏 (收藏的歌单 / 专辑都走这里)
///
/// 专辑入口(`playlistId` 以 `album-` 开头)按 `PlaylistSource.collected` 传,
/// 因为详情页内 `playlistId` 前缀单独判断专辑身份,跟 `playlistSource`
/// 是两套独立维度。
class SongListDetail extends StatelessWidget {
  const SongListDetail({
    super.key,
    required this.playlistId,
    this.displayTitle,
    required this.playlistSource,
  });

  final String playlistId;
  final String? displayTitle;
  final PlaylistSource playlistSource;

  static const mainTextMaxLines = 4;
  static const subTextMaxLines = 1;
  @override
  Widget build(BuildContext context) {
    final controller = Get.find<SongListController>();
    final textTheme = Theme.of(context).textTheme;
    final isAlbum = playlistId.startsWith('album-');
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Get.back(id: DefaultValues.shellNavigatorId),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Obx(() {
          final remoteTitle = controller.title.value?.trim() ?? '';
          final fallbackTitle = displayTitle?.trim() ?? '歌单';
          final title = remoteTitle.isNotEmpty ? remoteTitle : fallbackTitle;
          final prefix = isAlbum ? '专辑' : '歌单';
          return Text('$prefix · $title');
        }),
      ),
      body: Obx(() {
        // 读取 likedIds 触发重建，使每个 SongRowTile 的 isLiked 回调重新计算

        final list = controller.songs;
        return Column(
          children: [
            // 操作行(描述 + 按钮 Column):空歌单也渲染
            //
            // 原条件 `list.isNotEmpty && ...` 会把整行隐藏,导致空的自建歌单
            // 连删除按钮都看不到 → 用户没法删除新建的空歌单。
            // 现在拆成两层:
            //   - 整行:有歌 / 不在 loading / 无错误 / (播放按钮空列表会禁用)
            //   - 播放按钮:仅 `list.isNotEmpty` 时可点(空歌单播啥?)
            //   - 删除/收藏按钮:始终显示,跟歌单空不空无关
            if (!controller.isLoading.value &&
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
                        // 空歌单禁用播放,避免点了播个空队列
                        onPressed: list.isEmpty ? null : controller.playAll,
                        label: Text(
                          '播放',
                          style: textTheme.bodyMedium,
                          maxLines: subTextMaxLines,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // 专辑 / 收藏的歌单 → ❤️ 收藏
                      // 自建歌单           → 🗑 删除
                      if (playlistSource == PlaylistSource.created)
                        TextButton.icon(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: controller.deletePlaylist,
                          label: Text(
                            '删除',
                            style: textTheme.bodyMedium,
                            maxLines: subTextMaxLines,
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                      else
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
