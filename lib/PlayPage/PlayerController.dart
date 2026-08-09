import 'dart:async';

import 'package:flutter_lyric/flutter_lyric.dart';
import 'package:get/get.dart';

import '../models/Song.dart';
import '../PlayListPage/PlayQueueService.dart';
import '../sdk/api_exception.dart';
import '../sdk/netease_api.dart';
import 'AudioPlayerService.dart';

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
  final Rx<Duration> duration = const Duration(minutes: 3).obs;
  final RxBool isPlaying = false.obs;

  /// 当前播放的歌曲(null = 还没加载)
  final Rxn<Song> currentSong = Rxn<Song>();

  /// 当前加载是否进行中(用来显示 loading 状态,避免重复触发)
  final RxBool isLoadingSong = false.obs;
  // endregion

  // region UI 切页
  final RxInt centerIndex = 0.obs;
  // endregion

  // region 歌词
  final LyricController lyricController = LyricController();
  Worker? _positionWorker;
  Worker? _queueIndexWorker;
  Worker? _queuePlaylistWorker;
  bool _queueSyncScheduled = false;
  // endregion

  final NeteaseApi api = Get.find<NeteaseApi>();
  final PlayQueueService queue = Get.find<PlayQueueService>();

  late final AudioPlayerService _audio;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<bool>? _playingSub;

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
    _playingSub = _audio.playingStream.listen((p) => isPlaying.value = p);

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

    // 点击歌词行 → seek
    lyricController.setOnTapLineCallback((Duration p) {
      _audio.seek(p);
    });
  }

  @override
  void onClose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _playingSub?.cancel();
    _positionWorker?.dispose();
    _queueIndexWorker?.dispose();
    _queuePlaylistWorker?.dispose();
    lyricController.dispose();
    super.onClose();
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
      final url = _extractFirstUrl(r.body);
      if (url == null || url.isEmpty) {
        Get.snackbar(
          '无法播放',
          '${song.title} 取不到播放 URL(可能是 VIP / 版权)',
          snackPosition: SnackPosition.BOTTOM,
        );
        return;
      }
      currentSong.value = song;
      await _audio.setUrl(url);
      await _audio.play();
      // 歌词加载(异步,不阻塞音频启动)
      unawaited(fetchLyric(song.id));
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
  void switchPage() => centerIndex.value = centerIndex.value == 0 ? 1 : 0;
  // endregion
}

/// 启动时注册(在 main.dart 里调)
class PlayerBinding extends Bindings {
  @override
  void dependencies() => Get.lazyPut(() => PlayerController());
}
