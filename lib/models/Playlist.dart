import 'LibrarySummary.dart' show PlaylistSource;

/// 歌单元信息 (name/coverUrl/description + source)
class PlaylistMeta {
  final String name;
  final String coverUrl;
  final String description;

  /// 歌单来源。详情页 controller 读这个 Rx 决定显示 ❤️ 收藏还是 🗑 删除。
  ///
  /// 来自 `/playlist/detail` 响应里 `playlist.subscribed` 字段:
  ///   subscribed == true  → collected (我收藏的)
  ///   subscribed == false → created   (我自建的)
  final PlaylistSource source;

  const PlaylistMeta({
    required this.name,
    required this.coverUrl,
    required this.description,
    required this.source,
  });
}
