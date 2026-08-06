import 'package:get/get.dart';

import '../PlayListPage/PlayListController.dart' show Song;
import 'Album.dart';
import 'Artist.dart';

/// 艺人页 controller
///
/// - 一位艺人一个实例(由 [artistId] 区分);路由 pop 时随 binding 自动销毁
/// - 一次 [load] 同时拉艺人元信息 + 专辑/EP 列表 + 所有歌曲(stub 阶段一次性 assign)
/// - 后续接 SDK 时拆成 `artist` / `artist_album` / `artist_songs` 三个并行请求即可
class ArtistController extends GetxController {
  ArtistController({required this.artistId});

  /// 路由传进来的艺人 ID
  final String artistId;

  final Rxn<Artist> artist = Rxn<Artist>();
  final RxList<Album> albums = <Album>[].obs;
  final RxList<Song> songs = <Song>[].obs;
  final RxBool isLoading = false.obs;
  final RxnString errorMessage = RxnString();
  final RxBool isFollowing = false.obs;

  /// 0 = 专辑 / EP 网格;1 = 所有歌曲列表
  final RxInt viewIndex = 0.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      artist.value = _seedArtist(artistId);
      albums.assignAll(_seedAlbums(artistId));
      songs.assignAll(_seedSongs(artistId));
    } catch (e) {
      errorMessage.value = e.toString();
    } finally {
      isLoading.value = false;
    }
  }

  void setView(int index) => viewIndex.value = index;

  void toggleFollow() {
    isFollowing.toggle();
  }

  void toggleFavorite(String songId) {
    // TODO: 接 PlayListController 持久化 + 联动 PlayerController
  }

  void playSong(Song song) {
    // TODO: 联动 PlayListController + PlayerController
  }

  // ─── stub 数据 ────────────────────────────────────────────────────────────

  Artist _seedArtist(String id) {
    return Artist(
      id: id,
      name: '艺术家 $id',
      bio: '这是一个示例艺术家的简介,描述其音乐风格、代表作品等。',
      photoUrl:
          'https://cdn.jsdelivr.net/gh/cmachsocket/resources/avatar.png',
      songCount: 3,
      albumCount: 2,
    );
  }

  List<Album> _seedAlbums(String id) {
    final cover =
        'https://cdn.jsdelivr.net/gh/cmachsocket/resources/avatar.png';
    return [
      Album(
        id: '$id-album-1',
        name: '示例专辑 1',
        artist: '艺术家 $id',
        coverUrl: cover,
        songCount: 12,
        releaseDate: DateTime(2024, 3, 15),
        type: AlbumType.album,
      ),
      Album(
        id: '$id-album-2',
        name: '示例 EP',
        artist: '艺术家 $id',
        coverUrl: cover,
        songCount: 5,
        releaseDate: DateTime(2023, 11, 8),
        type: AlbumType.ep,
      ),
    ];
  }

  // (entry point TBD —— 跟 SongListCard 同款 inline BindingsBuilder 写法:
  //   Get.to(
  //     () => ArtistDetail(artistId: id),
  //     id: AppShell.shellNavigatorId,
  //     binding: BindingsBuilder(() {
  //       Get.lazyPut<ArtistController>(() => ArtistController(artistId: id));
  //     }),
  //   ),
  // )

  List<Song> _seedSongs(String id) {
    final cover =
        'https://cdn.jsdelivr.net/gh/cmachsocket/resources/avatar.png';
    return [
      Song(
        id: '$id-s1',
        title: '热单 - 红莲',
        artist: '艺术家 $id',
        album: '示例专辑 1',
        coverUrl: cover,
        duration: const Duration(minutes: 3, seconds: 30),
      ),
      Song(
        id: '$id-s2',
        title: '热单 - 远海',
        artist: '艺术家 $id',
        album: '示例专辑 1',
        coverUrl: cover,
        duration: const Duration(minutes: 4, seconds: 5),
      ),
      Song(
        id: '$id-s3',
        title: 'EP 同名 - 夜行',
        artist: '艺术家 $id',
        album: '示例 EP',
        coverUrl: cover,
        duration: const Duration(minutes: 2, seconds: 56),
      ),
    ];
  }
}
