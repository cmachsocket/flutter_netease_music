import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

/// just_audio 的全局单例 + 公共流
///
/// - **持有** [AudioPlayer] 实例(整个 app 共用,跟 [NeteaseApi] 同款 GetxService)
/// - **暴露** [positionStream] / [durationStream] / [playingStream] /
///   [bufferedPositionStream] / [playerStateStream] 给 controller 订阅
/// - **API** 走 `setUrl(url)` 加载流(URL 是从 /song/url 拿到的临时 mp3 直链),
///   不要传 NetEase API SDK 的 Song 对象,保持 AudioPlayer 跟业务解耦
///
/// **为什么不用 audio_service**:
/// - 暂时只需要 in-app 播放(锁屏/通知控制下一轮加)
/// - just_audio 本身能正常 stream + play/pause/seek,够用
class AudioPlayerService extends GetxService {
  final AudioPlayer player = AudioPlayer();

  /// 当前播放位置 stream(订阅它写 PlayerController.position)
  Stream<Duration> get positionStream => player.positionStream;

  /// 当前歌曲总时长 stream
  Stream<Duration?> get durationStream => player.durationStream;

  /// 已缓冲位置 stream(给 ProgressBar 的 buffered 字段)
  Stream<Duration> get bufferedPositionStream => player.bufferedPositionStream;

  /// 是否正在播放 stream
  Stream<bool> get playingStream => player.playingStream;

  /// 播放器状态 stream —— processingState 变 completed 时触发自动切下一首
  Stream<PlayerState> get playerStateStream => player.playerStateStream;

  /// 加载一首新歌(URL 是 /song/url 返回的临时 mp3 直链)
  Future<void> setUrl(String url) async {
    // Android/just_audio_media_kit 下 completed 事件依赖 playlistMode == none。
    // 防御性关闭 loop，避免任何路径把 playlistMode 改成 single/loop 导致
    // media_kit.completed 无法转成 ProcessingState.completed。
    await player.setLoopMode(LoopMode.off);
    await player.setUrl(url);
  }

  Future<void> play() async {
    await player.play();
  }

  Future<void> pause() async {
    await player.pause();
  }

  Future<void> stop() async {
    await player.stop();
  }

  Future<void> seek(Duration position) async {
    await player.seek(position);
  }
  @override
  void onInit() {
    super.onInit();
    // MediaKit 初始化是同步阻塞,放在 service onInit 里完成。
    // 后续 setUrl/play 直接用,不需要再 await ready(竞态源)。
    JustAudioMediaKit.ensureInitialized();
  }

  @override
  void onClose() {
    player.dispose();
    super.onClose();
  }
}
