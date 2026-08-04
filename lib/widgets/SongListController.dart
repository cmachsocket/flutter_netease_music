import 'package:get/get.dart';
import '../PlayListPage/PlayListController.dart' show Song;

/// 歌单详情页 controller
///
/// - 一张歌单一个实例(由 [playlistId] 区分);路由 pop 时随 binding 自动销毁
/// - 数据模型暂复用 [PlayListController] 里的 [Song](字段对齐,且避免重复定义)
/// - 后端接入 (TODO: 接 musiclibrary SDK 拉真歌单) 目前先用 [load] 内部的占位数据
class SongListController extends GetxController {
  SongListController({required this.playlistId});

  /// 路由传进来的歌单 ID
  final String playlistId;

  final RxList<Song> songs = <Song>[].obs;
  final RxBool isLoading = false.obs;
  final RxnString errorMessage = RxnString();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  /// 拉当前歌单 ([playlistId]) 的曲目
  ///
  /// 现在是 stub:按 playlistId 给一组占位 Song,模拟一次异步拉取
  /// 之后接 SDK 时换成 `await musiclibrary.getPlaylistDetail(playlistId)`
  Future<void> load() async {
    isLoading.value = true;
    errorMessage.value = null;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      songs.assignAll(_seedFor(playlistId));
    } catch (e) {
      errorMessage.value = e.toString();
    } finally {
      isLoading.value = false;
    }
  }

  List<Song> _seedFor(String id) {
    final cover =
        'https://cdn.jsdelivr.net/gh/cmachsocket/resources/avatar.png';
    switch (id) {
      case 'daily':
        return [
          Song(
            id: 'd1',
            title: '为你推荐 - 红莲',
            artist: '艺术家 A',
            album: 'Daily Mix',
            coverUrl: cover,
            duration: const Duration(minutes: 3, seconds: 30),
          ),
          Song(
            id: 'd2',
            title: '为你推荐 - 远海',
            artist: '艺术家 B',
            album: 'Daily Mix',
            coverUrl: cover,
            duration: const Duration(minutes: 4, seconds: 5),
          ),
          Song(
            id: 'd3',
            title: '为你推荐 - 夜行',
            artist: '艺术家 C',
            album: 'Daily Mix',
            coverUrl: cover,
            duration: const Duration(minutes: 2, seconds: 56),
          ),
        ];
      case 'private-fm':
        return [
          Song(
            id: 'p1',
            title: '私人 FM - 早安',
            artist: '艺术家 X',
            album: 'FM',
            coverUrl: cover,
            duration: const Duration(minutes: 3, seconds: 2),
          ),
          Song(
            id: 'p2',
            title: '私人 FM - 微风',
            artist: '艺术家 Y',
            album: 'FM',
            coverUrl: cover,
            duration: const Duration(minutes: 3, seconds: 47),
          ),
          Song(
            id: 'p3',
            title: '私人 FM - 山林',
            artist: '艺术家 Z',
            album: 'FM',
            coverUrl: cover,
            duration: const Duration(minutes: 4, seconds: 21),
          ),
        ];
      default:
        return [
          Song(
            id: '$id-1',
            title: '歌单 $id - 1',
            artist: '艺术家 A',
            album: 'Mixed',
            coverUrl: cover,
            duration: const Duration(minutes: 3, seconds: 12),
          ),
          Song(
            id: '$id-2',
            title: '歌单 $id - 2',
            artist: '艺术家 B',
            album: 'Mixed',
            coverUrl: cover,
            duration: const Duration(minutes: 4, seconds: 0),
          ),
          Song(
            id: '$id-3',
            title: '歌单 $id - 3',
            artist: '艺术家 C',
            album: 'Mixed',
            coverUrl: cover,
            duration: const Duration(minutes: 5, seconds: 24),
          ),
        ];
    }
  }

  /// 喜爱切换(占位)。后续可挂 [RxSet<String>] 持久化 + 联动 PlayListController 真正切换
  void toggleFavorite(String songId) {
    // TODO: 接 controller.toggleFavorite(songId);接 player 那边通知
  }

  /// 播放(占位)。后续接 PlayerController:
  /// - 把 song 入到 [PlayListController.playlist] 末尾
  /// - currentIndex.value = playlist.length - 1
  /// - player.playAt(currentIndex)
  void playSong(Song song) {
    // TODO: 联动 PlayListController + PlayerController
  }
}
