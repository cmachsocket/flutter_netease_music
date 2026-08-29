import 'package:get/get.dart';

import '../models/Album.dart';
import '../models/Song.dart';
import '../services/PlayQueueService.dart';
import '../services/LikedAlbumsService.dart';
import '../services/LikedArtistsService.dart';
import '../services/LikedSongsService.dart';
import '../services/repositories/artist_repository.dart';
import '../models/Artist.dart';

/// 艺人详情页 tab 枚举
///
/// 不用裸 int — enum 在编译期挡住 setView(99) 这种垃圾值,
/// switch 也带 exhaustiveness 检查(加新 tab 时漏一个 case 编译器报错)。
enum ArtistView { albums, songs }

/// 艺人页 controller
///
/// - 一位艺人一个实例(由 [artistId] 区分);路由 pop 时随 binding 自动销毁
/// - [load] 并行拉 `artists` / `artist_album` / `artist_songs` 三个接口
class ArtistController extends GetxController {
  ArtistController({required this.artistId});

  /// 路由传进来的艺人 ID
  final String artistId;

  final PlayQueueService queue = Get.find<PlayQueueService>();
  final LikedSongsService _likedService = Get.find<LikedSongsService>();
  final LikedArtistsService _likedArtists = Get.find<LikedArtistsService>();
  final ArtistRepository _artistRepo = Get.find<ArtistRepository>();

  final Rxn<Artist> artist = Rxn<Artist>();
  final RxList<Album> albums = <Album>[].obs;
  final RxList<Song> songs = <Song>[].obs;
  final RxBool isLoading = false.obs;
  final RxnString errorMessage = RxnString();
  final RxBool isFollowing = false.obs;

  /// 当前选中的 tab (albums = 专辑/EP 网格, songs = 所有歌曲列表)
  final Rx<ArtistView> view = ArtistView.albums.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  /// 并行拉艺人元信息 + 专辑列表 + 所有歌曲
  ///
  /// - 三个接口独立,任一失败不影响其它两路结果写入
  /// - 全失败才把整体错误信息写到 [errorMessage]
  /// - API 调用集中到 [ArtistRepository]。
  Future<void> load() async {
    isLoading.value = true;
    errorMessage.value = null;
    final id = artistId;

    // Repository 内部已 try/catch,失败返回 null/[],这里只判 null 表走后续安全赋值
    final results = await Future.wait([
      _artistRepo.fetchArtist(id),
      _artistRepo.fetchAlbums(id),
      _artistRepo.fetchSongs(id, limit: 50),
    ]);

    final info = results[0] as ArtistInfo?;
    final albumsFetched = results[1] as List<Album>;
    final songsFetched = results[2] as List<Song>;

    if (info != null) {
      artist.value = info.artist;
      // /artists 响应里 artist 项有 `followed`(bool)字段——优先用后端真值
      final followed = info.followed;
      if (followed != null) {
        isFollowing.value = followed;
      }
    }
    albums.assignAll(albumsFetched);
    songs.assignAll(songsFetched);

    if (artist.value == null && albums.isEmpty && songs.isEmpty) {
      // 三路都失败,展示错误
      errorMessage.value = '加载失败';
    }
    isLoading.value = false;
  }

  void setView(ArtistView v) => view.value = v;

  void toggleFollow() {
    // 乐观更新本地状态(纯 UI 反映,后端 toggle 交由 service)
    isFollowing.toggle();
    // ignore: discarded_futures
    _likedArtists.toggle(artistId);
  }

  void toggleFavorite(String songId) {
    // ignore: discarded_futures
    _likedService.toggle(songId);
  }

  /// 查询某首歌是否被喜欢(同 SongListController)
  ///
  /// - 读 .value 触发 Obx 跟踪(contains 走内部 _value 不跟踪)
  bool isLiked(String songId) =>
      // ignore: invalid_use_of_protected_member
      _likedService.likedIds.value.contains(songId);

  /// 查询当前艺人是否已关注
  bool isArtistLiked() => isFollowing.value;

  /// 查询某张专辑是否被收藏
  ///
  /// - 读 .value 触发 Obx 跟踪
  bool isAlbumLiked(String albumId) =>
      // ignore: invalid_use_of_protected_member
      Get.find<LikedAlbumsService>().likedAlbumIds.value.contains(albumId);

  void toggleAlbumFavorite(String albumId) {
    // ignore: discarded_futures
    Get.find<LikedAlbumsService>().toggle(albumId);
  }

  void playSong(Song song) {
    queue.playSong(song);
  }

  /// 播放该艺人所有歌曲(把当前已加载的 songs 全部入队)
  void playAll() {
    queue.playSongs(songs.toList());
  }
}
