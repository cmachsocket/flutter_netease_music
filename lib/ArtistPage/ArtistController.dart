import 'package:get/get.dart';

import '../models/Album.dart';
import '../models/ApiException.dart';
import '../services/LikedController.dart';
import '../services/repositories/ArtistRepository.dart';

/// ArtistDetail 页面专属 controller —— 管"专辑 / 歌曲"切换 + 专辑列表。
///
/// **不存**:艺人元信息(head 视觉 + 关注 + 播放全部)走 [SongListHeadController]
/// (`ArtistHeadController` 子类),歌曲列表走 [SongListBodyController]。
///
/// **职责边界**:
/// - view 切换(albums / songs)
/// - 专辑 / EP 网格数据(`fetchAlbums` 拉取,`albums` RxList 持有)
/// - 单张专辑的收藏(`isAlbumLiked` / `toggleAlbumFavorite`)
///   — 复用全局 [LikedController](LikedType.album),不引入新存储
///
/// **与 head / body 的关系**:三个 controller 共用同一 `controllerTag`,
/// 在 [ArtistDetailBinding] 时一起注入。head 只读"关注"(艺人级别),
/// body 只读"歌曲列表",本 controller 只管 view 状态 + 专辑列表 + 专辑收藏。
class ArtistController extends GetxController {
  ArtistController({required this.artistId});

  final String artistId;

  // ---- 依赖 -----------------------------------------------------------------

  final ArtistRepository _artistRepo = Get.find<ArtistRepository>();
  final LikedController _likedService = Get.find<LikedController>();

  // ---- 视图切换 -------------------------------------------------------------

  /// 当前显示哪个面板
  final Rx<ArtistView> view = ArtistView.albums.obs;

  /// 切换面板
  void setView(ArtistView v) {
    if (view.value == v) return;
    view.value = v;
    // 切到歌曲面板时,如果专辑还没拉过,补一次(用户可能直接切过去,
    // 但 albums 仍是上次结果,无需 reload —— 专辑是静态资源)
  }

  // ---- 专辑 / EP 列表 -------------------------------------------------------

  final RxList<Album> albums = <Album>[].obs;
  final RxBool isAlbumsLoading = false.obs;
  final RxnString albumsError = RxnString();

  @override
  void onInit() {
    super.onInit();
    _loadAlbums();
  }

  Future<void> _loadAlbums() async {
    isAlbumsLoading.value = true;
    albumsError.value = null;
    try {
      final list = await _artistRepo.fetchAlbums(artistId);
      albums.assignAll(list);
    } on ApiException catch (e) {
      albumsError.value = e.message;
      albums.clear();
    } catch (e) {
      albumsError.value = '加载专辑失败: $e';
      albums.clear();
    } finally {
      isAlbumsLoading.value = false;
    }
  }

  // ---- 单张专辑收藏 ---------------------------------------------------------

  bool isAlbumLiked(String albumId) =>
      _likedService.isLiked(albumId, LikedType.album);

  void toggleAlbumFavorite(String albumId) {
    // ignore: discarded_futures
    _likedService.toggle(albumId, LikedType.album);
  }
}

/// ArtistDetail 的视图切换 enum。
///
/// **放在 `ArtistController` 同文件**(不是单独的 models 文件):只有这个
/// controller 用,不需要全局 enum 暴露。
enum ArtistView { albums, songs }
