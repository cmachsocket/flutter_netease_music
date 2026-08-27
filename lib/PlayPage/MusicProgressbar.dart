import 'package:flutter/material.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:get/get.dart';
import 'PlayerController.dart';

class MusicProgressBar extends StatelessWidget {
  const MusicProgressBar({
    super.key,
    this.timeLabelLocation = TimeLabelLocation.below,
  });
  final TimeLabelLocation timeLabelLocation;
  @override
  Widget build(BuildContext context) {
    final controller = Get.find<PlayerController>();
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Obx(
      () => ProgressBar(
        timeLabelLocation: timeLabelLocation,
        progress: controller.position.value,
        buffered: controller.buffered.value,
        total: controller.duration.value,
        onSeek: controller.seek,
        progressBarColor: scheme.primary,
        baseBarColor: scheme.onSurface.withValues(alpha: 0.3),
        bufferedBarColor: scheme.primary.withValues(alpha: 0.3),
        thumbColor: scheme.primary,
        thumbGlowColor: scheme.primary.withValues(alpha: 0.4),
        timeLabelTextStyle: textTheme.bodySmall,
      ),
    );
  }
}
