import 'package:flutter/material.dart';
import 'package:flutter_lyric/flutter_lyric.dart';
import 'package:get/get.dart';

import 'PlayerController.dart';

/// 可滚动歌词栏:由 [flutter_lyric] 提供渲染 + 高亮 + 自动滚动 + 触摸 seek
///
/// 字号 / 颜色全部走主题,在 [LyricStyles.default1] 基础上 copyWith 覆盖外观。
class Lyrics extends StatelessWidget {
  const Lyrics({super.key});

  @override
  Widget build(BuildContext context) {
    final player = Get.find<PlayerController>();
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return LyricView(
      controller: player.lyricController,
      width: double.infinity,
      height: double.infinity,
      style: LyricStyles.default1.copyWith(
        textStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        activeStyle: textTheme.titleMedium?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.bold,
        ),
        activeHighlightColor: scheme.primary,
        textAlign: TextAlign.center,
        contentAlignment: CrossAxisAlignment.center,
      ),
    );
  }
}
