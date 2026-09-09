import 'dart:async';

import 'package:get/get.dart';

/// 全局播放列表事件中心。
///
/// **为什么用 EventBus**:歌单曲目变化(`addTracks` / `removeTracks` /
/// `deletePlaylist`)是跨页面事件 —— LongPressDialog 加完歌后,
/// LibraryPage / HomePage 等所有显示同一歌单 trackCount 的地方都要更新。
///
/// **事件类型**(目前只一个,后续可加):
/// - [PlaylistTrackChangedEvent] — 歌单曲目数 delta,所有监听者按 playlistId 过滤
///
/// **设计**:
/// - 单例 `Get.find<PlaylistEventsController>()`(不挂 tag)
/// - 每个 playlistId 对应一个 `RxInt delta`(默认 0)
/// - `applyDelta(playlistId, n)` 累加 delta + emit 事件
/// - `deltaFor(playlistId)` 让 widget 读当前 delta
///
/// **生命周期**:全局 singleton,跟 app 同寿,不主动 dispose。
class PlaylistEventsController extends GetxController {
  /// 每个 playlistId 的本地 delta(累加:后端成功 +1 / -1 后写入这里,
  /// widget 读 trackCount 时把 base count + delta 显示)
  final RxMap<String, int> _deltas = <String, int>{}.obs;

  /// 变更广播(给那些不想用 Obx 想用 StreamBuilder 的 widget 用)。
  /// 不依赖这个也能用 `_deltas.value` 的 Obx 监听。
  final StreamController<PlaylistTrackChangedEvent> _trackChangedCtrl =
      StreamController<PlaylistTrackChangedEvent>.broadcast();

  /// 监听 track count 变化(任何 playlistId,widget 自己过滤)。
  Stream<PlaylistTrackChangedEvent> get onTrackChanged =>
      _trackChangedCtrl.stream;

  /// 读取指定 playlistId 当前本地 delta。
  /// widget 调用时包 Obx 就能响应 delta 变化。
  int deltaFor(String playlistId) => _deltas[playlistId] ?? 0;

  /// 应用一个 delta(累加)。n>0 = 加歌,n<0 = 减歌,n=0 = 删除歌单(归零)。
  ///
  /// 重复应用同一个 playlistId 会累加,不会覆盖 —— 多次 addTracks(+1,+1,+1)
  /// 显示为 +3,符合用户直觉。
  void applyDelta(String playlistId, int n) {
    if (n == 0) return;
    _deltas[playlistId] = (_deltas[playlistId] ?? 0) + n;
    _trackChangedCtrl.add(
      PlaylistTrackChangedEvent(playlistId: playlistId, delta: n),
    );
  }

  /// 重置某个 playlistId 的 delta(例如 LibraryController.reload 后,
  /// 重新从后端拿到 base count,本地 delta 应该清零 —— widget 会拿最新
  /// base count 重新显示)。
  void resetDelta(String playlistId) {
    _deltas[playlistId] = 0;
  }

  @override
  void onClose() {
    _trackChangedCtrl.close();
    super.onClose();
  }
}

/// 歌单曲目数变化事件。
class PlaylistTrackChangedEvent {
  const PlaylistTrackChangedEvent({
    required this.playlistId,
    required this.delta,
  });
  final String playlistId;
  final int delta;
}
