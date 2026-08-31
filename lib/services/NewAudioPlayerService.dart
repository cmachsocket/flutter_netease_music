import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_netease_music/services/repositories/liked_repository.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import '../models/Headers.dart';
import '../models/Song.dart';
import 'LikedSongsService.dart';
import 'repositories/song_repository.dart';

/// 播放顺序。影响 [AudioPlayerHandler._playOrder] 的索引推进策略。
enum PlayOrder { sequential, shuffle, repeatOne }

/// ---- 顶层包装层暴露给 UI 的快照 ------------------------------------------------

/// 播放状态快照。包装器把 [PlaybackState] + 业务上下文聚合成一份给 UI 订阅。
class PlaybackSnapshot {
  const PlaybackSnapshot({
    required this.isPlaying,
    required this.processingState,
    required this.position,
    required this.bufferedPosition,
    required this.currentSong,
    required this.queue,
    required this.currentIndex,
    required this.playOrder,
    required this.isLiked,
  });

  final bool isPlaying;
  final ProcessingState processingState;
  final Duration position;
  final Duration bufferedPosition;

  final Song? currentSong;

  /// 完整队列（UI 用），长度 = 内部 [_AudioPlayerHandler._queue].length
  final List<MediaItem> queue;

  /// 在 [queue] 里的索引；-1 = 没有当前播放
  final int currentIndex;

  final PlayOrder playOrder;
  final bool isLiked;

  PlaybackSnapshot copyWith({
    bool? isPlaying,
    ProcessingState? processingState,
    Duration? position,
    Duration? bufferedPosition,
    Song? currentSong,
    bool clearCurrentSong = false,
    List<MediaItem>? queue,
    int? currentIndex,
    PlayOrder? playOrder,
    bool? isLiked,
  }) {
    return PlaybackSnapshot(
      isPlaying: isPlaying ?? this.isPlaying,
      processingState: processingState ?? this.processingState,
      position: position ?? this.position,
      bufferedPosition: bufferedPosition ?? this.bufferedPosition,
      currentSong: clearCurrentSong ? null : (currentSong ?? this.currentSong),
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      playOrder: playOrder ?? this.playOrder,
      isLiked: isLiked ?? this.isLiked,
    );
  }
}

/// ---- 顶层包装层 ----------------------------------------------------------------
///
/// 把 [AudioPlayerHandler] 提供的 audio_service 事件流 (playbackState / mediaItem /
/// queue) 翻译成 [PlaybackSnapshot],并把 UI 命令 (play/pause/seek/skip/setQueue/
/// setPlayOrder) 转发到底层。
///
/// 唯一可变状态: [snapshot] (`Rx<PlaybackSnapshot>`),由 5 个来源聚合而成:
///   1. handler.playbackState  → isPlaying / processingState / position / bufferedPosition
///   2. handler.mediaItem       → currentSong (Song)
///   3. handler.queue           → queue
///   4. handler.currentIndex    → currentIndex
///   5. LikedSongsService 订阅  → isLiked
class AudioPlayerService extends GetxController {
  AudioPlayerService();

  final SongRepository _songRepo = Get.find<SongRepository>();
  final LikedRepository _likedRepo = Get.find<LikedRepository>();
  late final AudioPlayerHandler audioHandler;

  /// UI 唯一订阅点。任何播放相关变化都聚合到这一个 Rx。
  final Rx<PlaybackSnapshot> snapshot = Rx<PlaybackSnapshot>(
    PlaybackSnapshot(
      isPlaying: false,
      processingState: ProcessingState.idle,
      position: Duration.zero,
      bufferedPosition: Duration.zero,
      currentSong: null,
      queue: const [],
      currentIndex: -1,
      playOrder: PlayOrder.sequential,
      isLiked: false,
    ),
  );

  StreamSubscription<PlaybackState>? _stateSub;
  StreamSubscription<MediaItem?>? _itemSub;
  StreamSubscription<List<MediaItem>>? _queueSub;

  @override
  Future<void> onInit() async {
    super.onInit();

    // MediaKit init 是同步阻塞,在 onInit 里完成。
    // 后续 setUrl/play 直接用,不需要再 await ready(竞态源)。
    JustAudioMediaKit.ensureInitialized();

    audioHandler = await AudioService.init(
      builder: () =>
          AudioPlayerHandler(songRepo: _songRepo, likedRepo: _likedRepo),
    );

    // ---- 聚合层:5 个来源 → 1 个 Rx -----------------------------------------
    _stateSub = audioHandler.playbackState.listen(_onPlaybackState);
    _itemSub = audioHandler.mediaItem.listen(_onMediaItem);
    _queueSub = audioHandler.queue.listen(_onQueue);

    // currentIndex 由 handler 自己维护,直接同步
    audioHandler.currentIndex.addListener(_syncCurrentIndex);

    // isLiked 跟 currentSong 一起算
    Get.find<LikedSongsService>().likedIds.listen((_) => _refreshIsLiked());
    // 换歌也刷一次 isLiked
    audioHandler.mediaItem.listen((_) => _refreshIsLiked());
  }

