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
}