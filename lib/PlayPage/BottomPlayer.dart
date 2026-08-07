import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'Player.dart';
import 'PlayerController.dart';
import '../PlayListPage/PlayListPage.dart';
import '../PlayListPage/PlayListController.dart';
import '../ArtistPage/ArtistDetail.dart';

/// 底部 mini 播放器:全局共享 [PlayerController] 的 position / lyric
///
/// 点击跳转到全屏 [Player] 页(不再需要 binding,PlayerController 已在 main 注入)
class BottomPlayer extends StatelessWidget {
  const BottomPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = Get.find<PlayerController>();
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: () => Get.to(() => Player()),
      child: Container(
        color: scheme.surfaceContainerHighest,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  // 封面
                  Image(
                    image: NetworkImage(
                      'https://cdn.jsdelivr.net/gh/cmachsocket/resources/avatar.png',
                    ),
                    fit: BoxFit.cover,
                  ),
                  //todo: bind to actual cover
                  // 标题 + 艺术家
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextButton(
                          onPressed: () {},
                          child: Text(
                            'Song Title',
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Get.to(
                              () => ArtistDetail(artistId: "111"),
                              binding: ArtistDetailBinding(artistId: "111"),
                            );
                          },
                          child: Text(
                            'Artist Name',
                            style: textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.shuffle), onPressed: () {}),
                  IconButton(
                    icon: const Icon(Icons.favorite_border),
                    onPressed: () {},
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_previous),
                    onPressed: () {},
                  ),
                  IconButton(
                    icon: const Icon(Icons.play_arrow),
                    onPressed: () {},
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next),
                    onPressed: () {},
                  ),
                  IconButton(
                    icon: const Icon(Icons.playlist_play),
                    onPressed: () {
                      Get.to(() => PlayListPage(), binding: PlayListBinding());
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 1,
              child: Obx(
                () => ProgressBar(
                  progress: player.position.value,
                  //todo: bind to actual buffered
                  buffered: const Duration(seconds: 60),
                  total: player.duration.value,
                  onSeek: player.updatePosition,
                  timeLabelLocation: TimeLabelLocation.sides,
                  // 颜色全部跟主题走:进度条 = primary,底色 = onSurface 淡,缓冲 = primary 淡
                  progressBarColor: scheme.primary,
                  baseBarColor: scheme.onSurface.withValues(alpha: 0.3),
                  bufferedBarColor: scheme.primary.withValues(alpha: 0.3),
                  thumbColor: scheme.primary,
                  thumbGlowColor: scheme.primary.withValues(alpha: 0.4),
                  timeLabelTextStyle: textTheme.bodySmall,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
