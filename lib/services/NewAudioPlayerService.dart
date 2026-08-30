import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:audio_service/audio_service.dart';
import '../models/Headers.dart';
import '../models/Song.dart';
import '../PlayPage/PlayerController.dart';
import 'LikedSongsService.dart';
import 'PlayQueueService.dart';
import 'repositories/song_repository.dart';

enum PlayOrder { sequential, shuffle, repeatOne }

// 包装器，将 AudioHandler 广播的流转换为 Rx 流，方便在 GetX 中使用
class AudioPlayerService extends GetxController {
  // 持有 AudioHandler 实例
  late final AudioHandler audioHandler;
  //  // 依赖注入: 底层url获取
  final SongRepository _repo = Get.find<SongRepository>();

  // 异步初始化 AudioHandler
  Future<void> initAudioHandler() async {
    // MediaKit 初始化是同步阻塞,放在 service onInit 里完成。
    // 后续 setUrl/play 直接用,不需要再 await ready(竞态源)。
    JustAudioMediaKit.ensureInitialized();
    audioHandler = await AudioService.init(
      builder: () => AudioPlayerHandler(repo: _repo),
    );
  }
}

/// 后台播放 handler —— audio_service 0.18 的 [BaseAudioHandler]
/// 这是一个抽象音频处理器，本质上是一种controller，负责处理音频播放的各种操作和状态管理。
/// 原生提供了队列与音频状态的流
class AudioPlayerHandler extends BaseAudioHandler
    with
        // QueueHandler: 默认实现 addQueueItem / removeQueueItem / updateQueue
        // SeekHandler: 默认实现 seek / seekForward / seekBackward
        QueueHandler,
        SeekHandler {
  static const int headerOfQueue = 0;
  int get tailOfQueue => _queue.length - 1;
  final _audio = AudioPlayer();
  PlayOrder _playOrder = PlayOrder.sequential;
  late final SongRepository _repo;
  List<MediaItem> _queue = [];
  // 离散化随机映射表
  List<int> _shuffleQueueIndex = [];
  int _shuffleIndex = -1;
  int _currentIndex = -1;
  @override
  Future<void> updateQueue(List<MediaItem> newQueue) async {
    _queue = newQueue;
    // 将队列广播出去，供UI层更新
    await super.updateQueue(newQueue);
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (_queue.isEmpty) return;
    if (index < headerOfQueue || index > tailOfQueue) return;
    _currentIndex = index;
    await notifyAndPlay(
      index: _currentIndex,
      isPlayAtRepeatOne: _playOrder == PlayOrder.repeatOne,
    );
    await super.skipToQueueItem(index);
  }

  @override
  Future<void> removeQueueItemAt(int index) async {
    // 直接操作 just_audio 移除歌曲
    // 监听器会自动更新
    if (_queue.isEmpty) return;
    if (index < headerOfQueue || index > tailOfQueue) return;

    if (index == _currentIndex) {
      // 如果移除的是当前播放的歌曲，先暂停播放
      _currentIndex = -1; // 重置当前索引
      await pause();
    }
    // 移除队列中的歌曲
    _queue.removeAt(index);
    // 更新广播的队列
    await updateQueue(_queue);
    await super.removeQueueItemAt(index);
  }

  @override
  Future<void> skipToNext() async {
    if (_queue.isEmpty) return;
    if (_currentIndex < 0 || _currentIndex > tailOfQueue) return;
    if (_playOrder == PlayOrder.shuffle || _playOrder == PlayOrder.sequential) {
      if (_currentIndex < tailOfQueue) {
        _currentIndex++;
      } else {
        _currentIndex = headerOfQueue; // 循环到队列头
      }
      if (_playOrder == PlayOrder.shuffle) {
        _shuffleIndex = _shuffleQueueIndex[_currentIndex];
        await notifyAndPlay(
          index: _shuffleIndex,
          isPlayAtRepeatOne: _playOrder == PlayOrder.repeatOne,
        );
      } else {
        await notifyAndPlay(
          index: _currentIndex,
          isPlayAtRepeatOne: _playOrder == PlayOrder.repeatOne,
        );
      }
    }

    await super.skipToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    if (_queue.isEmpty) return;
    if (_currentIndex < 0 || _currentIndex > tailOfQueue) return;
    if (_playOrder == PlayOrder.shuffle || _playOrder == PlayOrder.sequential) {
      if (_currentIndex > headerOfQueue) {
        _currentIndex--;
      } else {
        _currentIndex = tailOfQueue; // 循环到队列尾
      }
      if (_playOrder == PlayOrder.shuffle) {
        _shuffleIndex = _shuffleQueueIndex[_currentIndex];
        await notifyAndPlay(
          index: _shuffleIndex,
          isPlayAtRepeatOne: _playOrder == PlayOrder.repeatOne,
        );
      } else {
        await notifyAndPlay(
          index: _currentIndex,
          isPlayAtRepeatOne: _playOrder == PlayOrder.repeatOne,
        );
      }
    }

    await super.skipToPrevious();
  }

  Future<void> updateItemUrl(int index) async {
    // 1. 获取当前要播放的 MediaItem`
    final currentItem = _queue[index];
    // 2. 获取当前 MediaItem 的 ID
    final dynamicUrl = await _repo.fetchSongUrl(currentItem.id);

    // 4. 将获取到的URL更新到 MediaItem 的 extras 中
    final updatedItem = currentItem.copyWith(
      extras: {
        ...?currentItem.extras, // 保留原有的 extras 数据
        'url': dynamicUrl,
      },
    );
    // 5. 更新队列中的 MediaItem
    _queue[index] = updatedItem;
  }

  Future<void> notifyAndPlay({
    required int index,
    required bool isPlayAtRepeatOne,
  }) async {
    switch (_playOrder) {
      case PlayOrder.repeatOne:
        if (isPlayAtRepeatOne) {
          await updateItemUrl(index); // 更新当前播放项的 URL
          await prepareFromUri(
            Uri.parse(_queue[index].extras!['url'] as String),
          );
          mediaItem.add(_queue[index]);
        } else {
          await seek(Duration.zero);
        }
        break;
      case PlayOrder.shuffle:
      case PlayOrder.sequential:
        await updateItemUrl(index); // 更新当前播放项的 URL
        await prepareFromUri(Uri.parse(_queue[index].extras!['url'] as String));
        mediaItem.add(_queue[index]);
        break;
    }
    await play();
  }

  Future<void> setPlayOrder(PlayOrder order) async {
    _playOrder = order;
    if (order == PlayOrder.shuffle) {
      _shuffleQueueIndex = List.generate(_queue.length, (index) => index);
      _shuffleQueueIndex.shuffle();
    }
    for (int i = 0; i < _queue.length; i++) {
      if (_shuffleQueueIndex[i] == _currentIndex) {
        _shuffleIndex = i;
        break;
      }
    }
  }

  AudioPlayerHandler({required this._repo}) {
    // 订阅 AudioPlayer 的状态 → broadcast 给系统通知/锁屏
    // _audio.player.playerStateStream.listen(_broadcastState);
    // // 订阅当前歌曲变化 → broadcast mediaItem
    // _player.currentSong.listen(_broadcastMediaItem);
    // // 订阅队列变化 → broadcast queue
    // //_queue.playlist.listen(_broadcastQueue);
    // //_queue.currentIndex.listen(
    // //  (_) => _broadcastMediaItem(_player.currentSong.value),
    // //);
    // // 订阅喜欢状态变化 → 重建 controls (单按钮 toggle, 跟着 isLiked 切 like/dislike icon)
    // _player.isLiked.listen((_) => _resyncControls());
    // // 订阅歌曲变化也重建 controls (新歌 isLiked 状态不一样, like 按钮的 icon/label 要换)
    // _player.currentSong.listen((_) => _resyncControls());
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
      prev.copyWith(controls: _buildControls(isLiked: _player.isLiked.value)),
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
      song.toMediaItem(
        duration: _player.duration.value,
        artHeaders: NeteaseImageHeaders.neteaseImageHeaders,
      ),
    );
  }

  void _broadcastQueue(List<Song> songs) {
    queue.add(
      songs
          .map(
            (s) => s.toMediaItem(
              artHeaders: NeteaseImageHeaders.neteaseImageHeaders,
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

  @override
  Future<void> prepareFromUri(Uri uri, [Map<String, dynamic>? extras]) async {
    await _audio.setUrl(uri.toString());
  }

  @override
  Future<void> play() async {
    await _audio.play();
  }

  @override
  Future<void> pause() async {
    await _audio.pause();
  }

  @override
  Future<void> stop() async {
    await _audio.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await _audio.seek(position);
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
