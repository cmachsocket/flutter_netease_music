import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;

import '../models/Song.dart';
import '../services/LikedService.dart';
import '../services/NewAudioPlayerService.dart';

enum CenterPage { cover, lyric }

/// 播放页 UI 控制器 — 跟 PlayPage widget 生命周期一致 (permanent: true,
/// 跨 tab 路由活)
/// ## 架构定位(自 NewAudioPlayerService 接管音频底层后)
///
/// 所有音频事实状态(`playlist` / `currentSong` / `position` / `duration` /
/// `buffered` / `isPlaying` / `isCurrentSongLiked` / `mode`)由
/// [AudioPlayerService] 持有。本 controller **不再**:
///   - 持有 [AudioPlayer] 引用
///   - 直接调 `setUrl()` / `fetchSongUrl()` — handler `_playAt` 内部完成
///   - 维护 queue / mode 真相 — wrapper.playlist / currentIndex / mode 才是
///   - 自己监听 playerStateStream 算"自然结束 → next()" — handler 不再叠
///     这层逻辑(它只把 processingState 镜像给 playbackState),由本 controller
///     在 snapshot.processingState 进 completed 时调 next() 兜底
///
/// 本 controller 只做 3 件事:
///   1. **UI facade**:把 wrapper.snapshot 的字段镜像成同名的 Rx
///      (position / duration / buffered / isPlaying / currentSong / isLiked),
///      让现有 UI (Player / BottomPlayer / MusicProgressBar) 无需改一行代码
///   2. **命令转发**:play / pause / seek / selectIndex / next / prev / togglePlay
///      全部委托给 wrapper,UI 调用点不变
///   3. **UI 局部状态**:center 切页 (cover / lyric) — 纯 UI 状态
class PlayerController extends GetxController {
  // region UI facade:从 wrapper 镜像过来 (UI 端无感)
  final Rx<Duration> position = Duration.zero.obs;
  final Rx<Duration> duration = Duration.zero.obs;
  final Rx<Duration> buffered = Duration.zero.obs;
  final RxBool isPlaying = false.obs;

  /// 当前播放的歌曲(null = 还没加载)。镜像 wrapper.snapshot.currentSong。
  final Rxn<Song> currentSong = Rxn<Song>();

  /// 当前歌曲是否被喜欢。镜像 wrapper.snapshot.isCurrentSongLiked
  /// (handler 推流;本 controller 不再订阅 LikedService.likedSongIds)。
  final RxBool isLiked = false.obs;
  // endregion

  // region UI 切页(纯 UI 状态)
  /// 中央区域当前页 (封面 / 歌词)
  final Rx<CenterPage> center = CenterPage.cover.obs;
  // endregion

  final AudioPlayerService _audio = Get.find<AudioPlayerService>();
  final LikedService _likedService = Get.find<LikedService>();

  Worker? _snapshotWorker;

  /// 防止同一首歌自然结束时重复触发 next() (handler 不再叠防抖,
  /// 由 PlayerController 在镜像层兜底一次)
  ///
  /// 时序:
  ///   - 切歌 / repeatOne 重播 / 跳到下一首:会重新调用 _playAt,
  ///     handler emit 新 mediaItem → snapshot.currentSong 变化 → 镜像层
  ///     自动 reset (见 [selectIndex]/[next]/[prev] 的 _resetAutoNext())
  ///   - 自然播完:just_audio playerStateStream 进 completed → snapshot
  ///     触发镜像 → 这里 if completed && !_autoNextFired → next() + flag=true
  bool _autoNextFired = false;

  @override
  void onInit() {
    super.onInit();
    // 镜像 wrapper.snapshot 到 UI Rx (Obx 触发保持不变)。
    // duration 字段也在 _onSnapshot 里更新 (snapshot.currentSong.duration →
    // 即时 currentSong 的最新 duration,handler durationStream 实时维护)
    _snapshotWorker = ever<PlaybackSnapshot>(_audio.snapshot, _onSnapshot);
    _onSnapshot(_audio.snapshot.value);
  }

  @override
  void onClose() {
    _snapshotWorker?.dispose();
    super.onClose();
  }

