import 'package:audio_service/audio_service.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState, PlayerState;

import '../models/Song.dart';
import '../PlayPage/PlayerController.dart';
import 'AudioPlayerService.dart';
import 'LikedSongsService.dart';
import 'PlayQueueService.dart';

/// 后台播放 handler —— audio_service 0.18 的 [BaseAudioHandler]
///
/// 职责分层(避免业务逻辑双份):
/// - **队列**(`queue` / `mediaItem` / 模式):从 [PlayQueueService] 订阅,这边只做
///   broadcast(`BaseAudioHandler` 要求内部 `BehaviorSubject<List<MediaItem>>`)
/// - **播放控制**(play / pause / stop / seek):直接转发给 [AudioPlayerService]
/// - **next / prev**(锁屏按"下一首" / 通知栏按钮):委托给 [PlayerController]
///   —— 因为 next/prev 实际要"切歌+加载新歌",这部分逻辑本来就在
///   `PlayerController._onPlayerState` 里,音频 handler 复制一份会双份维护
///
/// **重要**:`PlaybackService` 在 `WidgetsFlutterBinding.ensureInitialized()` **之后**、
/// `AudioPlayerService` 注册之后实例化(handler 内部 [Get.find] 拉这两个 service)。
/// 在 main.dart 里走 `AudioService.init(builder: () => PlaybackService(), ...)`。
class PlaybackService extends BaseAudioHandler
    with
        // QueueHandler: 默认实现 addQueueItem / removeQueueItem / updateQueue
        // SeekHandler: 默认实现 seek / seekForward / seekBackward
        QueueHandler,
        SeekHandler {
  final AudioPlayerService _audio = Get.find<AudioPlayerService>();
  final PlayQueueService _queue = Get.find<PlayQueueService>();
  final PlayerController _player = Get.find<PlayerController>();

  PlaybackService() {
    // 订阅 AudioPlayer 的状态 → broadcast 给系统通知/锁屏
    _audio.player.playerStateStream.listen(_broadcastState);
    // 订阅当前歌曲变化 → broadcast mediaItem
    _player.currentSong.listen(_broadcastMediaItem);
    // 订阅队列变化 → broadcast queue
    _queue.playlist.listen(_broadcastQueue);
    _queue.currentIndex.listen((_) => _broadcastMediaItem(_player.currentSong.value));
    // 订阅喜欢状态变化 → 重建 controls (单按钮 toggle, 跟着 isLiked 切 like/dislike icon)
    _player.isLiked.listen((_) => _resyncControls());
    // 订阅歌曲变化也重建 controls (新歌 isLiked 状态不一样, like 按钮的 icon/label 要换)
    _player.currentSong.listen((_) => _resyncControls());
  }

  void _broadcastState(PlayerState state) {
    final playing = state.playing;
    playbackState.add(
      playbackState.value.copyWith(
        controls: _buildControls(isLiked: _player.isLiked.value),
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: _mapProcessingState(state.processingState),
        playing: playing,
        updatePosition: _player.position.value,
        bufferedPosition: _player.buffered.value,
        speed: 1.0,
      ),
    );
  }

  /// 重新 emit 一次 PlaybackState (不改 playing/processingState, 只刷新 controls)
  ///
  /// 场景: like 状态变了 (isLiked 流触发) / 换了首歌 (currentSong 流触发)
  /// 不重读 playerStateStream 而是复用上一次播报的状态,
  /// 避免双重 state 覆盖产生 race
  void _resyncControls() {
    final prev = playbackState.value;
    playbackState.add(
      prev.copyWith(
        controls: _buildControls(isLiked: _player.isLiked.value),
      ),
    );
  }

  List<MediaControl> _buildControls({required bool isLiked}) {
    final playing = playbackState.value.playing;
    return [
      MediaControl.skipToPrevious,
      if (playing) MediaControl.pause else MediaControl.play,
      MediaControl.skipToNext,
      // like 按钮 (单按钮 toggle):
      // - 未 like → 提示点击后喜欢, icon 用空心心 ic_favorite_border
      // - 已 like → 提示点击后取消, icon 用实心心 ic_favorite
      MediaControl(
        action: MediaAction.custom,
        label: isLiked ? '取消喜欢' : '喜欢',
        androidIcon: isLiked
            ? 'drawable/ic_favorite'
            : 'drawable/ic_favorite_border',
        customAction: const CustomMediaAction(name: 'toggleLike'),
      ),
    ];
  }

  void _broadcastMediaItem(Song? song) {
    if (song == null) {
      mediaItem.add(null);
      return;
    }
    mediaItem.add(
      MediaItem(
        id: song.id,
        title: song.title,
        artist: song.artist,
        album: song.album,
        duration: _player.duration.value,
        // artUri: TODO 后续接封面 URL
      ),
    );
  }

  void _broadcastQueue(List<Song> songs) {
    queue.add(
      songs
          .map(
            (s) => MediaItem(
              id: s.id,
              title: s.title,
              artist: s.artist,
              album: s.album,
            ),
          )
          .toList(),
    );
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

  // ---- 标准 system action 实现 ----

  @override
  Future<void> play() => _audio.play();

  @override
  Future<void> pause() => _audio.pause();

  @override
  Future<void> stop() async {
    await _audio.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _audio.seek(position);

  @override
  Future<void> skipToNext() async {
    _player.next();
  }

  @override
  Future<void> skipToPrevious() async {
    _player.prev();
  }

  // ---- 自定义 action: 锁屏/通知栏"喜欢"按钮 ----

  /// 锁屏/通知栏按 like 按钮 → 调 [LikedSongsService.toggle]
  ///
  /// 不重复 try/catch: LikedSongsService.toggle 内部已经做了
  /// 乐观更新 + 失败回滚 + SnackBar 错误提示,这里只负责转发
  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    if (name != 'toggleLike') return null;
    final song = _player.currentSong.value;
    if (song == null) return null;
    await Get.find<LikedSongsService>().toggle(song.id);
    return null;
  }

  // ---- QueueHandler 默认实现够了,不用 override ----
}