  @override
  void onClose() {
    _stateSub?.cancel();
    _itemSub?.cancel();
    _queueSub?.cancel();
    audioHandler.currentIndex.removeListener(_syncCurrentIndex);
    audioHandler.stop();
    super.onClose();
  }

  // ---- 聚合回调 -----------------------------------------------------------------

  void _onPlaybackState(PlaybackState s) {
    snapshot.value = snapshot.value.copyWith(
      isPlaying: s.playing,
      processingState: _toJustAudioProcessing(s.processingState),
      position: s.position,
      bufferedPosition: s.bufferedPosition,
    );
  }

  void _onMediaItem(MediaItem? item) {
    if (item == null) {
      snapshot.value = snapshot.value.copyWith(clearCurrentSong: true);
      return;
    }
    final song = _itemToSong(item);
    snapshot.value = snapshot.value.copyWith(currentSong: song);
  }

  void _onQueue(List<MediaItem> q) {
    snapshot.value = snapshot.value.copyWith(queue: q);
  }

  void _refreshIsLiked() {
    final song = snapshot.value.currentSong;
    if (song == null) {
      snapshot.value = snapshot.value.copyWith(isLiked: false);
      return;
    }
    final liked = Get.find<LikedSongsService>().likedIds.contains(song.id);
    snapshot.value = snapshot.value.copyWith(isLiked: liked);
  }

  /// 把 handler 的 currentIndex 变化合并到 snapshot。
  /// 用 ChangeNotifier.addListener 而不是 RxInt.listen,因为 handler 不是 GetxController。
  void _syncCurrentIndex() {
    snapshot.value = snapshot.value.copyWith(
      currentIndex: audioHandler.currentIndex.value,
    );
  }

  // ---- UI 转发到 handler ---------------------------------------------------------

  Future<void> play() => audioHandler.play();
  Future<void> pause() => audioHandler.pause();
  Future<void> stop() => audioHandler.stop();
  Future<void> seek(Duration position) => audioHandler.seek(position);
  Future<void> skipToNext() => audioHandler.skipToNext();
  Future<void> skipToPrevious() => audioHandler.skipToPrevious();
  Future<void> skipToQueueItem(int index) =>
      audioHandler.skipToQueueItem(index);

  /// 替换整个队列。传入 Song 列表,内部翻成 MediaItem 并刷新 shuffle 映射。
  Future<void> setQueue(List<Song> songs, {int startIndex = 0}) {
    final items = songs
        .map(
          (s) => s.toMediaItem(
            artHeaders: NeteaseImageHeaders.neteaseImageHeaders,
          ),
        )
        .toList();
    return audioHandler.setQueue(items, startIndex: startIndex);
  }

  /// 切歌。
  Future<void> playSong(Song song, {List<Song>? surrounding}) async {
    if (surrounding != null && surrounding.isNotEmpty) {
      final idx = surrounding.indexWhere((s) => s.id == song.id);
      await setQueue(surrounding, startIndex: idx >= 0 ? idx : 0);
      return;
    }
    // 单曲:放进长度为 1 的队列,handler 会 fetch URL
    await setQueue([song], startIndex: 0);
  }

  Future<void> setPlayOrder(PlayOrder order) =>
      audioHandler.setPlayOrder(order);

  // ---- helpers -----------------------------------------------------------------

  ProcessingState _toJustAudioProcessing(AudioProcessingState s) {
    switch (s) {
      case AudioProcessingState.idle:
        return ProcessingState.idle;
      case AudioProcessingState.loading:
        return ProcessingState.loading;
      case AudioProcessingState.buffering:
        return ProcessingState.buffering;
      case AudioProcessingState.ready:
        return ProcessingState.ready;
      case AudioProcessingState.completed:
        return ProcessingState.completed;
      case AudioProcessingState.error:
        return ProcessingState.idle; // just_audio 没有 error 状态,降级
    }
  }

  /// MediaItem → Song (用于 UI 显示)
  /// MediaItem 里的 id 存的是 Song.id (String);
  /// 其他字段直接从 MediaItem.title/artist/album/artUri 翻
  Song _itemToSong(MediaItem item) {
    return Song(
      id: item.id,
      title: item.title,
      artist: item.artist ?? '',
      album: item.album ?? '',
      coverUrl: item.artUri?.toString() ?? '',
      duration: item.duration ?? Duration.zero,
    );
  }
}

