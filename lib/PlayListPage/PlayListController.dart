import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../PlayPage/PlayerController.dart';
import '../models/Song.dart';

/// 单曲数据模型(后续从后端/SDK 注入时扩展字段)

/// 播放列表页的 controller
///
/// - [playlist] / [currentIndex] 用 GetStorage 持久化,删除/选中后真正落盘
/// - 首次启动 (无持久化数据) 时 seed 4 首示例
class PlayListController extends GetxController {
  static const _storageKey = 'playlist_v1';
  static const _currentIndexKey = 'playlist_currentIndex_v1';

  final RxList<Song> playlist = <Song>[].obs;

  /// 当前播放项的索引(与 PlayerController 后续联动切歌)
  final RxInt currentIndex = 0.obs;

  /// 兼容旧字段名
  int get listTotal => playlist.length;

  @override
  void onInit() {
    super.onInit();
    _hydrate();
  }

  /// 从 GetStorage 加载;首次则 seed 默认示例
  void _hydrate() {
    final box = GetStorage();
    final raw = box.read<List>(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      playlist.assignAll(
        raw
            .whereType<Map>()
            .map((e) => Song.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
    } else {
      _seedDefaults();
    }
    final savedIdx = box.read<int>(_currentIndexKey) ?? 0;
    currentIndex.value = (savedIdx >= 0 && savedIdx < playlist.length)
        ? savedIdx
        : 0;
  }

  void _seedDefaults() {
    playlist.assignAll([
      const Song(
        id: '1',
        title: '示例歌曲 A',
        artist: '艺术家 A',
        album: '首张专辑',
        coverUrl:
            'https://cdn.jsdelivr.net/gh/cmachsocket/resources/avatar.png',
        duration: Duration(minutes: 3, seconds: 45),
      ),
      const Song(
        id: '2',
        title: '示例歌曲 B - 一首稍微长一点的歌',
        artist: '艺术家 B',
        album: 'The Second Album',
        coverUrl:
            'https://cdn.jsdelivr.net/gh/cmachsocket/resources/avatar.png',
        duration: Duration(minutes: 4, seconds: 12),
      ),
      const Song(
        id: '3',
        title: '示例歌曲 C',
        artist: '艺术家 C',
        album: '秋日私语',
        coverUrl:
            'https://cdn.jsdelivr.net/gh/cmachsocket/resources/avatar.png',
        duration: Duration(minutes: 2, seconds: 30),
      ),
      const Song(
        id: '4',
        title: '示例歌曲 D',
        artist: '艺术家 D',
        album: 'Demo Collection',
        coverUrl:
            'https://cdn.jsdelivr.net/gh/cmachsocket/resources/avatar.png',
        duration: Duration(minutes: 5, seconds: 8),
      ),
    ]);
    _persist();
  }

  void _persist() {
    final box = GetStorage();
    box.write(_storageKey, playlist.map((s) => s.toJson()).toList());
    box.write(_currentIndexKey, currentIndex.value);
  }

  /// 选中第 [index] 项
  void selectIndex(int index) {
    if (index < 0 || index >= playlist.length) return;
    currentIndex.value = index;
    _persist();
  }

  /// 删除第 [index] 项,并修正 [currentIndex] 使其继续指向"同一首歌"
  ///
  /// - 删的是当前播放之前 → currentIndex -1
  /// - 删的是当前播放本身 → 选同一位置的下一首(如果刪到末尾则选新末尾)
  /// - 删的是当前播放之后 → 不变
  /// - 删完为空 → currentIndex = 0
  /// - 删的是当前播放 → 联动 [PlayerController] 重置 position + duration
  void removeSong(int index) {
    if (index < 0 || index >= playlist.length) return;
    final wasCurrent = index == currentIndex.value;

    playlist.removeAt(index);

    if (playlist.isEmpty) {
      currentIndex.value = 0;
    } else if (index < currentIndex.value) {
      currentIndex.value -= 1;
    } else if (index == currentIndex.value) {
      if (currentIndex.value >= playlist.length) {
        currentIndex.value = playlist.length - 1;
      }
    }

    _persist();

    // 联动 PlayerController:删的是当前播放 → 重置 progress / duration
    if (wasCurrent) {
      final player = Get.find<PlayerController>();
      player.updatePosition(Duration.zero);
      player.updateDuration(
        playlist.isEmpty
            ? Duration.zero
            : playlist[currentIndex.value].duration,
      );
    }
  }
}

class PlayListBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<PlayListController>(() => PlayListController());
  }
}
