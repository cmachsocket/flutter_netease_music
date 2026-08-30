import 'package:audio_service/audio_service.dart';

class Song {
  final String id;
  final String title;
  final String artist;
  final String? artistId;
  final String album;
  final String? albumId;
  final String coverUrl;
  final Duration duration;

  const Song({
    required this.id,
    required this.title,
    required this.artist,
    this.artistId,
    required this.album,
    this.albumId,
    required this.coverUrl,
    required this.duration,
  });

  String get durationLabel {
    final m = duration.inMinutes;
    final s = duration.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'artistId': artistId,
    'album': album,
    'albumId': albumId,
    'coverUrl': coverUrl,
    'duration': duration.inSeconds,
  };

  factory Song.fromJson(Map<String, dynamic> json) => Song(
    id: json['id'] as String,
    title: json['title'] as String,
    artist: json['artist'] as String,
    artistId: json['artistId'] as String?,
    album: json['album'] as String,
    albumId: json['albumId'] as String?,
    coverUrl: json['coverUrl'] as String,
    duration: Duration(seconds: json['duration'] as int),
  );

  /// 从网易云返回的 song JSON 解析
  ///
  /// **兼容两种 schema**:
  /// - /song/detail、`/search` 返回的 songs[]、playlist_track_all 等大部分场景
  /// - /search 用 `artists`(复数) + `album`(完整) + `duration`
  /// - /song/detail 用 `ar`(简写) + `al`(简写) + `dt`
  ///
  /// 主要字段:
  /// - id: u64 / str
  /// - name: 标题
  /// - 歌手列表: `ar` (list) 或 `artists` (list),取第一个 name / id
  /// - 专辑: `al` 或 `album`,取 name / id / picUrl
  /// - 时长(ms): `dt` 或 `duration`
  /// - fee: 0 免费 / 1 VIP / 8 非会员低音质
  factory Song.fromNeteaseJson(Map<String, dynamic> json) {
    // 艺人列表:优先 ar,其次 artists
    final arList = json['ar'] ?? json['artists'];
    final artists = arList is List ? arList : const [];
    final firstArtist = artists.isNotEmpty
        ? Map<String, dynamic>.from(artists.first as Map)
        : null;
    // 专辑:优先 al,其次 album
    final albumRaw = json['al'] ?? json['album'];
    final albumMap = albumRaw is Map
        ? Map<String, dynamic>.from(albumRaw)
        : null;
    // 时长:优先 dt(毫秒),其次 duration(毫秒),都是毫秒数
    final dt = json['dt'] is int
        ? json['dt'] as int
        : (json['duration'] is int ? json['duration'] as int : 0);
    return Song(
      id: json['id'].toString(),
      title: (json['name'] ?? '').toString(),
      artist: (firstArtist?['name'] ?? '').toString(),
      artistId: firstArtist?['id']?.toString(),
      album: (albumMap?['name'] ?? '').toString(),
      albumId: albumMap?['id']?.toString(),
      coverUrl: (albumMap?['picUrl'] ?? '').toString(),
      duration: Duration(milliseconds: dt),
    );
  }

  /// 统一的 Song -> MediaItem 映射。
  ///
  /// 业务模型 [Song] 保留在业务层；仅在接入 audio_service 的系统通知/锁屏/队列时
  /// 通过本扩展转换为 [MediaItem]。这样避免在两个 PlaybackService 里重复维护相同映射。
  ///
  /// [duration] 由调用方传入：mediaItem 展示时长需要播放器实时值，
  /// 而 [Song.duration] 是静态元数据，两者语义不同。
  /// [artHeaders] 由调用方传入：NCM CDN 需要伪装 UA 才能取封面。

  MediaItem toMediaItem({Duration? duration, Map<String, String>? artHeaders}) {
    return MediaItem(
      id: id,
      title: title,
      artist: artist,
      album: album,
      duration: duration,
      artUri: coverUrl.isEmpty ? null : Uri.tryParse(coverUrl),
      artHeaders: artHeaders,
    );
  }
}
