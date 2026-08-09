import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'Lyrics.dart';
import 'PlayerController.dart';
import '../PlayListPage/PlayListPage.dart';
import '../PlayListPage/PlayListController.dart';
import '../PlayListPage/PlayQueueService.dart';
import '../widgets/linked_detail_text.dart';
import '../widgets/netease_image.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';

class Player extends StatelessWidget {
  Player({super.key});
  final controller = Get.find<PlayerController>();
  final playlist = Get.find<PlayListController>();
  final queue = Get.find<PlayQueueService>();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Get.back(),
        ),
        centerTitle: true,
        title: Obx(() {
          final song = controller.currentSong.value;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                song?.title ?? '未在播放',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (song != null)
                LinkedDetailText(
                  song: song,
                  mainAxisAlignment: MainAxisAlignment.center,
                  textStyle: textTheme.bodyMedium,
                  backFirst: true,
                ),
            ],
          );
        }),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: controller.switchPage,
        child: Obx(
          () => Icon(
            controller.centerIndex.value == 0 ? Icons.music_note : Icons.lyrics,
          ),
        ),
      ),
      body: Column(
        children: [
          // 图片 / 歌词:Expanded 占满中间区域
          Expanded(
            child: Obx(
              () => GestureDetector(
                onSecondaryTap: controller.switchPage,
                onLongPress: controller.switchPage,
                child: Center(
                  child: IndexedStack(
                    index: controller.centerIndex.value,
                    alignment: Alignment.center,
                    children: [
                      AspectRatio(
                        aspectRatio: 1,
                        child: Obx(() {
                          final song = controller.currentSong.value;
                          return Image(
                            image: neteaseNetworkImage(song?.coverUrl ?? ''),
                            fit: BoxFit.cover,
                          );
                        }),
                      ),
                      const Lyrics(),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Obx(
            () => ProgressBar(
              progress: controller.position.value,
              buffered: const Duration(seconds: 60),
              total: controller.duration.value,
              onSeek: controller.seek,
              progressBarColor: scheme.primary,
              baseBarColor: scheme.onSurface.withValues(alpha: 0.3),
              bufferedBarColor: scheme.primary.withValues(alpha: 0.3),
              thumbColor: scheme.primary,
              thumbGlowColor: scheme.primary.withValues(alpha: 0.4),
              timeLabelTextStyle: textTheme.bodySmall,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous),
                onPressed: () => _prev(playlist),
              ),
              Obx(
                () => IconButton(
                  icon: Icon(
                    controller.isPlaying.value ? Icons.pause : Icons.play_arrow,
                  ),
                  onPressed: controller.togglePlay,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.skip_next),
                onPressed: () => _next(playlist),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(icon: const Icon(Icons.shuffle), onPressed: () {}),
              IconButton(
                icon: const Icon(Icons.favorite_border),
                onPressed: () {},
              ),
              IconButton(
                icon: const Icon(Icons.playlist_play),
                onPressed: () => Get.to(() => const PlayListPage()),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _next(PlayListController playlist) {
    final next = queue.currentIndex.value + 1;
    if (next >= playlist.playlist.length) return;
    playlist.selectIndex(next);
  }

  void _prev(PlayListController playlist) {
    final prev = queue.currentIndex.value - 1;
    if (prev < 0) return;
    playlist.selectIndex(prev);
  }
}
