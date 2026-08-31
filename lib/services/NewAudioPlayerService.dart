import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import '../models/Headers.dart';
import '../models/Song.dart';
import 'LikedService.dart';
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
///   5. 上层 (controller/ui) likedIds 变了 → audioHandler.refreshIsLiked() → 重建 controls
class AudioPlayerService extends GetxController {
  AudioPlayerService();

  final SongRepository _songRepo = Get.find<SongRepository>();
  final LikedService _likedService = Get.find<LikedService>();
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
          AudioPlayerHandler(songRepo: _songRepo, likedService: _likedService),
    );

    // ---- 聚合层:5 个来源 → 1 个 Rx -----------------------------------------
    _stateSub = audioHandler.playbackState.listen(_onPlaybackState);
    _itemSub = audioHandler.mediaItem.listen(_onMediaItem);
    _queueSub = audioHandler.queue.listen(_onQueue);

    // 换歌后刷一次 isLiked (随 mediaItem 流);后续 likedIds 变化靠上层 controller/ui
    // 调 audioHandler.refreshIsLiked() 推送,handler 不订阅 LikedSongsService,
    // wrapper 也不订阅 — 双向耦合的避免,让 liked 状态变化走显式入口。
    audioHandler.mediaItem.listen((_) {
      final song = snapshot.value.currentSong;
      if (song == null) {
        snapshot.value = snapshot.value.copyWith(isLiked: false);
      } else {
        final liked = _likedService.isLiked(song.id, LikedType.song);
        snapshot.value = snapshot.value.copyWith(isLiked: liked);
      }
    });
  }

  @override
  void onClose() {
    _stateSub?.cancel();
    _itemSub?.cancel();
    _queueSub?.cancel();
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
      snapshot.value = snapshot.value.copyWith(
        clearCurrentSong: true,
        currentIndex: -1,
      );
      return;
    }
    final song = _itemToSong(item);
    // queueIndex 由 handler 写在 MediaItem.extras['queueIndex'] 里
    // (避免 wrapper 依赖 _onQueue 和 _onMediaItem 之间的 stream 时序)
    final idx = item.extras?['queueIndex'] as int? ?? -1;
    snapshot.value = snapshot.value.copyWith(
      currentSong: song,
      currentIndex: idx,
    );
  }

  void _onQueue(List<MediaItem> q) {
    snapshot.value = snapshot.value.copyWith(queue: q);
  }

  // 注意:不再单独订阅 handler 的 currentIndex 变化。currentIndex 由 handler
  // 在 emit MediaItem 时通过 extras['queueIndex'] 一并带过来,_onMediaItem
  // 里直接读。这样设计是因为:
  //   1. mediaItem 流已经覆盖了所有 currentIndex 变化的场景 (切歌=mediaItem 变)
  //   2. 单独 addListener 会出现两个 stream 到达 wrapper 的时序不一致风险
  //   3. ValueNotifier 在 handler 不是 GetxController 时确实合规,但没必要
  //      多开一条 channel

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
///   1. 订阅 [_audio] 的 5 个原生 stream,转发给 audio_service 广播:
///        - playerStateStream       → playbackState.add()
///        - currentIndexStream      → mediaItem.add(根据 _queue[index])
///        - durationStream          → mediaItem.add(更新 duration)
///        - positionStream          → playbackState.add(更新 position)
///        - bufferedPositionStream  → playbackState.add(更新 bufferedPosition)
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
  AudioPlayerHandler({required this._songRepo, required this._likedService}) {
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
  final LikedService _likedService;
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

  /// shuffle 反向映射:_shufflePosOfQueueIndex[queueIdx] = shufflePos。
  /// 让 [_neighbor] 在 shuffle 模式下 O(1) 查当前歌的播放顺序位置,
  /// 也让 [removeQueueItemAt] 在 shuffle 模式下做"顺序保持"的稳定删除,
  /// 而不是重洗整个队列 (重洗会让用户在听 shuffle 时删歌后听到不同的歌)。
  /// 非 shuffle 模式时为空 (sequential 不需要反向查)。
  List<int> _shufflePosOfQueueIndex = [];

  /// 当前 MediaItem 缓存 (用于在 stream 回调里判定是否需要重发)
  MediaItem? _lastEmittedItem;

  // 注:不再暴露 currentIndex 字段。wrapper 从 mediaItem.extras['queueIndex']
  // 读取当前索引,handler 在 [_playAt] / [removeQueueItemAt] 等"换索引"的地方
  // 把新索引写进对应 [MediaItem.extras] 并随 [mediaItem.add] emit。

  // ---- 订阅接线 (在构造里跑一次) -------------------------------------------------

  void _wireAudioStreams() {
    // 1. 播放状态 → playbackState
    _audio.playerStateStream.listen((state) {
      // liked 状态查 _likedService.isLiked (实时查,不缓存);
      // liked 变化驱动走 [refreshIsLiked] (上层 controller/ui 调) ,
      // 这里在 playerStateStream 顺带把 controls 同步上,避免切歌后按钮还是老的
      final liked = _likedService.isLiked(
        _lastEmittedItem?.id ?? '',
        LikedType.song,
      );
      playbackState.add(
        playbackState.value.copyWith(
          playing: state.playing,
          processingState: _mapProcessingState(state.processingState),
          controls: _buildControls(isLiked: liked),
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

    // 6. like 状态变化由上层调 [refreshIsLiked] 推送 (handler 不主动 .listen likedIds,避免双向耦合)
  }

  // ---- BaseAudioHandler API override ---------------------------------------------

  Future<void> setQueue(List<MediaItem> newQueue, {int startIndex = 0}) async {
    if (newQueue.isEmpty) {
      _queue = [];
      _shuffleOrder = [];
      _shufflePosOfQueueIndex = [];
      _currentIndex = -1;
      mediaItem.add(null);
      queue.add(const []);
      await _audio.stop();
      return;
    }
    _queue = List.of(newQueue);
    _rebuildShuffleMaps();

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
      _shufflePosOfQueueIndex = [];
      _currentIndex = -1;
      mediaItem.add(null);
      queue.add(const []);
      await _audio.stop();
      return;
    }

    // shuffle 模式下做"稳定删除":保持剩余歌曲在 shuffle 序列中的相对顺序,
    // 而不是每次都重洗 (重洗会让用户听到不同的歌)。
    //   - 正向表 _shuffleOrder: 删掉 _shufflePosOfQueueIndex[index] 那项,后续 -1
    //   - 反向表 _shufflePosOfQueueIndex: index 之后的所有项 -1
    if (_playOrder == PlayOrder.shuffle) {
      _removeFromShuffleMaps(index);
    } else {
      // sequential 模式不用维护反向表;_shuffleOrder 是恒等映射也不需要重生成
    }

    if (wasCurrent) {
      // 移除的是当前:从头开始播 (走 _playAt,会在 extras 写 queueIndex=0)
      _currentIndex = -1;
      await _playAt(0);
    } else {
      // 调整 currentIndex,重发当前 mediaItem (带新 queueIndex)
      if (index < _currentIndex) {
        _currentIndex--;
        _queue[_currentIndex] = _queue[_currentIndex].copyWith(
          extras: {
            ...?_queue[_currentIndex].extras,
            'queueIndex': _currentIndex,
          },
        );
        _lastEmittedItem = _queue[_currentIndex];
        mediaItem.add(_queue[_currentIndex]);
      }
      // 删除后面的歌:_currentIndex 不变,queue 已经更新,wrapper 通过 _onQueue 收新列表
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

  /// 锁屏 like 按钮 → 转发到 LikedSongsService.toggle (由 service 自己做乐观更新 + 错误提示)
  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    if (name != 'toggleLike') return null;
    final cur = _lastEmittedItem;
    if (cur == null) return null;
    // LikedService.toggle 接收 (id, LikedType),内部会触发 likedSongIds 变化,
    // 上层 controller/ui 监听到 likedSongIds 变化后会调 [refreshIsLiked] 推送 controls。
    await _likedService.toggle(cur.id, LikedType.song);
    return null;
  }

  /// like 状态变化推送入口。
  ///
  /// 由上层 controller/ui 监听 LikedSongsService.likedIds 后调用
  /// (而不是 handler 自己 .listen,避免双向耦合)。
  /// 内部重新查 likedIds 重建 playbackState.controls (锁屏 like 按钮 icon/label)。
  Future<void> refreshIsLiked() async {
    final cur = _lastEmittedItem;
    if (cur == null) return;
    final liked = _likedService.isLiked(cur.id, LikedType.song);
    playbackState.add(
      playbackState.value.copyWith(controls: _buildControls(isLiked: liked)),
    );
  }

  // ---- 播放顺序控制 -------------------------------------------------------------

  Future<void> setPlayOrder(PlayOrder order) async {
    if (_playOrder == order) return;
    _playOrder = order;
    // 切模式后重生成 shuffle 表 + 反向表
    _rebuildShuffleMaps();
    // currentIndex 已经是 queue 索引,不需要变
  }

  /// (re)build shuffle 模式下的 _shuffleOrder 和 _shufflePosOfQueueIndex。
  /// - shuffle: 正向洗,反向跟着建
  /// - 其他: 正向恒等,反向留空 (sequential / repeatOne 不查反向)
  void _rebuildShuffleMaps() {
    if (_playOrder == PlayOrder.shuffle) {
      _shuffleOrder = List.generate(_queue.length, (i) => i)..shuffle();
      _shufflePosOfQueueIndex = List.filled(_queue.length, -1);
      for (var pos = 0; pos < _shuffleOrder.length; pos++) {
        _shufflePosOfQueueIndex[_shuffleOrder[pos]] = pos;
      }
    } else {
      _shuffleOrder = List.generate(_queue.length, (i) => i);
      _shufflePosOfQueueIndex = [];
    }
  }

  /// 删 queueIndex=idx 的一首,在 shuffle 模式下做稳定删除。
  ///
  /// 操作:
  ///   1. 在 _shuffleOrder 里 removeAt(pos),其中 pos = _shufflePosOfQueueIndex[idx]
  ///   2. _shuffleOrder 里所有 > idx 的项 (queueIdx > idx 都已 -1) 需要 -1
  ///   3. _shufflePosOfQueueIndex removeAt(idx) (queueIdx 之后整体前移)
  ///   4. _shufflePosOfQueueIndex 里所有指向已删除项的 (越界) 清 -1,
  ///      其余保持原值 (它们的 shufflePos 没变,queueIdx 减了 1 但 pos 还指向同一个 shufflePos)
  ///
  /// 复杂度 O(n) (两表一次扫描),但不需要调 .shuffle(),剩余歌曲在 shuffle
  /// 序列中的相对顺序保持不变。
  void _removeFromShuffleMaps(int idx) {
    if (_shufflePosOfQueueIndex.length != _queue.length + 1) {
      // 防御: 长度对不上 (说明 _queue.removeAt 还没调或别的状态错误),重生成
      _rebuildShuffleMaps();
      return;
    }
    final pos = _shufflePosOfQueueIndex[idx];
    if (pos < 0 || pos >= _shuffleOrder.length) {
      _rebuildShuffleMaps();
      return;
    }
    // 1. 正向表删 pos
    _shuffleOrder.removeAt(pos);
    // 2. 正向表里 > idx 的项减 1 (queue 缩短了 1,这些项对应的 queueIdx 也 -1)
    for (var i = 0; i < _shuffleOrder.length; i++) {
      if (_shuffleOrder[i] > idx) _shuffleOrder[i]--;
    }
    // 3. 反向表删 idx (queueIdx 之后整体前移一格)
    _shufflePosOfQueueIndex.removeAt(idx);
    // 4. 反向表里 > pos 的项保持原值 (它们指向同一个 shufflePos,shuffleOrder 已删除 pos 那项,pos+1 现在在原 pos 位置 ——但 pos 是 shufflePos,反向表存的是 shufflePos,不动)
    //     实际上反向表里存的是 "queueIdx → shufflePos",queueIdx 删除后,后续 queueIdx -1 了,但 shufflePos 没变。
    //     反向表下标已经代表"新的 queueIdx" (第 3 步 removeAt(idx) 后),所以原 queueIdx K (K>idx) 现在在下标 K-1。
    //     它存的 shufflePos 还指向原 shufflePos,shuffleOrder 里那个 shufflePos 还在 (步骤 1 没动它,只删了 pos 那项) → OK 不需要改
  }

  // ---- 内部:播放/索引计算 -------------------------------------------------------

  /// 播放 [queueIndex] 对应的歌。会先把 extras.url 拉出来 setUrl,并把 queueIndex
  /// 也写进 extras (wrapper 从 mediaItem 流读 currentIndex 用)。
  Future<void> _playAt(int queueIndex) async {
    if (queueIndex < 0 || queueIndex >= _queue.length) return;
    _currentIndex = queueIndex;

    // 准备 URL:从 repo 拉真实 url,写到 MediaItem.extras 里
    final url = await _songRepo.fetchSongUrl(_queue[queueIndex].id);
    if (url == null) return; // 取不到 URL 直接放弃 (上层 snackbar 另说)
    _queue[queueIndex] = _queue[queueIndex].copyWith(
      extras: {
        ...?_queue[queueIndex].extras,
        'url': url,
        'queueIndex': queueIndex,
      },
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
        if (_shufflePosOfQueueIndex.isEmpty ||
            _shufflePosOfQueueIndex.length != n) {
          // 防御: 反向表长度对不上就重建
          _rebuildShuffleMaps();
        }
        final pos =
            _currentIndex >= 0 && _currentIndex < _shufflePosOfQueueIndex.length
            ? _shufflePosOfQueueIndex[_currentIndex]
            : -1;
        if (pos < 0) {
          // 当前不在序列里 (队列刚改),重洗后从当前开始
          _rebuildShuffleMaps();
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
