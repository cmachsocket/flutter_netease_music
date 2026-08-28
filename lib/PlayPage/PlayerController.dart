import 'dart:async';

import 'package:just_audio/just_audio.dart';
import 'package:get/get.dart';

import '../models/Song.dart';
import '../services/PlayQueueService.dart';
import '../services/LikedSongsService.dart';
import '../sdk/api_exception.dart';
import '../sdk/netease_api.dart';
import '../services/AudioPlayerService.dart';

enum CenterPage { cover, lyric }

/// 播放页统一控制器:进度 + 切页 + 歌词 + 实际音频加载
///
/// - **音频**:通过 [AudioPlayerService] 调 just_audio,
///   [loadSong] 走 `/song/url` 拿临时 mp3 直链 → `setUrl` 加载 → `play()`
/// - **进度**:订阅 [AudioPlayerService.positionStream] 写 [position];
///   订阅 [durationStream] 写 [duration](避免被 Player 那边 push 覆盖)
/// - **歌词**:由 [LyricsController] (page→controller→service) 负责拉 + 灌 lyric,
///   本 controller 不再持有 lyricController。
/// - **切页**:左右滑切 cover / lyric(原有 UI 逻辑)
class PlayerController extends GetxController {
  /// bitrate 默认 standard(128k = '128000')。
  ///
  /// **NetEase API 只认数字字符串码率**(128000/192000/320000/999000),不识别
  /// "standard"/"exhigh" 这种语义别名 —— 传字符串后端返 500 + body "undefined"
  /// (2026-08-10 复现确认)。SDK 不做转换,直接拼进 query。
  static const String defaultBitrate = '128000';

  // region 播放状态(由 AudioPlayer stream 推动)
  final Rx<Duration> position = Duration.zero.obs;
  final Rx<Duration> duration = Duration.zero.obs;
  final Rx<Duration> buffered = Duration.zero.obs;
  final RxBool isPlaying = false.obs;

  /// 当前播放的歌曲(null = 还没加载)
  final Rxn<Song> currentSong = Rxn<Song>();

  /// 当前加载是否进行中(用来显示 loading 状态,避免重复触发)
  final RxBool isLoadingSong = false.obs;

  /// 当前歌曲是否被喜欢(联动 currentSong + LikedSongsService.likedIds)
  ///
  /// UI 读 `controller.isLiked.value` 即可响应式刷新
  final RxBool isLiked = false.obs;
  // endregion

  // region UI 切页
  /// 中央区域当前页 (封面 / 歌词)
  ///
  /// **不用裸 int** —— enum 在编译期挡住外部 `.value = 99` 这种垃圾值,
  /// switch 也带 exhaustiveness 检查(加新 page 时漏 case 编译器报错)。
  final Rx<CenterPage> center = CenterPage.cover.obs;
  // endregion

  // region 歌词
  // lyricController / setProgress / setOnTapLineCallback 都不在 PlayerController 里,
  // 由独立的 [LyricsController] 负责 (page→controller→service 分层)。
  Worker? _queueIndexWorker;
  Worker? _queuePlaylistWorker;
  Worker? _currentSongWorker;
  Worker? _likedIdsWorker;
  bool _queueSyncScheduled = false;

  /// 自然结束自动切歌的防抖标志：同一首歌只触发一次 next()，
  /// 避免 playerStateStream / position 兜底双重触发导致跳歌。
  bool _autoNextFired = false;
  // endregion

  final LikedSongsService _likedService = Get.find<LikedSongsService>();

  final NeteaseApi api = Get.find<NeteaseApi>();
  final PlayQueueService queue = Get.find<PlayQueueService>();

  late final AudioPlayerService _audio;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<Duration>? _bufSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<PlayerState>? _stateSub;

