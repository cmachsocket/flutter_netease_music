import 'package:flutter/material.dart';
import '../models/Song.dart';
import 'SongRowTile.dart';
import '../widgets/aspect_driven_grid.dart';

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
  });

  final List<Song> songs;
  final bool isLoading;
  final String? errorMessage;
  final void Function(Song)? onToggleFavorite;
  final void Function(Song)? onPlay;

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
    return AspectDrivenGrid(
      itemCount: songs.length,
      maxColumns: 1,
      baseColumns: 1,
      gapRatio: 0.02,
      childAspectRatio: 30.0,
      itemBuilder: (context, index) {
        final song = songs[index];

        return SongRowTile(
          song: song,
          onToggleFavorite: () => onToggleFavorite?.call(song),
          onPlay: () => onPlay?.call(song),
          isLiked: () => isLiked?.call(song) ?? false,
        );
      },
    );
  }
}
