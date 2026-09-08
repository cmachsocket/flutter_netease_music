import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/default.dart';
import '../models/LibrarySummary.dart' show PlaylistSource;
import 'SongListBodyController.dart';
import 'SongListHeadController.dart';

/// 歌单详情页 head 行 widget。
///
/// **职责**:展示 [SongListHeadController] 持有的 head 数据 + 触发 head 命令。
///
/// **不展示**:歌曲列表 —— 那是 [SongListBody] 的事。
///
/// head widget 在 build 时通过 `Get.find` 拿 body controller(只读 songs
/// 是否为空用于 disable 播放按钮)。head 跟 body 是 sibling controller,
/// head widget 是组合层 —— head controller 不知道 body 存在,但 widget
/// 可以组合两个 controller 的视觉。
class SongListHead extends StatelessWidget {
  const SongListHead({super.key, required this.controllerTag});

  /// head controller 由 binding 注入,widget 只通过 controller 读 / 写状态。
  final String controllerTag;

  /// AppBar 上"返回"按钮的回退栈 id(沿用项目约定)
  static const int backNavigatorId = DefaultValues.shellNavigatorId;

  /// 行布局占满主轴最大高度(沿用原 SongListDetail 内 head 行的视觉)
  static const int rowMainTextMaxLines = 4;
  static const int rowSubTextMaxLines = 1;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // head widget 知道 body 是 sibling,这里只读 songs 是否空 ——
    // 用于 disable 播放按钮。空歌单不让播(head controller 不直接读 body)。
    final body = Get.isRegistered<SongListBodyController>(tag: controllerTag)
        ? Get.find<SongListBodyController>(tag: controllerTag)
        : null;
    final controller = Get.find<SongListHeadController>(tag: controllerTag);
    return Obx(() {
      // head 行整体隐藏条件:loading / 出错
      // 空歌单也渲染(head 显示删除按钮必须可见)
      if (controller.isLoading.value || controller.errorMessage.value != null) {
        return const SizedBox.shrink();
      }
      final songsEmpty = body?.songs.isEmpty ?? false;
      return Row(
        children: [
          Expanded(
            child: Obx(() {
              final description = controller.description.value?.trim() ?? '';
              return Text(
                description.isEmpty ? '暂无描述' : description,
                style: textTheme.bodyMedium,
                maxLines: rowMainTextMaxLines,
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
                // 空歌单禁用播放。onPlayAll 由 binding 注入 body.playAll
                // —— 没歌时 onPlayAll 还是会调,但 widget 这层 disable 拦截
                onPressed: songsEmpty ? null : controller.onPlayAll,
                label: Text(
                  '播放',
                  style: textTheme.bodyMedium,
                  maxLines: rowSubTextMaxLines,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // 按钮:按 playlistSource Rx 切
              //   album / collected → ❤️ 收藏
              //   created           → 🗑 删除
              //   null (loading)    → 不渲染
              Obx(() {
                final source = controller.playlistSource.value;
                if (source == null) {
                  return const SizedBox.shrink();
                }
                if (source == PlaylistSource.created) {
                  return TextButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: controller.deletePlaylist,
                    label: Text(
                      '删除',
                      style: textTheme.bodyMedium,
                      maxLines: rowSubTextMaxLines,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }
                // album 或 collected
                return TextButton.icon(
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
                  onPressed: controller.toggleFavorite,
                  label: Text(
                    '收藏',
                    style: textTheme.bodyMedium,
                    maxLines: rowSubTextMaxLines,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }),
            ],
          ),
        ],
      );
    });
  }
}

/// AlbumHead 占位 —— 等专辑独立详情页出现时复用同款 head 骨架。
///
/// 暂时不实现,因为现在专辑走 `SongListDetail` 同款页面,`SongListHead`
/// 已经处理 album- 前缀。等 `AlbumDetail` 真出现再补实现。
class AlbumHead extends StatelessWidget {
  const AlbumHead({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

/// ArtistHead 占位 —— ArtistDetail 现在有自己 inline 的 `_ArtistHeader`,
/// 未来可抽出来共享。
class ArtistHead extends StatelessWidget {
  const ArtistHead({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
