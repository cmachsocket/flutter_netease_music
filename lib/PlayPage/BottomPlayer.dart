import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'Player.dart';
import 'PlayerController.dart';
import '../PlayListPage/PlayListPage.dart';
import '../PlayListPage/PlayListController.dart';
import '../services/PlayQueueService.dart';
import '../widgets/netease_image.dart';

/// 底部 mini 播放器
///
/// - 数据来源:[PlayerController.currentSong](音视频状态)
///           + [PlayListController.currentIndex](队列索引)
/// - 进度条由 [PlayerController.position]/[duration] 驱动(just_audio stream 推)
/// - 点击跳转到全屏 [Player] 页
/// - 队列图标跳 [PlayListPage]
class BottomPlayer extends StatelessWidget {
  const BottomPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = Get.find<PlayerController>();
    final playlist = Get.find<PlayListController>();
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
                  // 封面(从当前歌曲拿;无歌曲时退化占位)
                  // 用 AspectRatio 1:1 + BoxFit.cover,让 Row 自身高度约束决定封面大小,
                  // 不写死 48x48 —— 跟随主题 / 父容器高度走
                  Obx(() {
                    final song = player.currentSong.value;
                    final child = song == null
                        ? Container(color: scheme.surfaceContainerHigh)
                        : CachedNetworkImage(
                            imageUrl: song.coverUrl,
                            fit: BoxFit.cover,
                            httpHeaders: neteaseImageHeaders,
                          );
                    return AspectRatio(aspectRatio: 1, child: child);
                  }),
                  // 标题 + 艺术家
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Obx(
                          () => Text(
                            player.currentSong.value?.title ?? '未在播放',
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Obx(() {
                          final song = player.currentSong.value;
                          return Text(
                            song?.artist ?? '-',
                            style: textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          );
                        }),
                      ],
                    ),
                  ),
                  Obx(() {
                    final song = player.currentSong.value;
                    return IconButton(
                      icon: Icon(
                        player.isLiked.value
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: player.isLiked.value ? scheme.primary : null,
                      ),
                      onPressed: song == null ? null : player.toggleFavorite,
                      tooltip: player.isLiked.value ? '取消喜欢' : '喜欢',
                    );
                  }),
                  IconButton(
                    icon: const Icon(Icons.skip_previous),
                    onPressed: () => _gotoPrev(playlist, player),
                  ),
                  IconButton(
                    icon: Obx(
                      () => Icon(
                        player.isPlaying.value ? Icons.pause : Icons.play_arrow,
                      ),
                    ),
                    onPressed: player.togglePlay,
                  ),

                  IconButton(
                    icon: const Icon(Icons.skip_next),
                    onPressed: () => _gotoNext(playlist, player),
                  ),
                  IconButton(
                    icon: const Icon(Icons.playlist_play),
                    onPressed: () => Get.to(
                      () => PlayListPage(),
                      binding: PlayListBinding(),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 1,
              child: Obx(
                () => ProgressBar(
                  progress: player.position.value,
                  buffered: player.buffered.value,
                  total: player.duration.value,
                  onSeek: player.seek,
                  timeLabelLocation: TimeLabelLocation.sides,
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

  /// 下一首:走 [PlayQueueService.nextIndex],由它决定 sequential/shuffle/repeatOne
  void _gotoNext(PlayListController playlist, PlayerController player) {
    final next = playlist.nextIndex();
    if (next < 0) return;
    playlist.selectIndex(next);
    if (playlist.mode.value == PlayMode.repeatOne) {
      player.seek(Duration.zero);
      player.play();
    }
  }

  /// 上一首:走 [PlayQueueService.prevIndex]
  void _gotoPrev(PlayListController playlist, PlayerController player) {
    final prev = playlist.prevIndex();
    if (prev < 0) return;
    playlist.selectIndex(prev);
    if (playlist.mode.value == PlayMode.repeatOne) {
      player.seek(Duration.zero);
      player.play();
    }
  }
}
