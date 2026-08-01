import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'Lyrics.dart';
import 'PlayerController.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';

class Player extends StatelessWidget {
  Player({super.key});
  final controller = Get.find<PlayerController>();
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () {
            Get.back();
            // 处理返回操作
          },
        ),
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题 + 副标题：字号 / 颜色全部走主题
            Text(
              'Song Title',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            Text(
              'Artist Name - Album Name',
              style: textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // 图片 / 歌词：Expanded 占满中间区域，子项居中
          Expanded(
            child: Obx(
              () => GestureDetector(
                onTap: () => controller.switchPage(),
                child: Center(
                  child: IndexedStack(
                    index: controller.centerIndex.value,
                    alignment: Alignment.center,
                    children: [
                      AspectRatio(
                        aspectRatio: 1,
                        child: Image(
                          //todo: bind to actual cover
                          image: NetworkImage(
                            'https://cdn.jsdelivr.net/gh/cmachsocket/resources/avatar.png',
                          ),
                          fit: BoxFit.cover,
                        ),
                      ),

                      Lyrics(),
                    ],
                  ),
                ),
              ),
            ),
          ),
          ProgressBar(
            progress: const Duration(
              seconds: 30,
            ), //todo: bind to actual progress
            buffered: const Duration(seconds: 60),
            total: const Duration(minutes: 3),
            onSeek: (duration) => controller.updatePosition(duration),
            // 颜色全部跟主题走:进度条 = primary,底色 = onSurface 淡,缓冲 = primary 淡
            progressBarColor: scheme.primary,
            baseBarColor: scheme.onSurface.withValues(alpha: 0.3),
            bufferedBarColor: scheme.primary.withValues(alpha: 0.3),
            thumbColor: scheme.primary,
            thumbGlowColor: scheme.primary.withValues(alpha: 0.4),
            timeLabelTextStyle: textTheme.bodySmall,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous),
                onPressed: () {},
              ),
              IconButton(icon: const Icon(Icons.play_arrow), onPressed: () {}),
              IconButton(icon: const Icon(Icons.skip_next), onPressed: () {}),
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
            ],
          ),
        ],
      ),
    );
  }
}
