import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';

class BottomPlayer extends StatelessWidget {
  const BottomPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Image(
                image: NetworkImage(
                  'https://cdn.jsdelivr.net/gh/cmachsocket/resources/avatar.png',
                ),
              ), //todo: bind to actual cover
              IconButton(
                icon: const Icon(Icons.skip_previous),
                onPressed: () {},
              ),
              IconButton(icon: const Icon(Icons.play_arrow), onPressed: () {}),
              IconButton(icon: const Icon(Icons.skip_next), onPressed: () {}),
            ],
          ),
          ProgressBar(
            progress: const Duration(
              seconds: 30,
            ), //todo: bind to actual progress
            buffered: const Duration(seconds: 60),
            total: const Duration(minutes: 3),
            onSeek: (duration) {},
          ),
        ],
      ),
    );
  }
}
