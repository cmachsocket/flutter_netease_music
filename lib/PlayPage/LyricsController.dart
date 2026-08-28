import 'dart:async';

import 'package:flutter_lyric/flutter_lyric.dart';
import 'package:get/get.dart';

import '../models/Song.dart';
import '../services/LyricsService.dart';
import 'PlayerController.dart';

/// 歌词控制器 —— 把 [LyricsService.fetch] 的能力跟 [PlayerController.currentSong] 组合
///
/// 分层 (page → controller → service):
/// - **LyricsService**: 纯被动 API (fetch lyric string by song id, 带 cache)
/// - **LyricsController (这里)**: 监听 PlayerController.currentSong, 拉 lyric,
///   灌进 [lyricController] (flutter_lyric 的 LyricView 用)
/// - **Lyrics widget**: `Get.find<LyricsController>().lyricController` 拿
///
/// 为什么是 controller 不是 service:
/// - **要听 Rx** (currentSong) → controller 的职责
/// - **要 hold UI state** (LyricController 实例) → controller 的职责
/// - service 是被动的, 听 Rx 是 controller 主动订阅
///
/// 为什么是 permanent (跟 PlayerController 同 lifecycle):
/// - LyricController 实例跨路由活, 切歌时复用同一个 lyricController
/// - Lyrics widget 任何时候 mount 都能从 lyricNotifier 拿到当前 lyric
///   (修复"首次播放 lyrics 不加载"的关键 —— lyricController 在 widget mount 前就活了)
class LyricsController extends GetxController {
  final LyricController lyricController = LyricController();

  final PlayerController _player = Get.find<PlayerController>();
  final LyricsService _service = Get.find<LyricsService>();

  /// 正在拉 lyric 的 song id (防止重复请求 — PlayerController.currentSong
  /// 偶尔会快速连续 emit 两次同 id, 比如 seekbar 切换 + LyricsService 拉取之间)
  String? _fetchingSongId;

  /// 当前持有的 lyric (UI 调试 / 备用 — flutter_lyric 主用 lyricNotifier)
  final Rxn<String> currentLyric = Rxn<String>();

  @override
  void onInit() {
    super.onInit();
    // 监听当前播放歌曲变化 → 拉 lyric + 灌 lyricController
    _player.currentSong.listen(_onCurrentSongChanged);
    // 监听进度 → 歌词高亮 + 自动滚动
    ever<Duration>(_player.position, lyricController.setProgress);
    // 点击歌词行 → seek
    lyricController.setOnTapLineCallback((Duration p) {
      _player.seek(p);
    });
  }

  /// 用户手动刷新当前歌词 (UI "重试"按钮)
  Future<void> refreshCurrent() async {
    final song = _player.currentSong.value;
    if (song == null) return;
    _service.invalidate(song.id);
    await _loadLyricFor(song.id);
  }

  Future<void> _onCurrentSongChanged(Song? song) async {
    if (song == null) {
      _fetchingSongId = null;
      currentLyric.value = null;
      lyricController.loadLyric('');
      return;
    }
    await _loadLyricFor(song.id);
  }

  Future<void> _loadLyricFor(String songId) async {
    // 防抖: 快速连续两次同一首不重拉 (currentSong 流偶尔抖)
    if (_fetchingSongId == songId) return;
    _fetchingSongId = songId;

    final lyric = await _service.fetch(songId);
    // 期间可能切歌了 → 只对当前 songId 灌结果
    if (_fetchingSongId != songId) return;

    if (lyric == null) {
      currentLyric.value = null;
      lyricController.loadLyric('');
      return;
    }
    currentLyric.value = lyric;
    lyricController.loadLyric(lyric);
  }

  @override
  void onClose() {
    lyricController.dispose();
    super.onClose();
  }
}
