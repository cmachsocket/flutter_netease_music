import 'package:flutter/material.dart';
import '../models/Song.dart';
import 'SongRowTile.dart';

/// 歌曲列表壳:loading / empty / error / 真实列表 四态合一
///
/// - 调用方传入 [songs] / [isLoading] / [errorMessage] —— 通常从 controller 的 .obs 直接读
/// - 调用方把 toggleFavorite / playSong 包装成 (Song) -> void 后传进来
/// - 列表渲染走 [SongRowTile],业务侧零硬编码
class SongListBody extends StatelessWidget {
  const SongListBody({
    super.key,
    required this.songs,
    required this.isLoading,
    this.errorMessage,
    this.onToggleFavorite,
    this.onPlay,
    this.isLiked,
    this.extraTrailing,
    this.selectedHighlight,
  });

  final List<Song> songs;
  final bool isLoading;
  final String? errorMessage;
  final void Function(Song)? onToggleFavorite;
  final void Function(Song)? onPlay;
  // 为SongRowTile暴露的额外 trailing widget，同时会传递当前Song和index。
  final Widget Function(Song, int)? extraTrailing;
  final int? selectedHighlight;

  /// 查询某首 song 是否被喜欢(由 controller 提供,内部读 Rx)
  final bool Function(Song)? isLiked;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (errorMessage != null) {
      final scheme = Theme.of(context).colorScheme;
      return Center(
        child: Text(
          '加载失败: $errorMessage',
          style: TextStyle(color: scheme.error),
        ),
      );
    }
    if (songs.isEmpty) {
      return const Center(child: Text('暂无歌曲'));
    }
    return ListView.builder(
      itemCount: songs.length,
      itemBuilder: (context, index) {
        final song = songs[index];
        final selected =
            selectedHighlight != null && index == selectedHighlight;
        return SongRowTile(
          selected: selected,
          song: song,
          onToggleFavorite: () => onToggleFavorite?.call(song),
          onPlay: () => onPlay?.call(song),
          extraTrailing: extraTrailing != null
              ? () => extraTrailing!(song, index)
              : null,
          isLiked: () => isLiked?.call(song) ?? false,
        );
      },
    );
  }
}
