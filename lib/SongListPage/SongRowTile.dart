import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../models/Song.dart';
import '../widgets/linked_detail_text.dart';
import '../widgets/song_cover.dart';
import '../models/Default.dart';
import 'package:responsive_builder/responsive_builder.dart';

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
    this.selected = false,
    this.onToggleFavorite,
    this.onPlay,
    this.isLiked,
    this.extraTrailing,
    this.onLongPress,
  });

  final Song song;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onPlay;
  final bool selected;
  final void Function()? onLongPress;

  //额外的 trailing widget, 比如专辑列表页的 "更多" 按钮
  final Widget Function()? extraTrailing;

  /// 查询当前 song 是否被喜欢 —— callback 内部读 Rx，
  /// Obx 会自动监听那些 Rx（likedIds / likedAlbumIds 等）。
  final IsLikedGetter? isLiked;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      selected: selected,
      leading: AspectRatio(
        aspectRatio: DefaultValues.squardRatio,
        child: SongCover(url: song.coverUrl),
      ),
      title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: LinkedDetailText(song: song),
      onTap: onPlay,
      onLongPress: onLongPress,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OrientationLayoutBuilder(
            portrait: (context) => const SizedBox.shrink(),
            landscape: (context) => Text(song.durationLabel),
          ),
          // fav button 响应式：likedIds 变化时只重建 IconButton, 不是整行。
          // isLiked == null 路径不能包 Obx (GetX 检测空订阅会抛 "improper use"),
          // 直接用普通 IconButton;此路径本来就没 Rx 可订阅, 也不需要响应式。
          if (isLiked == null)
            IconButton(
              padding: DefaultValues.onlyZero,
              icon: const Icon(Icons.favorite_border),
              onPressed: null, // 没回调就不响应
              tooltip: '喜爱',
            )
          else
            Obx(() {
              final liked = isLiked!.call();
              return IconButton(
                padding: DefaultValues.onlyZero,
                icon: Icon(
                  liked ? Icons.favorite : Icons.favorite_border,
                  color: liked ? scheme.primary : null,
                ),
                onPressed: onToggleFavorite,
                tooltip: '喜爱',
              );
            }),
          IconButton(
            padding: DefaultValues.onlyZero,
            icon: const Icon(Icons.play_arrow),
            onPressed: onPlay,
            tooltip: '播放',
          ),
          if (extraTrailing != null) extraTrailing!(),
        ],
      ),
    );
  }
}
