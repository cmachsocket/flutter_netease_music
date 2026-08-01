import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'Player.dart';

class BottomPlayer extends StatelessWidget {
  const BottomPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () {
        Get.to(() => const Player());
      },
      child: Container(
        color: scheme.surfaceContainerHighest,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              flex: 3,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Image(
                    image: NetworkImage(
                      'https://cdn.jsdelivr.net/gh/cmachsocket/resources/avatar.png',
                    ),
                    fit: BoxFit.cover,
                  ),
                  //todo: bind to actual cover
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Song Title',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text('Artist Name'),
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
                ],
              ),
            ),
            Expanded(
              flex: 1,
              child: ProgressBar(
                progress: const Duration(
                  seconds: 30,
                ), //todo: bind to actual progress
                buffered: const Duration(seconds: 60),
                total: const Duration(minutes: 3),
                onSeek: (duration) {},
                timeLabelLocation: TimeLabelLocation.sides,
                // 颜色全部跟主题走:进度条 = primary,底色 = onSurface 淡,缓冲 = primary 淡
                progressBarColor: scheme.primary,
                baseBarColor: scheme.onSurface.withOpacity(0.2),
                bufferedBarColor: scheme.primary.withOpacity(0.3),
                thumbColor: scheme.primary,
                thumbGlowColor: scheme.primary.withOpacity(0.4),
                timeLabelTextStyle: TextStyle(color: scheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
