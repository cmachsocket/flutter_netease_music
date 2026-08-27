import 'dart:math';

import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../models/Song.dart';

/// 播放模式
///
/// - [sequential]: 顺序循环, 队尾 → 跳回首首(双向都 wrap, 跟常用播放器一致)
/// - [shuffle]:    乱序播放, 不重复抽到同一首直到 playlist 全部播过一轮
/// - [repeatOne]:  单曲循环, 播完当前首自动重播(不走 next)
enum PlayMode { sequential, shuffle, repeatOne }

/// 播放队列服务
///
/// - 只负责队列数据、当前索引、播放模式和播放队列的持久化
/// - 不负责任何页面渲染
/// - **next/prev 走 service** —— UI 层不该自己算"下一首要播谁",
///   因为 shuffle/repeatOne 模式下游算法不一样
class PlayQueueService extends GetxService {
  static const _storageKey = 'playlist_v1';
  static const _currentIndexKey = 'playlist_currentIndex_v1';
  static const _modeKey = 'playlist_mode_v1';
  static const notToPlay = -1;
  static const constHeadOfTheQueue = 0;
  int get headOfTheQueue => constHeadOfTheQueue;
  int get tailOfTheQueue => playlist.length - 1;
  final RxList<Song> playlist = <Song>[].obs;
  final RxInt currentIndex = 0.obs;
  final Rx<PlayMode> mode = PlayMode.sequential.obs;

  /// shuffle 模式专用: 这一轮里已经播过的歌的 id 集合
  /// 一轮播完(全部 id 都进过)清空, 重新随机
  final Set<String> _shufflePlayed = <String>{};
  final Random _rng = Random();

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
    currentIndex.value =
        (savedIdx >= headOfTheQueue && savedIdx <= tailOfTheQueue)
        ? savedIdx
        : headOfTheQueue;
    // mode 持久化 (没存过 → sequential)
    final savedMode = box.read<String>(_modeKey);
    mode.value = _decodeMode(savedMode);
  }

  void _persist() {
    final box = GetStorage();
    box.write(_storageKey, playlist.map((s) => s.toJson()).toList());
    box.write(_currentIndexKey, currentIndex.value);
    box.write(_modeKey, _encodeMode(mode.value));
  }

  static String _encodeMode(PlayMode m) => m.name;
  static PlayMode _decodeMode(String? s) {
    for (final m in PlayMode.values) {
      if (m.name == s) return m;
    }
    return PlayMode.sequential;
  }

  void selectIndex(int index) {
    if (index < 0 || index >= playlist.length) return;
    currentIndex.value = index;
    // 切歌 → 在 shuffle 模式下不算"已播过这首", 重置轮询
    if (mode.value == PlayMode.shuffle) {
      _shufflePlayed
        ..clear()
        ..add(playlist[index].id);
    }
    _persist();
  }

  /// 切换播放模式 (UI 那个 mode 按钮调这个)
  ///
  /// - 切到 shuffle 时: 重置 _shufflePlayed, 把当前首标为已播过,
  ///   这样 next 不会立刻又抽到同一首
  void setMode(PlayMode m) {
    if (mode.value == m) return;
    mode.value = m;
    _shufflePlayed.clear();
    if (m == PlayMode.shuffle && playlist.isNotEmpty) {
      _shufflePlayed.add(playlist[currentIndex.value].id);
    }
    _persist();
  }

  /// 计算"下一首要播的索引"
  ///
  /// - **sequential**: currentIndex + 1, 队尾 wrap 回 0 (顺序循环)
  /// - **shuffle**:    从未播过的歌里随机抽; 全部播过一轮 → 清空轮询重来
  /// - **repeatOne**:  当前首, 不变 —— Controller 走 reload-current-song 路径
  ///
  /// **不修改 currentIndex** —— 调用方拿到返回值自己 selectIndex
  int nextIndex() {
    if (playlist.isEmpty) return notToPlay;
    switch (mode.value) {
      case PlayMode.sequential:
        return (currentIndex.value + 1) % playlist.length;
      case PlayMode.shuffle:
        return _nextShuffleIndex();
      case PlayMode.repeatOne:
        return currentIndex.value;
    }
  }

  /// 计算"上一首要播的索引"
  ///
  /// - **sequential**: currentIndex - 1, 队首 wrap 到队尾 (双向循环对称)
  /// - **shuffle**:    同 next, 随机抽
  /// - **repeatOne**:  当前首, 不变
  int prevIndex() {
    if (playlist.isEmpty) return notToPlay;
    switch (mode.value) {
      case PlayMode.sequential:
        final p = currentIndex.value - 1;
        return p < headOfTheQueue ? tailOfTheQueue : p;
      case PlayMode.shuffle:
        return _nextShuffleIndex();
      case PlayMode.repeatOne:
        return currentIndex.value;
    }
  }

  int _nextShuffleIndex() {
    if (playlist.length == 1) return headOfTheQueue;

    final allPlayed = _shufflePlayed.length >= playlist.length;
    if (allPlayed) {
      _shufflePlayed.clear();
    }

    final candidates = <int>[];
    for (var i = headOfTheQueue; i < playlist.length; i++) {
      if (!_shufflePlayed.contains(playlist[i].id)) {
        candidates.add(i);
      }
    }
    if (candidates.isEmpty) return currentIndex.value;

    final pick = candidates[_rng.nextInt(candidates.length)];
    _shufflePlayed.add(playlist[pick].id);
    return pick;
  }

  Future<void> playSong(Song song) async {
    final idx = playlist.indexWhere((s) => s.id == song.id);
    if (idx >= 0) {
      currentIndex.value = idx;
    } else {
      playlist.add(song);
      currentIndex.value = tailOfTheQueue;
    }
    _resetShuffleRound();
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
        ? headOfTheQueue
        : playlist.indexWhere((song) => song.id == startSong.id);
    currentIndex.value = startIndex >= headOfTheQueue
        ? startIndex
        : headOfTheQueue;
    _resetShuffleRound();
    _persist();
  }

  void removeSong(int index) {
    if (index < headOfTheQueue || index > tailOfTheQueue) return;

    // shuffle 模式下如果删的是已播过的, 同步清掉标记
    if (mode.value == PlayMode.shuffle &&
        _shufflePlayed.contains(playlist[index].id)) {
      _shufflePlayed.remove(playlist[index].id);
    }

    playlist.removeAt(index);

    if (playlist.isEmpty) {
      currentIndex.value = 0;
    } else if (index < currentIndex.value) {
      currentIndex.value -= 1;
    } else if (index == currentIndex.value) {
      if (currentIndex.value >= playlist.length) {
        currentIndex.value = tailOfTheQueue;
      }
    }

    _persist();
  }

  /// shuffle 轮询重置 (queue 替换/清空时由 playSongs 调)
  void _resetShuffleRound() {
    _shufflePlayed.clear();
    if (mode.value == PlayMode.shuffle && playlist.isNotEmpty) {
      _shufflePlayed.add(playlist[currentIndex.value].id);
    }
  }
}
