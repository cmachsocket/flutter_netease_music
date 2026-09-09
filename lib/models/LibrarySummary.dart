/// 首页 / 我的页 展示用的轻量摘要模型。
///
/// 原先散落在 HomeController(PlaylistCard) 和
/// LibraryController(PlaylistSummary/AlbumSummary/ArtistSummary) 里，
/// 抽到 models 方便 repository 与 controller 共享，避免反向 import controller。

/// 歌单来源 —— 区分自建 vs 收藏(将来可能加 recommended / default 等类型)。
///
/// /user/playlist 接口用 `subscribed` bool 区分,但 bool 二态可读性差
/// (调用点写 `if (p.subscribed)` 必须翻注释才知 true=收藏 / false=自建)。
/// 改成 enum 后:
///   - `p.source == PlaylistSource.created` 语义自解释
///   - switch 时有 exhaustiveness 检查,加新 case 时编译器会强制提醒
///   - 真值转换在 model.fromNeteaseJson 一处完成,调用方零负担
enum PlaylistSource {
  /// 我自己创建的(原 subscribed == false)
  created,

  /// 我收藏/订阅的(原 subscribed == true)
  collected,

  /// 专辑:`/album?id=X` 走的是另一条接口,`playlistId` 以 `album-` 前缀区分
  album,

  /// 艺人
  artist,

  //纯粹的列表
  pure,
}

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
/// `source` 区分自建 vs 收藏：
/// - [PlaylistSource.created] = 用户自己创建的歌单(红心按钮不渲染 —— 没有"再收藏一次"的语义)
/// - [PlaylistSource.collected] = 用户订阅/收藏的歌单(红心显示且可切换)
///
/// 来源于 /user/playlist.playlist[] 元素的 `subscribed` 字段：
///   subscribed == true  → collected
///   subscribed == false → created
///
/// 真值映射放在 [fromNeteaseJson],调用方只读 enum 不接触 bool。
class PlaylistSummary {
  final String id;
  final String name;
  final String picUrl;
  final int trackCount;
  final PlaylistSource source;

  const PlaylistSummary({
    required this.id,
    required this.name,
    required this.picUrl,
    required this.trackCount,
    required this.source,
  });

  /// /user/playlist.playlist[] 元素：
  /// - id, name, coverImgUrl, trackCount, subscribed
  factory PlaylistSummary.fromNeteaseJson(Map<String, dynamic> json) =>
      PlaylistSummary(
        id: json['id'].toString(),
        name: (json['name'] ?? '').toString(),
        picUrl: (json['coverImgUrl'] ?? '').toString(),
        trackCount: (json['trackCount'] as int?) ?? 0,
        source: json['subscribed'] == true
            ? PlaylistSource.collected
            : PlaylistSource.created,
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
