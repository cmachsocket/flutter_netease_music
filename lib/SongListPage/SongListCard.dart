import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../AppShell.dart';
import '../widgets/netease_image.dart' show neteaseImageHeaders;
import 'SongListController.dart';
import 'SongListDetail.dart';

/// 整张歌单播放回调(返回 Future 但卡片场景 fire-and-forget)
typedef PlayPlaylistCallback = Future<void> Function();

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
  });

  final String playlistId;
  final String? title;
  final String? subtitle;
  final String? imageUrl;

  /// 覆盖默认导航。null = 默认跳 SongListDetail
  final VoidCallback? onTap;

  /// 覆盖默认播放(整张歌单)。null = 默认调 SongListController.playPlaylistById
  final PlayPlaylistCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        onTap: onTap ?? _defaultNavigate,
        child: Column(
          children: [
            Expanded(
              child: AspectRatio(
                aspectRatio: 1,
                child: Image.network(
                  imageUrl ?? '',
                  fit: BoxFit.cover,
                  headers: neteaseImageHeaders,
                ),
              ),
            ),
            ListTile(
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
                      onPlay ??
                      () => SongListController.playPlaylistById(playlistId);
                  cb(); // fire-and-forget
                },
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
        leading: Image.network(
          imageUrl ?? '',
          fit: BoxFit.cover,
          headers: neteaseImageHeaders,
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
