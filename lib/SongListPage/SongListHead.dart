import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/Default.dart';
import '../models/LibrarySummary.dart' show PlaylistSource;
import '../widgets/netease_image.dart';
import 'SongListBodyController.dart';
import 'SongListHeadController.dart';

/// 详情页 head 行 widget —— 通过 [controllerTag] 找到对应 [SongListHeadControllerBase]。
///
/// **真正的视觉由 controller 的具体类型决定**(在 binding 时选定):
/// - `SongListHeadController` (歌单: created / collected / pure) → [SongListHead]
/// - `AlbumHeadController`    (专辑)                              → [AlbumHead]
/// - `ArtistHeadController`   (艺人)                              → [ArtistHead]
///
/// **切换逻辑**:`SongListDetail` 用 `controllerTag = playlistId + source` 在 binding
/// 时同时注册 head / body 两个 controller。`SongListDetail.build` 读
/// `head.source` 决定显示哪个 head widget —— **这里不再根据 source 切换**,因为
/// 这三个 head widget 各有自己视觉,选哪个在 detail page 那一层做完。
///
/// 当前 [SongListDetail] 调用 `SongListHead(controllerTag: ...)` —— 即 head widget
/// 自己从 controllerTag 读 source → 转 delegate 到对应视觉子类。
class SongListHead extends StatelessWidget {
  const SongListHead({super.key, required this.controllerTag});

  final String controllerTag;

  /// AppBar 上"返回"按钮的回退栈 id(沿用项目约定)
  static const int backNavigatorId = DefaultValues.shellNavigatorId;

  /// 行布局占满主轴最大高度(沿用原 SongListDetail 内 head 行的视觉)
  static const int rowMainTextMaxLines = 4;
  static const int rowSubTextMaxLines = 1;

  @override
  Widget build(BuildContext context) {
    final head = Get.find<SongListHeadControllerBase>(tag: controllerTag);
    final source = head.source;
    // 按 source 委托给具体 head widget(三个子类视觉差异)
    return switch (source) {
      PlaylistSource.album => AlbumHead(
        controller: head,
        controllerTag: controllerTag,
      ),
      PlaylistSource.artist => ArtistHead(
        controller: head,
        controllerTag: controllerTag,
      ),
      _ => _PlaylistHead(controller: head, controllerTag: controllerTag),
    };
  }
}

/// 歌单形态 head —— 描述 + 按钮列(播放 / 收藏 / 删除)。
///
/// 按钮:
///   - 播放:head.onPlayAll(由 binding 注入 body.playAll)
///   - 收藏 / ❤️:head.toggleFavorite(LikedType.playlist)
///   - 删除:仅 source == PlaylistSource.created 时显示 —— 收藏的/纯的不可删
///
/// loading / 出错时整行隐藏(head 显示空字符串也没有意义)
class _PlaylistHead extends StatelessWidget {
  const _PlaylistHead({required this.controller, required this.controllerTag});

  final SongListHeadControllerBase controller;
  final String controllerTag;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final body = Get.isRegistered<SongListBodyController>(tag: controllerTag)
        ? Get.find<SongListBodyController>(tag: controllerTag)
        : null;
    return Obx(() {
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
                maxLines: SongListHead.rowMainTextMaxLines,
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
                onPressed: songsEmpty ? null : controller.onPlayAll,
                label: Text(
                  '播放',
                  style: textTheme.bodyMedium,
                  maxLines: SongListHead.rowSubTextMaxLines,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Obx(() {
                // null (loading) → 不渲染
                if (controller.playlistSource.value == null) {
                  return const SizedBox.shrink();
                }
                // 自建(created) → 删除 + 收藏两个按钮(纵向排列)
                if (controller.playlistSource.value == PlaylistSource.created) {
                  return TextButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: controller.deletePlaylist,
                    label: Text(
                      '删除',
                      style: textTheme.bodyMedium,
                      maxLines: SongListHead.rowSubTextMaxLines,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }
                // 收藏的(collected)/ 搜索结果(pure) → 只收藏
                return _LikeButton(
                  liked: controller.isPlaylistFavorite,
                  onToggle: controller.toggleFavorite,
                );
              }),
            ],
          ),
        ],
      );
    });
  }
}

/// 收藏 ❤️ 按钮 widget —— 自建歌单 / 专辑 / 艺人 head 都会用到。
///
/// - [liked] 内部读 Rx,包 Obx 自动响应收藏状态变化
/// - [onToggle] 调对应 controller 的 toggleFavorite
class _LikeButton extends StatelessWidget {
  const _LikeButton({required this.liked, required this.onToggle});

