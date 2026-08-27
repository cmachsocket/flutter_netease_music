import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../models/Song.dart';
import '../widgets/linked_detail_text.dart';
import '../widgets/song_cover.dart';

/// 查询 song 是否被喜欢的回调（无参：调用方包好 song 后注入,SongRowTile 内部 Obx 调用)
typedef IsLikedGetter = bool Function();

/// 歌曲行(供 SongListDetail / ArtistDetail 共用)
///
/// - 封面 + 标题 + "艺人 - 专辑" + (时长 + 喜爱 + 播放)
/// - 复用 [ListTile] + 内嵌 [SongCover] 错误降级，业务侧零硬编码
/// - onToggleFavorite / onPlay / isLiked 由调用方绑定 controller 方法
class SongRowTile extends StatelessWidget {
  const SongRowTile({
    super.key,
    required this.song,
    this.onToggleFavorite,
    this.onPlay,
    this.isLiked,
  });

  final Song song;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onPlay;

  /// 查询当前 song 是否被喜欢 —— 调用方在 Obx 内调用,内部读 Rx 触发响应式 rebuild
  final IsLikedGetter? isLiked;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: AspectRatio(aspectRatio: 1.0, child: SongCover(url: song.coverUrl)),
      title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: LinkedDetailText(song: song),
      onTap: onPlay,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(song.durationLabel),
          IconButton(
            icon: isLiked == null
                ? const Icon(Icons.favorite_border)
                : Obx(() {
                    final liked = isLiked!.call();
                    return Icon(
                      liked ? Icons.favorite : Icons.favorite_border,
                      color: liked
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    );
                  }),
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

