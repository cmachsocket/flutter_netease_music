import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../AppShell.dart';
import 'SongListController.dart';
import 'SongListDetail.dart';

/// 主页歌单卡片
///
/// - [playlistId] 由调用方注入(主页 HomePage 把每天推荐/私人FM/推荐歌单的 ID 传进来)
/// - 点击走 [Get.to] 推到 `AppShell` 的嵌套 Navigator 上(保留底部 [BottomPlayer]);
///   进入后自动按 ID 拉数据([SongListController] 由 binding 注入,路由 pop 时自动销毁)
class SongListCard extends StatelessWidget {
  const SongListCard({
    super.key,
    required this.playlistId,
    this.title,
    this.subtitle,
    this.imageUrl,
  });

  final String playlistId;
  final String? title;
  final String? subtitle;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        onTap: () => Get.to(
          () => SongListDetail(playlistId: playlistId),
          id: AppShell.shellNavigatorId,
          binding: BindingsBuilder(() {
            Get.lazyPut<SongListController>(
              () => SongListController(playlistId: playlistId),
            );
          }),
        ),
        child: Column(
          children: [
            Expanded(
              child: AspectRatio(
                aspectRatio: 1,
                child: Image.network(imageUrl ?? '', fit: BoxFit.cover),
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
                  // TODO: 播放歌单
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TopSongListCard extends StatelessWidget {
  const TopSongListCard({
    super.key,
    required this.playlistId,
    this.title,
    this.subtitle,
    this.imageUrl,
  });

  final String playlistId;
  final String? title;
  final String? subtitle;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () => Get.to(
          () => SongListDetail(playlistId: playlistId),
          id: AppShell.shellNavigatorId,
          binding: BindingsBuilder(() {
            Get.lazyPut<SongListController>(
              () => SongListController(playlistId: playlistId),
            );
          }),
        ),
        leading: Image.network(imageUrl ?? '', fit: BoxFit.cover),
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
            // TODO: 播放歌单
          },
        ),
      ),
    );
  }
}
