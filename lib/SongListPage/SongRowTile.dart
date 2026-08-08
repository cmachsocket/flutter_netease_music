import 'package:flutter/material.dart';
import '../models/Song.dart';
import '../widgets/linked_detail_text.dart';
import '../widgets/netease_image.dart' show neteaseImageHeaders;

/// 歌曲行(供 SongListDetail / ArtistDetail 共用)
///
/// - 封面 + 标题 + "艺人 - 专辑" + (时长 + 喜爱 + 播放)
/// - 复用 [ListTile] + 内嵌 [_Cover] 错误降级,业务侧零硬编码
/// - onToggleFavorite / onPlay 由调用方绑定 controller 方法
class SongRowTile extends StatelessWidget {
  const SongRowTile({
    super.key,
    required this.song,
    this.onToggleFavorite,
    this.onPlay,
  });

  final Song song;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _Cover(url: song.coverUrl),
      title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: LinkedDetailText(
        song: Song(
          id: "",
          title: "",
          artist: "",
          album: "",
          coverUrl: "",
          duration: Duration.zero,
        ), // TODO: 传入真实 song
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(song.durationLabel),
          IconButton(
            icon: const Icon(Icons.favorite_border),
            onPressed: onToggleFavorite,
            tooltip: '喜爱',
          ),
          IconButton(
            icon: const Icon(Icons.play_arrow),
            onPressed: onPlay,
            tooltip: '播放',
          ),
        ],
      ),
    );
  }
}

/// 列表封面:复用网络图,失败时退化为 M3 标准 surface 色块 + 音符图标
class _Cover extends StatelessWidget {
  const _Cover({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Image.network(
      url,
      fit: BoxFit.cover,
      headers: neteaseImageHeaders,
      errorBuilder: (_, _, _) => Container(
        color: scheme.surfaceContainerHigh,
        alignment: Alignment.center,
        child: Icon(Icons.music_note, color: scheme.onSurfaceVariant),
      ),
    );
  }
}
