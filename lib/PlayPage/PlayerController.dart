import 'package:flutter_lyric/flutter_lyric.dart';
import 'package:get/get.dart';

/// 播放页统一控制器:进度 + 切页 + 歌词
///
/// 把 flutter_lyric 的 [LyricController] 也托管在这里,
/// 避免歌词/进度条双源状态,保证点击歌词行的 seek 能直接驱动进度条。
class PlayerController extends GetxController {
  // region 播放状态
  /// 图片 / 歌词 切页索引
  final RxInt centerIndex = 0.obs;

  /// 当前播放位置(由 ProgressBar.onSeek / Lyric 点击行 / 后续 audio player 推动)
  final Rx<Duration> position = Duration.zero.obs;

  /// 歌曲总长度(由 audio player.durationStream 推动;默认 3 分钟占位)
  final Rx<Duration> duration = const Duration(minutes: 3).obs;
  // endregion

  // region 歌词
  /// 包装底层 flutter_lyric 控制器,供 [Lyrics] widget 使用
  final LyricController lyricController = LyricController();
  Worker? _positionWorker;

  // 占位 LRC(正式版由后端/解析器注入)
  static const String _sampleLrc = '''
[00:00.00]示例歌词第一行 - 欢迎使用
[00:05.00]这是第二行歌词
[00:10.00]第三行歌词在这里
[00:15.00]下面继续测试滚动效果
[00:20.00]第五行,看看高亮
[00:25.00]第六行,继续
[00:30.00]第七行歌词内容
[00:35.00]第八行,看看还能不能滚
[00:40.00]第九行,接近末尾
[00:45.00]第十行,快结束了
[00:50.00]倒数第二行
[00:55.00]最后一首歌词行
''';
  // endregion

  @override
  void onInit() {
    super.onInit();
    lyricController.loadLyric(_sampleLrc);

    // 进度推进 → 歌词高亮 + 自动滚动
    _positionWorker = ever<Duration>(position, lyricController.setProgress);

    // 点击歌词行 → seek(直接改 position,进度条自动跟随)
    lyricController.setOnTapLineCallback((Duration p) {
      updatePosition(p);
    });
  }

  @override
  void onClose() {
    _positionWorker?.dispose();
    lyricController.dispose();
    super.onClose();
  }

  /// 由 ProgressBar.onSeek 或底层 audio player 调用
  void updatePosition(Duration p) => position.value = p;

  /// 由 audio player.durationStream 推动
  void updateDuration(Duration d) => duration.value = d;

  void switchPage() => centerIndex.value = centerIndex.value == 0 ? 1 : 0;
}

class PlayerBinding extends Bindings {
  @override
  void dependencies() => Get.lazyPut(() => PlayerController());
}
