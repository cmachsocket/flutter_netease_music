/// 首页 / 我的页 展示用的轻量摘要模型。
///
/// 原先散落在 HomeController(PlaylistCard) 和
/// LibraryController(PlaylistSummary/AlbumSummary/ArtistSummary) 里，
/// 抽到 models 方便 repository 与 controller 共享，避免反向 import controller。

/// 首页推荐歌单卡片。
class PlaylistCard {
  final String id;
  final String name;
  final String picUrl;

  const PlaylistCard({
    required this.id,
    required this.name,
    required this.picUrl,
  });

  /// 网易云 /personalized 返回的 result 数组元素：
  /// - id: u64 / str
  /// - name: 歌单名
  /// - picUrl: 封面图（可空）
  factory PlaylistCard.fromNeteaseJson(Map<String, dynamic> json) =>
      PlaylistCard(
        id: json['id'].toString(),
        name: (json['name'] ?? '').toString(),
        picUrl: (json['picUrl'] ?? '').toString(),
      );
}

/// 我的歌单摘要（Library tab 1）。
///
/// `subscribed` 区分自建 vs 收藏：
/// - `true` = 用户订阅/收藏的歌单（红心显示且可切换）
/// - `false` = 用户自己创建的歌单（红心按钮不渲染）
///
/// 来源于 /user/playlist.playlist[] 元素的 `subscribed` 字段
/// （注意：LibraryRepository.fetchPlaylists 之前丢失了这个字段，
///  自建/收藏混在同一个 list 里渲染成一样的红心 —— 现在补回来）
class PlaylistSummary {
  final String id;
  final String name;
  final String picUrl;
  final int trackCount;
  final bool subscribed;

  const PlaylistSummary({
    required this.id,
    required this.name,
    required this.picUrl,
    required this.trackCount,
    required this.subscribed,
  });

  /// /user/playlist.playlist[] 元素：
  /// - id, name, coverImgUrl, trackCount, subscribed
  factory PlaylistSummary.fromNeteaseJson(Map<String, dynamic> json) =>
      PlaylistSummary(
        id: json['id'].toString(),
        name: (json['name'] ?? '').toString(),
        picUrl: (json['coverImgUrl'] ?? '').toString(),
        trackCount: (json['trackCount'] as int?) ?? 0,
        subscribed: json['subscribed'] == true,
      );
}

/// 订阅专辑摘要（Library tab 2）。
class AlbumSummary {
  final String id;
  final String name;
  final String artist;
  final String picUrl;

  const AlbumSummary({
    required this.id,
    required this.name,
    required this.artist,
    required this.picUrl,
  });

  /// /album/sublist.data[] 元素：
  /// - id, name, artists[0].name, picUrl
  factory AlbumSummary.fromNeteaseJson(Map<String, dynamic> json) {
    final artists = (json['artists'] as List?) ?? const [];
    final firstArtist = artists.isNotEmpty
        ? Map<String, dynamic>.from(artists.first as Map)
        : null;
    return AlbumSummary(
      id: json['id'].toString(),
      name: (json['name'] ?? '').toString(),
      artist: (firstArtist?['name'] ?? '').toString(),
      picUrl: (json['picUrl'] ?? '').toString(),
    );
  }
}

/// 关注艺人摘要（Library tab 3）。
class ArtistSummary {
  final String id;
  final String name;
  final String picUrl;

  const ArtistSummary({
    required this.id,
    required this.name,
    required this.picUrl,
  });

  /// /user/follow/mixed 的 artistInfo 元素：
  /// - id, name, picUrl
  factory ArtistSummary.fromNeteaseJson(Map<String, dynamic> json) =>
      ArtistSummary(
        id: json['id'].toString(),
        name: (json['name'] ?? '').toString(),
        picUrl: (json['picUrl'] ?? '').toString(),
      );
}
