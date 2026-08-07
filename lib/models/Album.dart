/// 专辑 / EP / 单曲 模型
///
/// 后续接 musiclibrary SDK 时,字段从 [netease_cloud_music_api.artist_album] / [album] 解析
enum AlbumType { album, ep, single }

extension AlbumTypeLabel on AlbumType {
  String get label => switch (this) {
        AlbumType.album => '专辑',
        AlbumType.ep => 'EP',
        AlbumType.single => '单曲',
      };
}

class Album {
  final String id;
  final String name;
  final String artist;
  final String coverUrl;
  final int songCount;
  final DateTime releaseDate;
  final AlbumType type;

  const Album({
    required this.id,
    required this.name,
    required this.artist,
    required this.coverUrl,
    required this.songCount,
    required this.releaseDate,
    required this.type,
  });
}