  @override
  void onInit() {
    super.onInit();
    _audio = Get.find<AudioPlayerService>();

    // 订阅 just_audio 的 stream → 写 Rx
    _posSub = _audio.positionStream.listen(_onPositionChange);
    _durSub = _audio.durationStream.listen((d) {
      if (d != null) duration.value = d;
    });
    _bufSub = _audio.bufferedPositionStream.listen((b) => buffered.value = b);
    _playingSub = _audio.playingStream.listen((p) {
      isPlaying.value = p;
    });
    // 播完一首 → 自动切下一首
    _stateSub = _audio.playerStateStream.listen(_onPlayerState);

    _queueIndexWorker = ever<int>(
      queue.currentIndex,
      (_) => _scheduleQueueSync(),
    );
    _queuePlaylistWorker = ever<List<Song>>(
      queue.playlist,
      (_) => _scheduleQueueSync(),
    );

    // 当前歌 + likedIds 联动 → isLiked
    _currentSongWorker = ever<Song?>(currentSong, (_) => _refreshIsLiked());
    _likedIdsWorker = ever<Set<String>>(
      _likedService.likedIds,
      (_) => _refreshIsLiked(),
    );
  }

  @override
  void onClose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _bufSub?.cancel();
    _playingSub?.cancel();
    _stateSub?.cancel();
    _queueIndexWorker?.dispose();
    _queuePlaylistWorker?.dispose();
    _currentSongWorker?.dispose();
    _likedIdsWorker?.dispose();
    // lyricController 不再 dispose, 由 [LyricsService] (permanent: true) 跨 widget 生命周期拥有
    super.onClose();
  }

  /// 播完一首 → 自动切下一首
  ///
  /// 两个入口信号:
  /// 1. **[_onPlayerState]**: 负责 `processingState == completed`(iOS/desktop 默认 backend
  ///    正常路径)。completed 是 just_audio backend 明确告诉“媒体播完了”，人工 seek 不会触发。
  /// 2. **[_onPositionChange]**: 负责 Android/just_audio_media_kit 上 completed 事件丢了
  ///    的兑底。 media_kit 在 complete 事件中把 _position reset 到 0 (mediakit_player.dart:131),
  ///    同时由于 _player.open(Media) 后 _player.state.playlist.medias 是空数组,
  ///    line 132-137 的 last-track 条件不成立 → completed 不转 ProcessingState.completed。
  ///    兑底策略: position 出现“接近末尾 → 接近 0”的跳变且未发生用户主动 seek → next().
  ///
  /// 防抖 [_autoNextFired]: 同一首歌只允许触发一次 next(), 避免双信号走两遍导致跳歌。
  /// [loadSong] 开头重置 → 下首歌开始播放后可重新触发。 repeatOne 走 [next]/[prev] 里的
  /// 手动重置 → 重播结束后还能再触发。
  void _onPlayerState(PlayerState state) {
    if (state.processingState != ProcessingState.completed) return;
    if (_autoNextFired) return;
    _autoNextFired = true;
    next();
  }

  /// 上一次 positionStream 是否接近末尾 (供 [_onPositionChange] 判断跳变)
  bool _lastNearEnd = false;

  /// position stream 变化 → _onPlayerState (processingState.completed) 的兑底
  ///
  /// Android/just_audio_media_kit 下需兑底的原因 (见 [_onPlayerState] 头部 doc):
  /// media_kit 在 complete 事件中会把 _position reset 到 0 (mediakit_player.dart:131),
  /// positionStream 会 emit 一次 0。 这跟用户手动 seek 到 0 看起来一样, 需要 [_userSeeked]
  /// 区分。
  ///
  /// 判断逻辑: 上一次 position 接近 dur (且本次不接近 dur) 且未产生 [_userSeeked] →
  /// 认定为自然结束 → next().
  void _onPositionChange(Duration p) {
    position.value = p;
    final dur = duration.value;
    if (dur == Duration.zero) {
      _lastNearEnd = false;
      return;
    }
    final nearEnd = p >= dur - const Duration(milliseconds: 800);
    if (nearEnd) {
      // 接近末尾,  标记为“候选跳变起点”,  等下一帧看是 reset 还是用户继续在末尾。
      _lastNearEnd = true;
      return;
    }
    // 当前位置不接近末尾 (如果不是 0 或很小)。 如果上一次接近末尾 → MediaKit reset
    // 产生的大幅跳变 → 自然结束 (除非用户主动 seek)。
    final wasNearEnd = _lastNearEnd;
    _lastNearEnd = false;
    if (!wasNearEnd) return;
    if (_autoNextFired) return;
    if (_userSeeked) {
      _userSeeked = false;
      return;
    }
    _autoNextFired = true;
    next();
  }

  /// 公开 selectIndex(int) —— PlayListPage 等"点队列里某一首"走这里
  ///
  /// - **不依赖 ever worker**:`selectIndex` 改 currentIndex 后,只有值真的变了
  ///   `ever<int>` 才会触发，点当前 currentIndex 时不会触发 → 永远没反应。
  /// - 手动调一次 [_scheduleQueueSync] 解决:`_syncQueueState` 内部有
  ///   `currentSong.id == target.id` 早退守卫,如果是同一首就早退(不会重播);
  ///   不同首就 loadSong。
  /// - 从 GetStorage 恢复的场景下,currentIndex 已经指向一首但 currentSong=null
  ///   (从来没加载过),_syncQueueState 会发现 `null != target.id` → 调 loadSong ✅
  void selectIndex(int index) {
    queue.selectIndex(index);
    _scheduleQueueSync();
  }

  /// 公开 next() —— 锁屏/通知"下一首"按钮走这里
  ///
  /// - 委托 [PlayQueueService.nextIndex] 算索引 + [queue.selectIndex] 触发 _syncQueueState 加载
  /// - audio_service 的 PlaybackService 也会调这个 (锁屏按 next 时 app 不一定在前台)
  /// - repeatOne 模式: 同首重播,不走切歌
  void next() {
    final n = queue.nextIndex();
    if (n < queue.headOfTheQueue) return;
    queue.selectIndex(n);
    if (queue.mode.value == PlayMode.repeatOne) {
      // repeatOne 不会重新 loadSong，这里手动重置防抖，
      // 让同一首歌重播到结尾后还能再次触发自动重播。
      _autoNextFired = false;
      _audio.seek(Duration.zero);
      _audio.play();
    }
  }

  /// 公开 prev() —— 锁屏/通知"上一首"按钮走这里
  ///
  /// - sequential 模式下走反向循环(队首 wrap 到队尾), service 永远返回有效索引
  /// - shuffle / repeatOne: 同 next 的语义
  void prev() {
    final p = queue.prevIndex();
    if (p < queue.headOfTheQueue) return;
    queue.selectIndex(p);
    if (queue.mode.value == PlayMode.repeatOne) {
      // repeatOne 不会重新 loadSong，这里手动重置防抖，
      // 让同一首歌重播到结尾后还能再次触发自动重播。
      _autoNextFired = false;
      _audio.seek(Duration.zero);
      _audio.play();
    }
  }

  void _scheduleQueueSync() {
    if (_queueSyncScheduled) return;
    _queueSyncScheduled = true;
    Future.microtask(() {
      _queueSyncScheduled = false;
      _syncQueueState();
    });
  }

  void _syncQueueState() {
    if (isLoadingSong.value) return;

    if (queue.playlist.isEmpty) {
      if (currentSong.value != null) {
        currentSong.value = null;
        seek(Duration.zero);
        pause();
      }
      return;
    }

    final index = queue.currentIndex.value;
    if (index < queue.headOfTheQueue || index > queue.tailOfTheQueue) return;

    final target = queue.playlist[index];
    if (currentSong.value?.id == target.id) return;

    unawaited(loadSong(target));
  }

  /// 加载并播放一首新歌
  ///
  /// 流程:1) 调 /song/url 拿临时 mp3 直链 → 2) just_audio setUrl → 3) play
  /// - 已经在加载同一首 → 直接 return(避免重入)
  /// - 失败 → SnackBar 提示,UI 状态保留(不切歌)
  Future<void> loadSong(Song song, {String bitrate = defaultBitrate}) async {
    if (isLoadingSong.value) return;
    isLoadingSong.value = true;
    // 新歌真正开始加载，允许下一首自然结束时再次自动 next。
    _autoNextFired = false;
    try {
      final r = await api.call(
        (a) => a.song_url(song.id, br: bitrate),
        what: '取播放 URL',
      );
      final httpUrl = _extractFirstUrl(r.body) ?? "";
      late String url;
      if (httpUrl.startsWith('http://')) {
        url = httpUrl.replaceFirst('http://', 'https://');
      } else {
        url = httpUrl;
      }
      if (url.isEmpty) {
        Get.snackbar(
          '无法播放',
          '${song.title} 取不到播放 URL(可能是 VIP / 版权)',
          snackPosition: SnackPosition.BOTTOM,
        );
        return;
      }

      currentSong.value = song;
      // 歌词由 [LyricsService] 监听 currentSong 自动拉 + 灌 lyricController,
      // 这里不需要等。 LyricsService 在 PlayerController 之前已注册 (main.dart),
      // 且 lyricController 由 service 跨实例持有 (跟 widget 生命周期解耦)。

      await _audio.setUrl(url);
      await _audio.play();
    } on ApiException catch (e) {
      Get.snackbar(
        '加载失败 (code ${e.code})',
        e.message,
        snackPosition: SnackPosition.BOTTOM,
      );
    } finally {
      isLoadingSong.value = false;
    }
  }

  /// /song/url 返回结构:body['data'][0]['url']
  String? _extractFirstUrl(Map<String, dynamic> body) {
    final data = body['data'];
    if (data is! List || data.isEmpty) return null;
    final first = data.first;
    if (first is Map) return (first['url'] as String?)?.toString();
    return null;
  }

  /// 拉歌词并灌进 lyricController
  ///
  /// - 调 /lyric/new(id) 拿 yrc (逐字) + lrc (普通) 两个字段
  /// - 优先 yrc:有逐字歌词更精细。flutter_lyric 的 QrcParser 能处理 yrc 格式,
  ///   JSON metadata 行 ({...}) 由其 lineRegExp 自动跳过
  // region 控制接口(给 Player UI 调用)
  void play() => _audio.play();
  void pause() => _audio.pause();
  void togglePlay() => isPlaying.value ? pause() : play();
  /// 手动 seek —— 标记一下供 [_onPositionChange] 区分"用户主动 seek"vs"自然播完 reset"
  ///
  /// 背景:Android/just_audio_media_kit 播完时 media_kit.completed 会把 position
  /// reset 到 0 (mediakit_player.dart:131),  positionStream 会 emit 一次 0。
  /// 这跟用户手动 seek 到 0 在 stream 看来一样。 需要一个有意识的标记。
  bool _userSeeked = false;
  void seek(Duration p) {
    _userSeeked = true;
    _audio.seek(p);
  }
  void switchPage() {
    // exhaustive switch: enum 加新 page 时编译器报错,不会静默走错分支
    center.value = switch (center.value) {
      CenterPage.cover => CenterPage.lyric,
      CenterPage.lyric => CenterPage.cover,
    };
  }

  /// toggle 当前歌曲的喜欢状态
  ///
  /// - 转发给 [LikedSongsService],UI 不用直接接触 service
  /// - 没有当前歌曲时是 no-op
  void toggleFavorite() {
    final song = currentSong.value;
    if (song == null) return;
    // ignore: discarded_futures
    _likedService.toggle(song.id);
  }
  // endregion

  void _refreshIsLiked() {
    final song = currentSong.value;
    isLiked.value = song != null && _likedService.likedIds.contains(song.id);
  }
}

/// 启动时注册(在 main.dart 里调)
class PlayerBinding extends Bindings {
  @override
  void dependencies() => Get.lazyPut(() => PlayerController());
}
