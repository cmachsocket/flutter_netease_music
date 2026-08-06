/// 艺人模型
///
/// 后续接 musiclibrary SDK 时,字段从 [netease_cloud_music_api.artists] / [artist_desc] 解析
class Artist {
  final String id;
  final String name;
  final String bio;
  final String photoUrl;

  /// 公开曲目总数
  final int songCount;

  /// 公开专辑/EP/单曲总数
  final int albumCount;

  const Artist({
    required this.id,
    required this.name,
    required this.bio,
    required this.photoUrl,
    this.songCount = 0,
    this.albumCount = 0,
  });
}
