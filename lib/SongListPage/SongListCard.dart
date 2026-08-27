import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:responsive_builder/responsive_builder.dart';
import '../AppShell.dart';
import '../widgets/netease_image.dart' show neteaseImageHeaders;
import 'SongListController.dart';
import 'SongListDetail.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// 整张歌单播放回调(返回 Future 但卡片场景 fire-and-forget)
typedef PlayPlaylistCallback = Future<void> Function();

/// 查询目标资源是否被喜欢/收藏/关注
typedef IsLikedGetter = bool Function();

/// 主页歌单卡片
///
/// - [playlistId] 由调用方注入(主页 HomePage 把每天推荐/私人FM/推荐歌单的 ID 传进来)
/// - 默认点击走 [Get.to] 推到 `AppShell` 的嵌套 Navigator 上(保留底部 [BottomPlayer]);
///   进入后自动按 ID 拉数据([SongListController] 由 binding 注入,路由 pop 时自动销毁)
/// - [onTap] 传了就用自定义导航(艺人/专辑卡片可以借此推到自己的详情页);
///   传 null 就走默认 SongListDetail 导航
class SongListCard extends StatelessWidget {
  const SongListCard({
    super.key,
    required this.playlistId,
    this.title,
    this.subtitle,
    this.imageUrl,
    this.onTap,
    this.onPlay,
    this.isLiked,
    this.onToggleFavorite,
  });

  final String playlistId;
  final String? title;
  final String? subtitle;
  final String? imageUrl;

  /// 覆盖默认导航。null = 默认跳 SongListDetail
  final VoidCallback? onTap;

  /// 覆盖默认播放(整张歌单)。null = 默认调 SongListController.playPlaylistById
  final PlayPlaylistCallback? onPlay;

  /// 查询当前 [playlistId] 是否被喜欢/收藏/关注
  ///
  /// - **必须在 Obx 内调用**才能响应 likedXxxIds 变化
  /// - widget 不直接 Get.find service,调用方注入响应式查询
  final IsLikedGetter? isLiked;

  /// 点击 ♥ 触发的操作
  ///
  /// - 调用方决定调哪个 service 的 toggle
  /// - widget 内 fire-and-forget,不 await
  final VoidCallback? onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        onTap: onTap ?? _defaultNavigate,
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: CachedNetworkImage(
                imageUrl: imageUrl ?? '',
                fit: BoxFit.cover,
                httpHeaders: neteaseImageHeaders,
              ),
            ),

            ListTile(
              title: Text(
                title ?? '',
                style: textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                subtitle ?? '',
                style: textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: OrientationLayoutBuilder(
                landscape: (_) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _LikeButton(
                      isLiked: isLiked,
                      onToggleFavorite: onToggleFavorite,
                      playlistId: playlistId,
                    ),
                    IconButton(
                      icon: Icon(Icons.play_circle_fill_outlined),
                      onPressed: () {
                        final cb =
                            onPlay ??
                            () =>
                                SongListController.playPlaylistById(playlistId);
                        cb(); // fire-and-forget
                      },
                    ),
                  ],
                ),
                portrait: (_) => SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _defaultNavigate() {
    Get.to(
      () => SongListDetail(playlistId: playlistId, displayTitle: title),
      id: AppShell.shellNavigatorId,
      binding: SongListDetailBinding(playlistId: playlistId),
    );
  }
}

class LineSongListCard extends StatelessWidget {
  const LineSongListCard({
    super.key,
    required this.playlistId,
    this.title,
    this.subtitle,
    this.imageUrl,
    this.onPlay,
  });

  final String playlistId;
  final String? title;
  final String? subtitle;
  final String? imageUrl;

  /// 覆盖默认播放(整张歌单)。null = 默认调 SongListController.playPlaylistById
  final PlayPlaylistCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () => Get.to(
          () => SongListDetail(playlistId: playlistId, displayTitle: title),
          id: AppShell.shellNavigatorId,
          binding: SongListDetailBinding(playlistId: playlistId),
        ),
        leading: CachedNetworkImage(
          imageUrl: imageUrl ?? '',
          fit: BoxFit.cover,
          httpHeaders: neteaseImageHeaders,
        ),
        title: Text(
          title ?? '',
          style: textTheme.bodySmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          subtitle ?? '',
          style: textTheme.bodySmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          icon: Icon(Icons.play_circle_fill_outlined),
          onPressed: () {
            final cb =
                onPlay ?? () => SongListController.playPlaylistById(playlistId);
            cb(); // fire-and-forget
          },
        ),
      ),
    );
  }
}

/// 歌单/专辑/艺人卡片的 ♥ 按钮
///
/// - **widget 不接触 service**:所有状态查询 / 操作都走 [SongListCard] 注入的 callback
/// - widget 内部 Obx 包 [isLiked] 调用 → 响应 likedXxxIds 变化
/// - 首次 build 时调 [onFirstBuild](典型场景:艺人卡片主动同步关注状态)
class _LikeButton extends StatelessWidget {
  const _LikeButton({
    required this.playlistId,
    required this.isLiked,
    required this.onToggleFavorite,
  });

  final String playlistId;
  final IsLikedGetter? isLiked;
  final VoidCallback? onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 没 isLiked callback 时直接静态 IconButton ——不包 Obx
    // (包 Obx 但体内不读 Rx 会报 "improper use of GetX")
    if (isLiked == null) {
      return IconButton(
        icon: const Icon(Icons.favorite_border),
        onPressed: () {
          onToggleFavorite?.call();
        },
        tooltip: '收藏',
      );
    }
    return Obx(() {
      final liked = isLiked?.call() ?? false;
      return IconButton(
        icon: Icon(
          liked ? Icons.favorite : Icons.favorite_border,
          color: liked ? scheme.primary : null,
        ),
        onPressed: () {
          onToggleFavorite?.call();
        },
        tooltip: liked ? '取消收藏' : '收藏',
      );
    });
  }
}
