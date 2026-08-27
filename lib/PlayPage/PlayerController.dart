import 'dart:async';

import 'package:flutter_lyric/flutter_lyric.dart';
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
/// - **歌词**:由 [fetchLyric] 主动拉 `/lyric`(TODO 后续切 lyric_new 拿逐字)
///   失败 / 空 → lyric 留空,UI 显示"暂无歌词"
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
  final LyricController lyricController = LyricController();
  Worker? _positionWorker;
  Worker? _queueIndexWorker;
  Worker? _queuePlaylistWorker;
  Worker? _currentSongWorker;
  Worker? _likedIdsWorker;
  bool _queueSyncScheduled = false;
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
    // 歌词留空 —— 由 [loadSong] 成功后调 [fetchLyric] 注入
    lyricController.loadLyric('');

    // 订阅 just_audio 的 stream → 写 Rx
    _posSub = _audio.positionStream.listen((p) => position.value = p);
    _durSub = _audio.durationStream.listen((d) {
      if (d != null) duration.value = d;
    });
    _bufSub = _audio.bufferedPositionStream.listen((b) => buffered.value = b);
    _playingSub = _audio.playingStream.listen((p) => isPlaying.value = p);
    // 播完一首 → 自动切下一首
    _stateSub = _audio.playerStateStream.listen(_onPlayerState);

    // 进度推进 → 歌词高亮 + 自动滚动
    _positionWorker = ever<Duration>(position, lyricController.setProgress);

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

    // 点击歌词行 → seek
    lyricController.setOnTapLineCallback((Duration p) {
      _audio.seek(p);
    });
  }

  @override
  void onClose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _bufSub?.cancel();
    _playingSub?.cancel();
    _stateSub?.cancel();
    _positionWorker?.dispose();
    _queueIndexWorker?.dispose();
    _queuePlaylistWorker?.dispose();
    _currentSongWorker?.dispose();
    _likedIdsWorker?.dispose();
    lyricController.dispose();
    super.onClose();
  }

  /// 播完一首 → 自动切下一首
  ///
  /// - 只看 `processingState == completed`(自然结束;手动 seek 不会触发这个)
  /// - **走 [PlayQueueService.nextIndex]** —— 模式(sequential/shuffle/repeatOne)
  ///   全在 service 里算, 这里只负责"查索引 → selectIndex → 触发 _syncQueueState"
  /// - sequential 模式下走顺序循环(队尾 wrap 到 0), service 永远返回有效索引
  ///   (除非 playlist 为空)
  /// - repeatOne → 同一首, service 自己处理(本函数选回当前 index → _syncQueueState
  ///   看到 currentSong.id == target.id 早退, 这里手动 seek + play 重启)
  void _onPlayerState(PlayerState state) {
    if (state.processingState != ProcessingState.completed) return;
    next();
  }

  /// 公开 next() —— 锁屏/通知"下一首"按钮走这里
  ///
  /// - 委托 [PlayQueueService.nextIndex] 算索引 + [queue.selectIndex] 触发 _syncQueueState 加载
  /// - audio_service 的 PlaybackService 也会调这个 (锁屏按 next 时 app 不一定在前台)
  /// - repeatOne 模式: 同首重播,不走切歌
  void next() {
    final n = queue.nextIndex();
    if (n < 0) return;
    queue.selectIndex(n);
    if (queue.mode.value == PlayMode.repeatOne) {
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
    if (p < 0) return;
    queue.selectIndex(p);
    if (queue.mode.value == PlayMode.repeatOne) {
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
    if (index < 0 || index >= queue.playlist.length) return;

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

      // 先拉歌词(同步 FFI,通常很快),避免与 ExoPlayer 首次初始化竞争。
      // Android 首次点播放时若歌词请求在 play() 之后异步发起,可能因时序
      // 竞态拿不到歌词;这里改为提前 await,保证第一次播放就有歌词。
      await fetchLyric(song.id);

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
  /// - 调 /lyric(id) 拿 lrc 字段
  /// - 失败 / 为空 → lyric 留空,UI 显示"暂无歌词"
  Future<void> fetchLyric(String songId) async {
    try {
      final r = await api.call((a) => a.lyric(songId), what: '取歌词');
      final lrc = (r.body['lrc']?['lyric'] as String?)?.toString() ?? '';
      if (lrc.trim().isEmpty) return;
      lyricController.loadLyric(lrc);
    } on ApiException {
      // 静默:歌词拿不到不影响播放
    }
  }

  // region 控制接口(给 Player UI 调用)
  void play() => _audio.play();
  void pause() => _audio.pause();
  void togglePlay() => isPlaying.value ? pause() : play();
  void seek(Duration p) => _audio.seek(p);
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