  final bool Function() liked;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return TextButton.icon(
      icon: Obx(
        () => Icon(
          liked() ? Icons.favorite : Icons.favorite_border,
          color: liked() ? Theme.of(context).colorScheme.primary : null,
        ),
      ),
      onPressed: onToggle,
      label: Text(
        '收藏',
        style: textTheme.bodyMedium,
        maxLines: SongListHead.rowSubTextMaxLines,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// 专辑形态 head —— 标题 + 描述 + 按钮列(播放 / 收藏)。
///
/// 视觉:`Row` + 左侧封面(SongCover)+ 右侧标题/描述/按钮 Column。
/// 跟歌单形态相比:
///   - 标题在标题列上方(歌单 head 没有标题,只显示描述)
///
/// 按钮:**没有删除**(专辑不能删)
class AlbumHead extends StatelessWidget {
  const AlbumHead({
    super.key,
    required this.controller,
    required this.controllerTag,
  });

  final SongListHeadControllerBase controller;
  final String controllerTag;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final body = Get.isRegistered<SongListBodyController>(tag: controllerTag)
        ? Get.find<SongListBodyController>(tag: controllerTag)
        : null;
    return Obx(() {
      if (controller.isLoading.value || controller.errorMessage.value != null) {
        return const SizedBox.shrink();
      }
      final songsEmpty = body?.songs.isEmpty ?? false;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 标题(歌单形态没有这一行 —— 标题在 AppBar 里)
                Text(
                  controller.title.value ?? '',
                  style: textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  controller.description.value?.trim().isNotEmpty == true
                      ? controller.description.value!.trim()
                      : '暂无描述',
                  style: textTheme.bodyMedium,
                  maxLines: SongListHead.rowMainTextMaxLines,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.play_arrow),
                onPressed: songsEmpty ? null : controller.onPlayAll,
                label: Text(
                  '播放',
                  style: textTheme.bodyMedium,
                  maxLines: SongListHead.rowSubTextMaxLines,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _LikeButton(
                liked: controller.isPlaylistFavorite,
                onToggle: controller.toggleFavorite,
              ),
            ],
          ),
        ],
      );
    });
  }
}

/// 艺人形态 head —— 圆形头像 + 名字 + 简介 + 按钮列(播放全部 / 关注)。
///
/// 视觉:`Row` + 左侧 `CircleAvatar` + 右侧名字/简介/按钮 Column。
///
/// 按钮:
///   - 播放全部:head.onPlayAll(由 binding 注入 body.playAll)
///   - 关注:head.toggleFavorite(LikedType.artist)
///   - **没有删除按钮**(艺人不能删)
class ArtistHead extends StatelessWidget {
  const ArtistHead({
    super.key,
    required this.controller,
    required this.controllerTag,
  });

  final SongListHeadControllerBase controller;
  final String controllerTag;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final body = Get.isRegistered<SongListBodyController>(tag: controllerTag)
        ? Get.find<SongListBodyController>(tag: controllerTag)
        : null;
    return Obx(() {
      if (controller.isLoading.value || controller.errorMessage.value != null) {
        return const SizedBox.shrink();
      }
      final songsEmpty = body?.songs.isEmpty ?? false;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 圆形头像
          CircleAvatar(
            backgroundColor: scheme.surfaceContainerHigh,
            backgroundImage:
                controller.coverUrl.value == null ||
                    controller.coverUrl.value!.isEmpty
                ? null
                : neteaseNetworkImage(controller.coverUrl.value!),
            child:
                controller.coverUrl.value == null ||
                    controller.coverUrl.value!.isEmpty
                ? Icon(Icons.person, color: scheme.onSurfaceVariant)
                : null,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 名字
                Text(
                  controller.title.value ?? '',
                  style: textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                // 简介 / bio
                Text(
                  controller.description.value?.trim().isNotEmpty == true
                      ? controller.description.value!.trim()
                      : '暂无简介',
                  style: textTheme.bodyMedium,
                  maxLines: SongListHead.rowMainTextMaxLines,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.play_arrow),
                onPressed: songsEmpty ? null : controller.onPlayAll,
                label: Text(
                  '播放全部',
                  style: textTheme.bodyMedium,
                  maxLines: SongListHead.rowSubTextMaxLines,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // 关注(用 favorite icon 表示,语义统一)
              _LikeButton(
                liked: controller.isPlaylistFavorite,
                onToggle: controller.toggleFavorite,
              ),
            ],
          ),
        ],
      );
    });
  }
}
