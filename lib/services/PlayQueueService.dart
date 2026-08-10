import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../models/Song.dart';

/// 播放队列服务
///
/// - 只负责队列数据、当前索引和播放队列的持久化
/// - 不负责任何页面渲染
class PlayQueueService extends GetxService {
  static const _storageKey = 'playlist_v1';
  static const _currentIndexKey = 'playlist_currentIndex_v1';

  final RxList<Song> playlist = <Song>[].obs;
  final RxInt currentIndex = 0.obs;

  @override
  void onInit() {
    super.onInit();
    _hydrate();
  }

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
    }
    final savedIdx = box.read<int>(_currentIndexKey) ?? 0;
    currentIndex.value = (savedIdx >= 0 && savedIdx < playlist.length)
        ? savedIdx
        : 0;
  }

  void _persist() {
    final box = GetStorage();
    box.write(_storageKey, playlist.map((s) => s.toJson()).toList());
    box.write(_currentIndexKey, currentIndex.value);
  }

  void selectIndex(int index) {
    if (index < 0 || index >= playlist.length) return;
    currentIndex.value = index;
    _persist();
  }

  Future<void> playSong(Song song) async {
    final idx = playlist.indexWhere((s) => s.id == song.id);
    if (idx >= 0) {
      currentIndex.value = idx;
    } else {
      playlist.add(song);
      currentIndex.value = playlist.length - 1;
    }
    _persist();
  }

  Future<void> playSongs(List<Song> songs, {Song? startSong}) async {
    if (songs.isEmpty) return;

    final uniqueSongs = <Song>[];
    final seenIds = <String>{};
    for (final song in songs) {
      if (seenIds.add(song.id)) {
        uniqueSongs.add(song);
      }
    }

    playlist.assignAll(uniqueSongs);

    final startIndex = startSong == null
        ? 0
        : playlist.indexWhere((song) => song.id == startSong.id);
    currentIndex.value = startIndex >= 0 ? startIndex : 0;
    _persist();
  }

  void removeSong(int index) {
    if (index < 0 || index >= playlist.length) return;

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
  }
}
