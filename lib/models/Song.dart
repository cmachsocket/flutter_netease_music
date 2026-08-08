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

  /// 从网易云 /song/detail 返回的 JSON 解析
  ///
  /// 主要字段(参考 MUSICLIBRARY.md song_detail 返回说明):
  /// - id: u64 / str
  /// - name: 标题
  /// - ar: List<Map> 歌手列表(取第一个 name / id)
  /// - al: Map 专辑(取 name / id / picUrl)
  /// - dt: u64 歌曲时长(毫秒)
  /// - fee: 0 免费 / 1 VIP / 8 非会员低音质
  factory Song.fromNeteaseJson(Map<String, dynamic> json) {
    final artists = (json['ar'] as List?) ?? const [];
    final firstArtist = artists.isNotEmpty
        ? Map<String, dynamic>.from(artists.first as Map)
        : null;
    final albumMap = json['al'] is Map
        ? Map<String, dynamic>.from(json['al'] as Map)
        : null;
    final dt = json['dt'] is int ? json['dt'] as int : 0;
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