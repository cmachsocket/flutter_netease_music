import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../models/Song.dart';
import '../widgets/linked_detail_text.dart';
import '../widgets/song_cover.dart';

/// 查询 song 是否被喜欢的回调（无参：调用方包好 song 后注入）
typedef IsLikedGetter = bool Function();

/// 歌曲行（供 SongListDetail / ArtistDetail 共用）
///
/// - **fav button 响应式**：[isLiked] 回调被 Obx 包裹，likedIds 变化时
///   只重建 IconButton（不是整行）—— 与 [LineSongListCard] 同思路。
/// - 如果 caller 不传 [isLiked]（null），Obx 闭包里不会触达任何 Rx，零开销。
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

  /// 查询当前 song 是否被喜欢 —— callback 内部读 Rx，
  /// Obx 会自动监听那些 Rx（likedIds / likedAlbumIds 等）。
  final IsLikedGetter? isLiked;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: AspectRatio(
        aspectRatio: 1.0,
        child: SongCover(url: song.coverUrl),
      ),
      title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: LinkedDetailText(song: song),
      onTap: onPlay,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(song.durationLabel),
          // Obx 只包 fav button：likedIds 变化时只重建这个 IconButton，
          // 其他部分（leading/title/subtitle/下面的 play button）不受影响。
          // isLiked 为 null 时 Obx 闭包里不触达 Rx → 零监听零重建开销。
          Obx(() {
            final liked = isLiked?.call() ?? false;
            return IconButton(
              icon: Icon(
                liked ? Icons.favorite : Icons.favorite_border,
                color: liked ? scheme.primary : null,
              ),
              onPressed: onToggleFavorite,
              tooltip: '喜爱',
            );
          }),
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
