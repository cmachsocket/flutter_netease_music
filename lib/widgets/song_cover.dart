import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/Headers.dart';

/// 歌曲 / 专辑 / 艺人 / 歌单封面通用 widget
///
/// - 加载成功 → 网络图
/// - URL 为空(常见:search 接口 album 项只有 picId 没 picUrl) → 直接占位,不调 CachedNetworkImage
/// - 网络失败 → 占位容器 (M3 surface 色块 + 音符图标)
///
/// 业务侧零硬编码:
/// - 占位色 = `Theme.of(context).colorScheme.surfaceContainerHigh`
/// - 图标色 = `Theme.of(context).colorScheme.onSurfaceVariant`
/// - 不写圆角数字,接受 [ListTile.leading] 默认方形容器
class SongCover extends StatelessWidget {
  const SongCover({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      color: scheme.surfaceContainerHigh,
      alignment: Alignment.center,
      child: Icon(Icons.music_note, color: scheme.onSurfaceVariant),
    );

    // 空 URL 守卫:不调 CachedNetworkImage,直接占位
    // (避免 URL null / "" 时 Image.network 抛解析异常)
    if (url.isEmpty) return placeholder;

    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      httpHeaders: NeteaseImageHeaders.neteaseImageHeaders,
      errorWidget: (_, _, _) => placeholder,
    );
  }
}
