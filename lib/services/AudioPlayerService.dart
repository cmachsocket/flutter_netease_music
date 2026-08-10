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
  Future<void> setUrl(String url) => player.setUrl(url);

  Future<void> play() => player.play();
  Future<void> pause() => player.pause();
  Future<void> stop() => player.stop();
  Future<void> seek(Duration position) => player.seek(position);
  @override
  void onInit() {
    super.onInit();
    JustAudioMediaKit.ensureInitialized();
  }

  @override
  void onClose() {
    player.dispose();
    super.onClose();
  }
}
