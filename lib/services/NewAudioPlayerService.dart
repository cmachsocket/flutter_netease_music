import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import '../models/Headers.dart';
import '../models/Song.dart';
import 'LikedService.dart';
import 'repositories/lyrics_repository.dart';
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
    required this.isCurrentSongLiked,
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
  final bool isCurrentSongLiked;

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
    bool? isCurrentSongLiked,
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
      isCurrentSongLiked: isCurrentSongLiked ?? this.isCurrentSongLiked,
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
///   5. handler.currentSongLiked 流 (`Stream<bool>`) → isCurrentSongLiked
///      (handler 内部 listen likedSongIds.stream + 在 _playAt emit,
///      主动推 bool 给 wrapper,wrapper 不需要查 _likedService)
class AudioPlayerService extends GetxController {
  AudioPlayerService();

  final SongRepository _songRepo = Get.find<SongRepository>();
  final LikedService _likedService = Get.find<LikedService>();
  final LyricsRepository _lyricsRepo = Get.find<LyricsRepository>();
  late final AudioPlayerHandler audioHandler;

  // ---- 业务层 Rx 集合 (跟 UI / 上层 controller 交互用) ------------------------

  /// 业务层队列 (Song 列表) — 与 handler 内部 [_queue] (MediaItem) 对应,
  /// 由 [_onQueue] / [setQueue] 双向同步。UI / controller 走 [playlist] 拿 Song,
  /// handler 走 [snapshot.queue] (MediaItem) 走 audio_service。
  final RxList<Song> playlist = <Song>[].obs;


  // 持久化 (从老的 PlayQueueService 迁来)
  static const _storageKey = 'playlist_v1';
  static const _currentIndexKey = 'playlist_currentIndex_v1';
  static const _modeKey = 'playlist_mode_v1';

  int get headOfTheQueue => 0;
  int get tailOfTheQueue => playlist.length - 1;

  /// UI 订阅的 [currentIndex] (从 snapshot 读)。 走 wrapper 而不是 [snapshot.currentIndex]
  /// 是为了跟其他 Rx (playlist) 同步变化触发 Obx 刷新。
  RxInt get currentIndex => _currentIndexSub;
  final RxInt _currentIndexSub = (-1).obs;

