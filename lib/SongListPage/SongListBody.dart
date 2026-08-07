import 'package:flutter/material.dart';
import '../PlayListPage/PlayListController.dart' show Song;
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
  });

  final List<Song> songs;
  final bool isLoading;
  final String? errorMessage;
  final void Function(Song)? onToggleFavorite;
  final void Function(Song)? onPlay;

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
        return SongRowTile(
          song: song,
          onToggleFavorite: () => onToggleFavorite?.call(song),
          onPlay: () => onPlay?.call(song),
        );
      },
    );
  }
}