/// ---- 后台播放 handler (audio_service + just_audio 桥接) ------------------------
///
/// 职责:
///
///   1. 订阅 [_audio] 的 4 个原生 stream,转发给 audio_service 广播:
///        - playerStateStream       → playbackState.add()
///        - currentIndexStream      → mediaItem.add(根据 _queue[index])
///        - durationStream          → mediaItem.add(更新 duration)
///        - positionStream          → playbackState.add(更新 position)
///   2. 接收 audio_service 系统控制 (play/pause/seek/skip/customAction)
///      并翻译成 just_audio 操作
///   3. 维护 *唯一* 的可变状态: [_queue] / [_currentIndex] / [_playOrder] / [_shuffleOrder]
///   shuffle 模式下 [_shuffleOrder] 是 _queue 的随机排列,_currentIndex 始终是 _queue 索引
///
/// 设计原则:
///
///   - **不持有派生状态**: isLiked / currentSong 都不在这里存,由上层包装器从 stream 聚合
///   - **不双写**: queue / playbackState / mediaItem 都是 _audio 的派生态,不手动管理
///   - **shuffle 用映射表**: shuffleMap[playOrderIndex] = queueIndex,currentIndex 始终指
///     播放顺序的位置,内部翻成 queue 索引去读 _queue
class AudioPlayerHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  AudioPlayerHandler({required this._songRepo, required this._likedRepo}) {
    // 初始 state: 启用 seek 系列系统手势 + 三按钮基础控件
    playbackState.add(
      playbackState.value.copyWith(
        controls: _baseControls,
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
      ),
    );
    _wireAudioStreams();
  }

  // ---- 依赖 ---------------------------------------------------------------------

  final SongRepository _songRepo;
  final LikedRepository _likedRepo;
  final AudioPlayer _audio = AudioPlayer();

  // ---- 唯一可变状态 -------------------------------------------------------------

  /// 逻辑队列 (UI 显示顺序)。
  /// 当前架构下 just_audio 用 setUrl() 单曲驱动，不维护自己的 playlist。
  /// 所以 [_currentIndex] 始终是 _queue 里的索引，shuffle 由 [_shuffleOrder]
  /// (一个 _queue.length 的随机排列) 控制。
  List<MediaItem> _queue = [];
  int _currentIndex = -1;
  PlayOrder _playOrder = PlayOrder.sequential;

  /// shuffle 顺序:第 i 个要播的是 _queue[_shuffleOrder[i]]。
  /// 非 shuffle 模式时 = [_queue] 的恒等排列 (List.generate(i, i))。
  List<int> _shuffleOrder = [];

  /// 当前 MediaItem 缓存 (用于在 stream 回调里判定是否需要重发)
  MediaItem? _lastEmittedItem;

  /// 给上层包装器订阅的 currentIndex 变化。
  ///
  /// 不用 GetX 的 RxInt —— handler 不是 GetxController,GetX 的生命周期管理
  /// (依赖追踪 / Get.find) 不会作用在这里; 改用 Flutter 自带的 [ValueNotifier],
  /// 上层用 [ValueNotifier.addListener] 同步通知。
  final ValueNotifier<int> currentIndex = ValueNotifier<int>(-1);

  // ---- 订阅接线 (在构造里跑一次) -------------------------------------------------

  void _wireAudioStreams() {
    // 1. 播放状态 → playbackState
    _audio.playerStateStream.listen((state) {
      playbackState.add(
        playbackState.value.copyWith(
          playing: state.playing,
          processingState: _mapProcessingState(state.processingState),
          controls: _buildControls(isLiked: _resolveIsLiked()),
          speed: 1.0,
        ),
      );
    });

    // 2. 当前索引 → mediaItem
    // 注意: setUrl() 模式下 just_audio.currentIndexStream 永远 = 0
    // 所以这里 *不* 用 currentIndexStream 做真相,_currentIndex 由 _playAt() 显式更新
    // currentIndexStream 只用来 *检测* skipToNext() 这类操作是否被 just_audio 内部消化
    // (供调试/扩展用,这里不依赖它)
    _audio.currentIndexStream.listen((_) {});

    // 3. 时长变化 → 更新当前 MediaItem 的 duration
    _audio.durationStream.listen((dur) {
      if (dur == null) return;
      final item = _lastEmittedItem;
      if (item == null) return;
      final updated = item.copyWith(duration: dur);
      if (updated == item) return; // 没变就别 add (避免无效广播)
      _lastEmittedItem = updated;
      // 同步更新 _queue 里这份 (媒体时长是只读属性,放 extras 也行,这里直接改 MediaItem)
      _queue[_currentIndex] = updated;
      mediaItem.add(updated);
    });

    // 4. 位置流 → playbackState (audio_service 锁屏进度条需要)
    _audio.positionStream.listen((pos) {
      playbackState.add(playbackState.value.copyWith(updatePosition: pos));
    });

    // 5. 缓冲位置
    _audio.bufferedPositionStream.listen((buf) {
      playbackState.add(playbackState.value.copyWith(bufferedPosition: buf));
    });

    // 6. like 状态变化 (锁屏 like 按钮) → 重建 controls
    Get.find<LikedSongsService>().likedIds.listen((_) {
      playbackState.add(
        playbackState.value.copyWith(
          controls: _buildControls(isLiked: _resolveIsLiked()),
        ),
      );
    });
  }

  // ---- BaseAudioHandler API override ---------------------------------------------

  Future<void> setQueue(List<MediaItem> newQueue, {int startIndex = 0}) async {
    if (newQueue.isEmpty) {
      _queue = [];
      _shuffleOrder = [];
      _currentIndex = -1;
      currentIndex.value = -1;
      mediaItem.add(null);
      queue.add(const []);
      await _audio.stop();
      return;
    }
    _queue = List.of(newQueue);

    // shuffle 模式:重洗映射表,保证 startIndex 落在 _shuffleOrder[0] 上
    if (_playOrder == PlayOrder.shuffle) {
      _shuffleOrder = List.generate(_queue.length, (i) => i)..shuffle();
    } else {
      _shuffleOrder = List.generate(_queue.length, (i) => i);
    }

    final clampedStart = startIndex.clamp(0, _queue.length - 1);
    await _playAt(clampedStart);
    await super.updateQueue(List.unmodifiable(_queue));
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (_queue.isEmpty) return;
    if (index < 0 || index >= _queue.length) return;
    await _playAt(index);
  }

  @override
  Future<void> skipToNext() async {
    if (_queue.isEmpty) return;
    final next = _neighbor(1);
    if (next < 0) return;
    await _playAt(next);
  }

  @override
  Future<void> skipToPrevious() async {
    if (_queue.isEmpty) return;
    final prev = _neighbor(-1);
    if (prev < 0) return;
    await _playAt(prev);
  }

  @override
  Future<void> removeQueueItemAt(int index) async {
    if (_queue.isEmpty) return;
    if (index < 0 || index >= _queue.length) return;

    final wasCurrent = index == _currentIndex;
    _queue.removeAt(index);
    if (_queue.isEmpty) {
      _shuffleOrder = [];
      _currentIndex = -1;
      currentIndex.value = -1;
      mediaItem.add(null);
      queue.add(const []);
      await _audio.stop();
      return;
    }

    // shuffle 模式:重洗映射
    if (_playOrder == PlayOrder.shuffle) {
      _shuffleOrder = List.generate(_queue.length, (i) => i)..shuffle();
    } else {
      _shuffleOrder = List.generate(_queue.length, (i) => i);
    }

    if (wasCurrent) {
      // 移除的是当前:从头开始播
      _currentIndex = -1;
      currentIndex.value = -1;
      await _playAt(0);
    } else {
      // 调整 currentIndex
      if (index < _currentIndex) {
        _currentIndex--;
        currentIndex.value = _currentIndex;
      }
      mediaItem.add(_currentIndex >= 0 ? _queue[_currentIndex] : null);
    }
    await super.updateQueue(List.unmodifiable(_queue));
  }

  @override
  Future<void> updateQueue(List<MediaItem> queue) async {
    // 系统/外部调用 (锁屏 widget 拖队列等) 会走这里
    // 我们信任 caller,直接接管
    await setQueue(queue, startIndex: _currentIndex.clamp(0, queue.length - 1));
  }

  // ---- just_audio 桥接 ----------------------------------------------------------

  @override
  Future<void> prepareFromUri(Uri uri, [Map<String, dynamic>? extras]) async {
    await _audio.setUrl(uri.toString());
  }

  @override
  Future<void> play() => _audio.play();

  @override
  Future<void> pause() => _audio.pause();

  @override
  Future<void> stop() async {
    await _audio.stop();
  }

  @override
  Future<void> seek(Duration position) => _audio.seek(position);

  /// 锁屏 like 按钮 → 转发到 LikedSongsService
  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    if (name != 'toggleLike') return null;
    final cur = _lastEmittedItem;
    if (cur == null) return null;
    // LikedSongsService.toggle 接收 String id
    await Get.find<LikedSongsService>().toggle(cur.id);
    return null;
  }

  // ---- 播放顺序控制 -------------------------------------------------------------

  Future<void> setPlayOrder(PlayOrder order) async {
    if (_playOrder == order) return;
    _playOrder = order;

    if (order == PlayOrder.shuffle) {
      _shuffleOrder = List.generate(_queue.length, (i) => i)..shuffle();
    } else {
      // 切回 sequential / repeatOne:把 shuffleMap 还原成恒等映射
      _shuffleOrder = List.generate(_queue.length, (i) => i);
    }
    // currentIndex 已经是 queue 索引,不需要变
  }

  // ---- 内部:播放/索引计算 -------------------------------------------------------

  /// 播放 [queueIndex] 对应的歌。会先把 extras.url 拉出来 setUrl。
  Future<void> _playAt(int queueIndex) async {
    if (queueIndex < 0 || queueIndex >= _queue.length) return;
    _currentIndex = queueIndex;
    currentIndex.value = queueIndex;

    // 准备 URL:从 repo 拉真实 url,写到 MediaItem.extras 里
    final url = await _songRepo.fetchSongUrl(_queue[queueIndex].id);
    if (url == null) return; // 取不到 URL 直接放弃 (上层 snackbar 另说)
    _queue[queueIndex] = _queue[queueIndex].copyWith(
      extras: {...?_queue[queueIndex].extras, 'url': url},
    );

    await _audio.setUrl(url);
    _lastEmittedItem = _queue[queueIndex];
    mediaItem.add(_queue[queueIndex]);

    // repeatOne 不需要重新 prepare;sequential/shuffle 已经在 setUrl 后 just_audio
    // 会自动从 0 开始播,这里主动 play() 保证立即开始
    if (_playOrder != PlayOrder.repeatOne) {
      await _audio.play();
    } else {
      // repeatOne 但不是同一首 (从外部点过来的):重新 prepare 然后播
      await _audio.play();
    }
  }

  /// 计算下一个/上一个 [_queue] 索引。
  ///
  /// - repeatOne: 不变 (同首)
  /// - sequential: [_currentIndex] ± 1, 头尾循环
  /// - shuffle:    在 [_shuffleOrder] 序列里往后/前走一步
  ///              (先找到当前在序列中的位置 pos, 取 _shuffleOrder[(pos + delta + n) % n])
  int _neighbor(int delta) {
    if (_queue.isEmpty) return -1;
    final n = _queue.length;
    switch (_playOrder) {
      case PlayOrder.repeatOne:
        return _currentIndex;
      case PlayOrder.sequential:
        return (_currentIndex + delta + n) % n;
      case PlayOrder.shuffle:
        if (_shuffleOrder.isEmpty || _shuffleOrder.length != n) {
          // 防御: 序列长度不一致就重建
          _shuffleOrder = List.generate(n, (i) => i)..shuffle();
        }
        final pos = _shuffleOrder.indexOf(_currentIndex);
        if (pos < 0) {
          // 当前不在序列里 (队列刚改),重洗后从当前开始
          _shuffleOrder = List.generate(n, (i) => i)..shuffle();
          return _currentIndex;
        }
        final nextPos = (pos + delta + n) % n;
        return _shuffleOrder[nextPos];
    }
  }

  // ---- 锁屏 controls 构造 -------------------------------------------------------

  /// 三按钮基础 controls (不含 like)。like 按钮由 [_buildControls] 根据 isLiked 拼上。
  List<MediaControl> get _baseControls => const [
    MediaControl.skipToPrevious,
    MediaControl.play,
    MediaControl.skipToNext,
  ];

  List<MediaControl> _buildControls({required bool isLiked}) {
    final playing = playbackState.value.playing;
    return [
      MediaControl.skipToPrevious,
      if (playing) MediaControl.pause else MediaControl.play,
      MediaControl.skipToNext,
      MediaControl(
        action: MediaAction.custom,
        label: isLiked ? '取消喜欢' : '喜欢',
        androidIcon: isLiked
            ? 'drawable/ic_favorite'
            : 'drawable/raw_favorite_border',
        customAction: const CustomMediaAction(name: 'toggleLike'),
      ),
    ];
  }

  bool _resolveIsLiked() {
    final cur = _lastEmittedItem;
    if (cur == null) return false;
    return Get.find<LikedSongsService>().likedIds.contains(cur.id);
  }

  AudioProcessingState _mapProcessingState(ProcessingState s) {
    switch (s) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }
}