  /// 播放顺序 (从 snapshot 读)
  Rx<PlayOrder> get mode => _modeRx;
  final Rx<PlayOrder> _modeRx = PlayOrder.sequential.obs;

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
      isCurrentSongLiked: false,
    ),
  );

  StreamSubscription<PlaybackState>? _stateSub;
  StreamSubscription<MediaItem?>? _itemSub;
  StreamSubscription<List<MediaItem>>? _queueSub;
  StreamSubscription<bool>? _currentSongLikedSub;
  StreamSubscription<PlayOrder>? _playOrderSub;

  // 不 override onInit: GetX 的 _onStart 同步调用 onInit() 并丢弃 future
  // (见 package:get/get_instance/src/lifecycle.dart _onStart):
  //   void _onStart() {
  //     if (_initialized) return;
  //     onInit();           // 同步调用,future 被丢弃
  //     _initialized = true;
  //   }
  // 所以 onInit 不能放 await 链 (AudioService.init / handler 异步构造等),
  // 否则 handler 还没就绪 PlayerController.onInit 已经跑完, 会出现
  // wrapper.audioHandler (late) 还未赋值就被访问的崩溃。
  //
  // 异步初始化挪到下面的 [init] 方法, 由 main.dart 用 `Get.putAsync` 在
  // builder 内 `await wrapper.init()` (跟 AuthController 同模式)。
  // putAsync 会 await builder() 整链, 等 handler + 5 路 stream 就绪
  // 再返回 instance, 之后 put PlayerController / LyricsController 时
  // wrapper.audioHandler (late) 已赋值。

  /// 异步初始化: 启动 MediaKit + 读持久化 + 构造 handler + 订阅 5 路 stream
  ///
  /// **必须由 main.dart 通过 `Get.putAsync` builder 内 `await init()` 调用**,
  /// 不能 override `onInit`(GetX 同步调用 + 丢 future), 也不能 `Get.put`
  /// 后再 await init() (留"已注册未初始化"中间态, 后续 Get.find 会拿到
  /// 未就绪的 wrapper)。见上面注释里 `_onStart` 的引用。
  Future<void> init() async {
    // MediaKit init 是同步阻塞,在 init() 里完成。
    // 后续 setUrl/play 直接用,不需要再 await ready(竞态源)。
    JustAudioMediaKit.ensureInitialized();

    // ---- 持久化恢复: 在 handler 构造前同步读 GetStorage, 把真相状态
    // (queue / currentIndex / mode) 作为 handler 的初始值传入。
    // handler 用 BehaviorSubject 在构造时 emit, wrapper 订阅后自动回放,
    // 不再由 wrapper 的 Rx 手动 hydrate (避免 UI 恢复了而 handler 为空)。
    final box = GetStorage();
    final rawQueue = box.read<List>(_storageKey);
    final savedIdx = box.read<int>(_currentIndexKey) ?? -1;
    final savedMode = _decodeMode(box.read<String>(_modeKey));

    final initialItems = <MediaItem>[
      for (final e in rawQueue ?? const [])
        if (e is Map)
          Song.fromJson(Map<String, dynamic>.from(e)).toMediaItem(
            artHeaders: NeteaseImageHeaders.neteaseImageHeaders,
            // 传 Song.duration → MediaItem.duration → wrapper._itemToSong 时
            // 还能正确还原 Song.duration (不然恢复后 playlist[i].duration == 0,
            // UI 进度条 / 队列列表显示 0:00)
            duration: Duration(seconds: (e['duration'] as int?) ?? 0),
          ),
    ];
    final initialIndex = (savedIdx >= 0 && savedIdx < initialItems.length)
        ? savedIdx
        : (initialItems.isEmpty ? -1 : 0);

    audioHandler = await AudioService.init(
      builder: () => AudioPlayerHandler(
        songRepo: _songRepo,
        likedService: _likedService,
        initialQueue: initialItems,
        initialIndex: initialIndex,
        initialMode: savedMode,
      ),
    );

    // mode 不需要在 wrapper 这里手动 hydrate: handler 构造时已经把
    // initialMode 写进 _playOrder 字段,并在构造尾部 emit 一次到
    // _playOrderCtrl 流, 下面订阅就会拿到 → _modeRx 自动同步。
    // (handler 是 mode 唯一真相源, wrapper 只读不写, 单向流)

    // ---- 聚合层:5 个来源 → 1 个 Rx -----------------------------------------
    _stateSub = audioHandler.playbackState.listen(_onPlaybackState);
    _itemSub = audioHandler.mediaItem.listen(_onMediaItem);
    _queueSub = audioHandler.queue.listen(_onQueue);

    // 订阅 handler 推的 currentSongLiked 流 → snapshot.isCurrentSongLiked
    // (handler 内部处理 likedSongIds 变化 + 换歌两种触发, 主动 emit bool,
    // 不用 wrapper 自己查 _likedService.likedSongIds)
    _currentSongLikedSub = audioHandler.currentSongLiked.listen((liked) {
      snapshot.value = snapshot.value.copyWith(isCurrentSongLiked: liked);
    });
    // broadcast 无 replay: 订阅后主动刷一次,避免订阅前 handler 已 emit 过
    // 导致 wrapper 的 isCurrentSongLiked 停在初始 false
    audioHandler.refreshCurrentSongLiked();

    // 订阅 handler 推的 playOrder 流 → _modeRx (handler 内部改 _playOrder
    // 后主动 emit, wrapper 只读不写, 单向流)
    _playOrderSub = audioHandler.playOrder.listen((order) {
      _modeRx.value = order;
    });
    // broadcast 无 replay: 兜底刷一次 (handler 构造时已 emit 初始值, 但
    // 如果 init() 跑在 handler 构造**之前** (本次不会,但兜底), 订阅就会
    // 漏掉初始 emit)
    audioHandler.refreshPlayOrder();
  }

  @override
  void onClose() {
    _stateSub?.cancel();
    _itemSub?.cancel();
    _queueSub?.cancel();
    _currentSongLikedSub?.cancel();
    _playOrderSub?.cancel();
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
      _currentIndexSub.value = -1;
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
    // 业务层 currentIndex 同步
    _currentIndexSub.value = idx;
  }

  void _onQueue(List<MediaItem> q) {
    snapshot.value = snapshot.value.copyWith(queue: q);
    // 业务层同步:MediaItem 列表 → Song 列表
    playlist.assignAll(q.map(_itemToSong));
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
  ///
  /// `duration: s.duration` 一起传入 MediaItem —— wrapper._itemToSong 翻译
  /// 时会取回 Song.duration,这样 `playlist[i].duration` 在切歌前就有合理值
  /// (否则 UI 进度条 / 队列列表里非当前歌曲显示 0:00)。
  /// handler `_playAt` 后 just_audio durationStream 会 emit 真值,handler
  /// 再用 `item.copyWith(duration: dur)` 覆盖一次(更准)。
  Future<void> setQueue(List<Song> songs, {int startIndex = 0}) {
    final items = songs
        .map(
          (s) => s.toMediaItem(
            artHeaders: NeteaseImageHeaders.neteaseImageHeaders,
            duration: s.duration,
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

  Future<void> setPlayOrder(PlayOrder order) {
    // 纯 forward: handler 改完 _playOrder 后 emit 到 _playOrderCtrl 流,
    // wrapper 那边订阅回调自动写 _modeRx (handler 是唯一真相源)。
    // wrapper 这里不写任何 Rx — 严格单向流。
    return audioHandler.setPlayOrder(order);
  }

  // ---- 歌词 (转发到 LyricsRepository) -----------------------------------------

  /// 拉取 songId 的歌词 (按 songId 缓存)。LyricsService 删了,走这里。
  Future<String?> fetchLyric(String songId) => _lyricsRepo.fetch(songId);

  /// 清歌词缓存 (用户手动刷新时调)。
  void invalidateLyric([String? songId]) => _lyricsRepo.invalidate(songId);

  // ---- 队列/模式业务 API (从老 PlayQueueService 迁来) -------------------------

  /// 选某一首开始播放 (UI 点队列里的某一首)
  void selectIndex(int index) {
    if (index < 0 || index >= playlist.length) return;
    // 不手动写 _currentIndexSub: handler skipToQueueItem → _playAt →
    // mediaItem.add 会回推 _onMediaItem,由它更新 (单向流,消除双写竞态)
    audioHandler.skipToQueueItem(index);
    _persist();
  }

  /// 计算"下一首要播的索引"(不修改 currentIndex)
  int nextIndex() {
    if (playlist.isEmpty) return -1;
    switch (mode.value) {
      case PlayOrder.sequential:
        return (_currentIndexSub.value + 1) % playlist.length;
      case PlayOrder.shuffle:
        return audioHandler.peekNeighbor(1);
      case PlayOrder.repeatOne:
        return _currentIndexSub.value;
    }
  }

  /// 计算"上一首要播的索引"(不修改 currentIndex)
  int prevIndex() {
    if (playlist.isEmpty) return -1;
    switch (mode.value) {
      case PlayOrder.sequential:
        final p = _currentIndexSub.value - 1;
        return p < headOfTheQueue ? tailOfTheQueue : p;
      case PlayOrder.shuffle:
        return audioHandler.peekNeighbor(-1);
      case PlayOrder.repeatOne:
        return _currentIndexSub.value;
    }
  }

  /// 队列里删一首 (UI 调)
  void removeSong(int index) {
    if (index < headOfTheQueue || index > tailOfTheQueue) return;
    // 不写 playlist: handler 的 removeQueueItemAt 会更新 _queue 并通过
    // queue/mediaItem 流回推 _onQueue/_onMediaItem (彻底单向化)
    audioHandler.removeQueueItemAt(index);
    _persist();
  }

  /// 加载多首歌作为整个队列(UI 调, 比如歌单页"播放全部")
  ///
  /// 返回 [Future<void>] 让上层 controller 可以 await (e.g.
  /// `SongListController.playPlaylistById` 等首屏数据 load 完再触发)。
  Future<void> playSongs(List<Song> songs, {Song? startSong}) async {
    if (songs.isEmpty) return;
    final uniqueSongs = <Song>[];
    final seenIds = <String>{};
    for (final song in songs) {
      if (seenIds.add(song.id)) uniqueSongs.add(song);
    }
    // 不写 playlist / _currentIndexSub: 直接喂 handler, 由 queue/mediaItem
    // 流回推 _onQueue/_onMediaItem 同步 (单向流)
    final startIndex = startSong == null
        ? 0
        : uniqueSongs.indexWhere((s) => s.id == startSong.id);
    final finalStart = startIndex >= 0 ? startIndex : 0;
    await audioHandler.setQueue(
      uniqueSongs
          .map(
            (s) => s.toMediaItem(
              artHeaders: NeteaseImageHeaders.neteaseImageHeaders,
              duration: s.duration,
            ),
          )
          .toList(),
      startIndex: finalStart,
    );
    _persist();
  }

  // ---- 持久化 (从老 PlayQueueService 迁来) ------------------------------------

  void _persist() {
    final box = GetStorage();
    // 全部读 handler 真相: 队列 / currentIndex / mode 都从 handler 取,
    // wrapper 的 Rx 只作展示层, 不参与持久化 (彻底单向化)
    box.write(
      _storageKey,
      audioHandler.persistedQueue
          .map(_itemToSong)
          .map((s) => s.toJson())
          .toList(),
    );
    box.write(_currentIndexKey, audioHandler.persistedIndex);
    box.write(_modeKey, audioHandler.persistedMode.name);
  }

  static PlayOrder _decodeMode(String? s) {
    for (final m in PlayOrder.values) {
      if (m.name == s) return m;
    }
    return PlayOrder.sequential;
  }

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
  AudioPlayerHandler({
    required this._songRepo,
    required this._likedService,
    List<MediaItem> initialQueue = const [],
    int initialIndex = -1,
    PlayOrder initialMode = PlayOrder.sequential,
  }) {
    _queue = List.of(initialQueue);
    _currentIndex = initialIndex;
    _playOrder = initialMode;
    _rebuildShuffleMaps();

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

    // queue / mediaItem 是 BehaviorSubject (带当前值 replay):
    // wrapper 订阅后立即拿到初始队列与当前歌, 真相状态在 handler 落地
    queue.add(List.unmodifiable(_queue));
    mediaItem.add(_currentItem);
    // playOrder 是 broadcast (无 replay): handler 构造时 emit 一次初始值,
    // wrapper 订阅后立刻拿到 (或在 onInit 里调 refreshPlayOrder 兜底)。
    // 之所以不用 BehaviorSubject 是因为 mode 只有 3 个枚举值, 没有"replay
    // 历史"语义, broadcast 更轻量。
    _playOrderCtrl.add(_playOrder);

    _wireAudioStreams();
  }

  // ---- 依赖 ---------------------------------------------------------------------

  final SongRepository _songRepo;
  final LikedService _likedService;
  final AudioPlayer _audio = AudioPlayer();

  /// likedSongIds 变化的订阅 (用于锁屏 like 按钮 icon 实时更新)
  StreamSubscription<Set<String>>? _likedSongIdsSub;

  /// 当前歌曲是否被喜欢 — 推送给上层 wrapper 同步 snapshot.isCurrentSongLiked
  ///
  /// 设计: 不用 refreshIsLiked() 公开方法让上层调,handler 主动 emit bool 流,
  /// wrapper 直接订阅 ([_currentSongLiked] getter)。事件源两个:
  ///   1. likedSongIds 变化 (在 _wireAudioStreams 里 listen)
  ///   2. _currentItem 变化 (在 _playAt / removeQueueItemAt 等 emit mediaItem 时
  ///      顺手 _currentSongLiked.add(...))
  /// wrapper 拿到 bool 后,copyWith(snapshot.isCurrentSongLiked) 一行搞定
  final StreamController<bool> _currentSongLikedCtrl =
      StreamController<bool>.broadcast();

  /// 公开给 wrapper 订阅 (handler 主动 emit 当前歌的 like 状态)
  Stream<bool> get currentSongLiked => _currentSongLikedCtrl.stream;

  /// 主动刷一次当前歌的 liked 状态 (broadcast 无 replay,wrapper 订阅后兜底用)
  void refreshCurrentSongLiked() => _emitCurrentSongLiked();

  /// 播放顺序变化流 — 推送给 wrapper 同步 _playOrderSub
  ///
  /// 设计: 跟 currentSongLiked 一样,handler 是真相持有者 ([_playOrder] 私有
  /// 字段),改完模式后主动 emit, wrapper 只订阅不写自己的 Rx。
  /// 这样 wrapper.setPlayOrder 只是个 forward (audioHandler.setPlayOrder(...)),
  /// _playOrderSub 的更新全部由这条流驱动 — 单一真相源, 严格单向流。
  final StreamController<PlayOrder> _playOrderCtrl =
      StreamController<PlayOrder>.broadcast();

  /// 公开给 wrapper 订阅 (handler 主动 emit 播放顺序)
  Stream<PlayOrder> get playOrder => _playOrderCtrl.stream;

  /// 主动刷一次当前 playOrder (broadcast 无 replay, wrapper 订阅后兜底用)
  void refreshPlayOrder() => _playOrderCtrl.add(_playOrder);

  /// 释放 handler 持有的订阅 (handler dispose 时由 audio_service 框架调用)
  void dispose() {
    _likedSongIdsSub?.cancel();
    _likedSongIdsSub = null;
    _currentSongLikedCtrl.close();
    _playOrderCtrl.close();
  }

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

  /// 当前播放的 MediaItem（== _queue[_currentIndex]，带边界保护）。
  MediaItem? get _currentItem =>
      (_currentIndex >= 0 && _currentIndex < _queue.length)
          ? _queue[_currentIndex]
          : null;

  /// 只读暴露给 wrapper 的 _persist 用 (避开 Rx 异步滞后的旧值)。
  int get persistedIndex => _currentIndex;
  PlayOrder get persistedMode => _playOrder;
  List<MediaItem> get persistedQueue => List.unmodifiable(_queue);
  // 注:不再暴露 currentIndex 字段。wrapper 从 mediaItem.extras['queueIndex']
  // 读取当前索引,handler 在 [_playAt] / [removeQueueItemAt] 等"换索引"的地方
  // 把新索引写进对应 [MediaItem.extras] 并随 [mediaItem.add] emit。

  // ---- 订阅接线 (在构造里跑一次) -------------------------------------------------

  void _wireAudioStreams() {
    // 1. 播放状态 → playbackState + 自动跳下一首
    _audio.playerStateStream.listen((state) {
      // liked 状态查 _likedService.isLiked (实时查,不缓存);
      // 切歌后的 likes 同步走 _emitCurrentSongLiked (在 _playAt 末尾调),
      // 这里在 playerStateStream 顺带把 controls 同步上 (因为 controls 含 playing
      // 状态,play 状态变化时也要 rebuild,此时再带一次最新 liked)
      final liked = _likedService.isLiked(
        _currentItem?.id ?? '',
        LikedType.song,
      );
      playbackState.add(
        playbackState.value.copyWith(
          playing: state.playing,
          processingState: _mapProcessingState(state.processingState),
          controls: _buildControls(isCurrentSongLiked: liked),
          speed: 1.0,
        ),
      );
      // 自然播完 → 自动下一首
      //
      // - just_audio 在 setUrl 单曲驱动模式下:currentIndexStream 永远 = 0,
      //   它**不会**在 playlist 走完时自动 skipToNext(那是 ConcatenatingAudioSource
      //   的行为),所以这里手动监听 completed → 调 _neighbor(1) 推进。
      // - sequential: +1 wrap;shuffle: 走 _shuffleOrder;repeatOne: 返回
      //   _currentIndex → 重播同首(走 _playAt 重新 prepare + play)。
      // - 无需防抖:skipToNext → _playAt → _audio.setUrl → processingState
      //   立刻进 loading/idle,不会再回 completed,不存在循环。
      // - **handler 内做**而不是 wrapper/PlayerController:handler 是 just_audio
      //   流唯一订阅者,生命周期跟 app 同步,无 PlayerController 销毁后
      //   自动切歌失效的隐患。
      if (state.processingState == ProcessingState.completed) {
        final next = _neighbor(1);
        if (next >= 0) {
          // ignore: discarded_futures
          _playAt(next);
        }
      }
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
      final item = _currentItem;
      if (item == null) return;
      if (item.duration == dur) return; // 没变就别 add (避免无效广播)
      final updated = item.copyWith(duration: dur);
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

    // 6. likedSongIds 变化 → emit isCurrentSongLiked 给 wrapper 订阅,
    //    同时重建 controls (锁屏 like 按钮 icon/label 实时更新)
    //
    // RxSet.stream 返回 Stream<Set<String>>,可以直接 .listen
    // (跟 RxInt.stream、RxString.stream 一样的 API,
    // 文档: https://pub.dev/documentation/get/latest)
    _likedSongIdsSub = _likedService.likedSongIds.stream.listen((_) {
      _emitCurrentSongLiked();
    });
  }

  /// 查当前歌的 like 状态 → emit 给 wrapper + 重建 controls
  ///
  /// 由 (a) likedSongIds 变化 (b) _currentItem 变化 触发。
  void _emitCurrentSongLiked() {
    final cur = _currentItem;
    final liked = cur != null && _likedService.isLiked(cur.id, LikedType.song);
    // 推 wrapper
    _currentSongLikedCtrl.add(liked);
    // 重建锁屏 controls
    playbackState.add(
      playbackState.value.copyWith(
        controls: _buildControls(isCurrentSongLiked: liked),
      ),
    );
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
        mediaItem.add(_queue[_currentIndex]);
        // _currentItem 还是同一首歌,只是 index 调整 — isCurrentSongLiked
        // 的值没变,这里不重复 emit (wrapper 那边 isCurrentSongLiked 也不会变)
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

  /// 锁屏 like 按钮 → 转发到 LikedService.toggle (LikedType.song) (由 service 自己做乐观更新 + 错误提示)
  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    if (name != 'toggleLike') return null;
    final cur = _currentItem;
    if (cur == null) return null;
    // LikedService.toggle 接收 (id, LikedType),内部会触发 likedSongIds 变化,
    // handler 内部 listen likedSongIds.stream → _emitCurrentSongLiked →
    // 自动重建 controls + 推 currentSongLiked 给 wrapper。
    await _likedService.toggle(cur.id, LikedType.song);
    return null;
  }

  // (refreshIsLiked 已删 — 现在通过 currentSongLiked stream 推送给 wrapper,
  //  上层不需要再调一个公开方法;liked 变化全在 handler 内部处理)

  // ---- 播放顺序控制 -------------------------------------------------------------

  Future<void> setPlayOrder(PlayOrder order) async {
    if (_playOrder == order) return;
    _playOrder = order;
    // 切模式后重生成 shuffle 表 + 反向表
    _rebuildShuffleMaps();
    // currentIndex 已经是 queue 索引,不需要变
    // 推 wrapper 同步展示层 Rx (handler 是唯一真相源, _playOrderSub 由这条流镜像)
    _playOrderCtrl.add(order);
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
    // stale request 校验: await 期间用户可能又切了别的歌,
    // 此刻 _currentIndex 已不是本次目标,丢弃这个过期的 fetch 结果
    if (_currentIndex != queueIndex) return;
    _queue[queueIndex] = _queue[queueIndex].copyWith(
      extras: {
        ...?_queue[queueIndex].extras,
        'url': url,
        'queueIndex': queueIndex,
      },
    );

    await _audio.setUrl(url);
    mediaItem.add(_queue[queueIndex]);

    // repeatOne 不需要重新 prepare;sequential/shuffle 已经在 setUrl 后 just_audio
    // 会自动从 0 开始播,这里主动 play() 保证立即开始
    if (_playOrder != PlayOrder.repeatOne) {
      await _audio.play();
    } else {
      // repeatOne 但不是同一首 (从外部点过来的):重新 prepare 然后播
      await _audio.play();
    }

    // 切歌完成,同步当前歌的 liked 状态给 wrapper (修复: 旧实现只在
    // likedSongIds 变化时 emit,切歌后 isCurrentSongLiked 会停留在旧值)
    _emitCurrentSongLiked();
  }

  /// 只读窥探下一首/上一首的 queue 索引 (不改状态)。
  /// 供 wrapper 的 nextIndex/prevIndex 转发,消除 wrapper 层重复的 shuffle 状态。
  int peekNeighbor(int delta) => _neighbor(delta);

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

  /// 构造锁屏 controls。
  List<MediaControl> _buildControls({required bool isCurrentSongLiked}) {
    final playing = playbackState.value.playing;
    return [
      MediaControl.skipToPrevious,
      if (playing) MediaControl.pause else MediaControl.play,
      MediaControl.skipToNext,
      MediaControl(
        action: MediaAction.custom,
        label: isCurrentSongLiked ? '取消喜欢' : '喜欢',
        androidIcon: isCurrentSongLiked
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
