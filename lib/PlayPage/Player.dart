import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'Lyrics.dart';
import '../widgets/song_cover.dart';
import 'PlayerController.dart';
import '../models/default.dart';
import '../PlayListPage/PlayListPage.dart';
import '../PlayListPage/PlayListController.dart';
import '../services/PlayQueueService.dart';
import '../widgets/linked_detail_text.dart';
import 'MusicProgressbar.dart';

class Player extends StatelessWidget {
  Player({super.key});
  final controller = Get.find<PlayerController>();
  final playlist = Get.find<PlayListController>();

  @override
  Widget build(BuildContext context) {
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
            controller.centerIndex.value == CenterPage.cover.index
                ? Icons.music_note
                : Icons.lyrics,
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
                        aspectRatio: DefaultValues.squardRatio,
                        child: Obx(() {
                          final song = controller.currentSong.value;
                          return SongCover(url: song?.coverUrl ?? '');
                        }),
                      ),
                      const Lyrics(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),

      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MusicProgressBar(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous),
                onPressed: _gotoPrev,
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
                onPressed: _gotoNext,
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Obx(() {
                // 三模式循环: sequential → shuffle → repeatOne → sequential
                final m = playlist.mode.value;
                return IconButton(
                  icon: Icon(_modeIcon(m)),
                  tooltip: _modeTooltip(m),
                  onPressed: () => playlist.setMode(_nextMode(m)),
                );
              }),
              Obx(() {
                final song = controller.currentSong.value;
                return IconButton(
                  icon: Icon(
                    controller.isLiked.value
                        ? Icons.favorite
                        : Icons.favorite_border,
                    color: controller.isLiked.value
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  onPressed: song == null ? null : controller.toggleFavorite,
                  tooltip: controller.isLiked.value ? '取消喜欢' : '喜欢',
                );
              }),
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

  void _gotoNext() {
    final next = playlist.nextIndex();
    if (next < 0) return;
    playlist.selectIndex(next);
    // repeatOne: nextIndex 返回同一首 → _syncQueueState 不会 reload,
    // 手动 seek 到 0 重启播放
    if (playlist.mode.value == PlayMode.repeatOne) {
      controller.seek(Duration.zero);
      controller.play();
    }
  }

  void _gotoPrev() {
    final prev = playlist.prevIndex();
    if (prev < 0) return;
    playlist.selectIndex(prev);
    if (playlist.mode.value == PlayMode.repeatOne) {
      controller.seek(Duration.zero);
      controller.play();
    }
  }

  /// 顺/乱/单 三模式循环 (sequential → shuffle → repeatOne → sequential)
  static PlayMode _nextMode(PlayMode m) {
    switch (m) {
      case PlayMode.sequential:
        return PlayMode.shuffle;
      case PlayMode.shuffle:
        return PlayMode.repeatOne;
      case PlayMode.repeatOne:
        return PlayMode.sequential;
    }
  }

  static IconData _modeIcon(PlayMode m) {
    switch (m) {
      case PlayMode.sequential:
        return Icons.repeat;
      case PlayMode.shuffle:
        return Icons.shuffle;
      case PlayMode.repeatOne:
        return Icons.repeat_one;
    }
  }

  static String _modeTooltip(PlayMode m) {
    switch (m) {
      case PlayMode.sequential:
        return '顺序播放';
      case PlayMode.shuffle:
        return '随机播放';
      case PlayMode.repeatOne:
        return '单曲循环';
    }
  }
}
