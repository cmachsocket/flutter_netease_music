/// 艺人模型
///
/// 字段从 [netease_cloud_music_api.artists] / [artist_detail] / [artist_desc] 解析
class Artist {
  final String id;
  final String name;
  final String bio;
  final String photoUrl;

  /// 公开曲目总数
  final int songCount;

  /// 公开专辑/EP/单曲总数
  final int albumCount;

  /// 粉丝数
  final int fanCount;

  const Artist({
    required this.id,
    required this.name,
    required this.bio,
    required this.photoUrl,
    this.songCount = 0,
    this.albumCount = 0,
    this.fanCount = 0,
  });

  /// 从网易云 /artists 或 /artist/detail 返回的 JSON 解析
  ///
  /// 主要字段:
  /// - id, name
  /// - picUrl / img1v1Url: 艺人头像
  /// - briefDesc / desc: 简介
  /// - musicSize: 曲目数
  /// - albumSize: 专辑数
  /// - fans: 粉丝数(可能不存在,如 /artist/album 返回的 summary)
  factory Artist.fromNeteaseJson(Map<String, dynamic> json) {
    final pic = json['picUrl'] ?? json['img1v1Url'] ?? '';
    return Artist(
      id: json['id'].toString(),
      name: (json['name'] ?? '').toString(),
      bio: (json['briefDesc'] ?? json['desc'] ?? '').toString(),
      photoUrl: pic.toString(),
      songCount: json['musicSize'] is int ? json['musicSize'] as int : 0,
      albumCount: json['albumSize'] is int ? json['albumSize'] as int : 0,
      fanCount: json['fans'] is int ? json['fans'] as int : 0,
    );
  }
}