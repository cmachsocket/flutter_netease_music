import 'package:get/get.dart';

import 'LyricsController.dart';

class PlayerController extends GetxController {
  final RxInt centerIndex = 0.obs;
  /// 当前播放位置(由进度条 onSeek / 后续 audio player 推动)
  final Rx<Duration> position = Duration.zero.obs;

  void switchPage() => centerIndex.value = centerIndex.value == 0 ? 1 : 0;

  /// 由 ProgressBar.onSeek 或底层 audio player 调用
  void updatePosition(Duration p) {
    position.value = p;
  }
}

class PlayerBinding extends Bindings {
  @override
  void dependencies() {
    // Player 必先于 Lyrics(后者依赖前者的 position)
    Get.lazyPut<PlayerController>(() => PlayerController());
    Get.lazyPut<LyricsController>(() => LyricsController());
  }
}

// 复用旧版绑定风格注释
// 或立即创建:Get.put(HomeController());