  /// snapshot 镜像 + 自然播完 → 下一首
  void _onSnapshot(PlaybackSnapshot s) {
    isPlaying.value = s.isPlaying;
    position.value = s.position;
    buffered.value = s.bufferedPosition;
    currentSong.value = s.currentSong;
    isLiked.value = s.isCurrentSongLiked;
    // 当前歌的 duration 从 snapshot.currentSong 拿 (wrapper._itemToSong 把
    // MediaItem.duration 翻进了 Song.duration,而 MediaItem.duration 是
    // handler 监听 just_audio durationStream 实时维护的 → 切歌后会有几次
    // emit(0 → 真值), snapshot.currentSong 会跟着更新)
    if (s.currentSong != null) {
      duration.value = s.currentSong!.duration;
    } else if (!_audio.playlist.isEmpty &&
        _audio.currentIndex.value >= 0 &&
        _audio.currentIndex.value < _audio.playlist.length) {
      // currentSong 还没 emit (handler 异步 _playAt 中) 但 playlist 已经有,
      // 用 playlist[currentIndex].duration 占位 (Song 元数据,可能略不准)
      duration.value = _audio.playlist[_audio.currentIndex.value].duration;
    } else {
      duration.value = Duration.zero;
    }
    _maybeAutoNext(s);
  }

  /// 自然播完 → next()
  ///
  /// - snapshot.processingState 进 completed 时触发 (handler 把 just_audio
  ///   的 processingState 镜像给 audio_service, 再被 wrapper 镜像给 snapshot)
  /// - _autoNextFired 防抖:同首歌只触发一次
  /// - 任何"非 completed"且有当前歌的状态(loading/buffering/ready)都视为
  ///   新歌 / 重播开始 → reset 防抖,允许下一次播完后再次触发
  void _maybeAutoNext(PlaybackSnapshot s) {
    if (s.processingState == ProcessingState.completed) {
      if (_autoNextFired) return;
      _autoNextFired = true;
      next();
    } else if (s.currentSong != null) {
      _autoNextFired = false;
    }
  }

  /// 当前歌的时长已经在 [_onSnapshot] 里覆盖 (snapshot.currentSong.duration),
  /// 这里只是注释说明,不再单独 worker:切歌 → handler emit → snapshot 触发
  /// _onSnapshot → duration 自动刷新。
  // (旧的 _refreshDuration() 已删,duration 跟随 snapshot 镜像)

  // region 命令转发 (UI 调用)

  /// 公开 selectIndex(int) —— PlayListPage 等"点队列里某一首"走这里。
  ///
  /// 委托给 [AudioPlayerService.selectIndex],handler 内部 skipToQueueItem
  /// → _playAt → fetch URL → setUrl → mediaItem.add 流回推 snapshot。
  void selectIndex(int index) => _audio.selectIndex(index);

  /// 公开 next() —— 锁屏/通知/UI 下一首按钮走这里。
  ///
  /// handler `_neighbor(1)` 按 mode 计算索引:repeatOne 返回 _currentIndex
  /// → 重播同首,sequential/shuffle 正常推进。不再需要上层"防抖 + 手动
  /// seek(0) + play()"的 repeatOne 兜底逻辑(handler 内部 _playAt 已经
  /// 重新 prepare + play)。
  void next() => _audio.skipToNext();

  /// 公开 prev() —— 锁屏/通知/UI 上一首按钮走这里。
  void prev() => _audio.skipToPrevious();

  // endregion

  void play() => _audio.play();
  void pause() => _audio.pause();
  void togglePlay() => isPlaying.value ? pause() : play();

  /// 手动 seek —— 直接转发到 wrapper.seek,handler 走 audio_service 标准路径。
  ///
  /// 不再需要 `_userSeeked` 标记(handler 不再有"自然结束 vs 用户 seek"区分
  /// 需求:ProcessingState.completed → 自动 skipToNext 是 handler 监听
  /// playerStateStream 自己跳,跟用户 seek 不冲突)。
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
  /// - 转发给 [LikedService.toggle] (LikedType.song),UI 不用直接接触 service
  /// - wrapper.snapshot.isCurrentSongLiked 会通过 handler 推流更新,
  ///   本 controller 镜像层自动跟 (ever<PlaybackSnapshot>)
  /// - 没有当前歌曲时是 no-op
  void toggleFavorite() {
    final song = currentSong.value;
    if (song == null) return;
    // ignore: discarded_futures
    _likedService.toggle(song.id, LikedType.song);
  }
}

/// 启动时注册(在 main.dart 里调)
class PlayerBinding extends Bindings {
  @override
  void dependencies() => Get.lazyPut(() => PlayerController());
}