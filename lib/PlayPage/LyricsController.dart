import 'dart:async';

import 'package:flutter_lyric/flutter_lyric.dart';
import 'package:get/get.dart';

import '../models/Song.dart';
import '../services/NewAudioPlayerService.dart';
import 'PlayerController.dart';

/// 歌词控制器 —— 监听 [PlayerController.currentSong],通过 wrapper
/// ([AudioPlayerService.fetchLyric]) 拉歌词,灌进 flutter_lyric 的 [lyricController]
///
/// 上层不再直接 Get.find<LyricsService> — LyricsService 已删,所有音频相关
/// API 走 wrapper。
///
/// 生命周期:
/// - **跟 PlayPage widget 走** (per-tab Get.lazyPut in HomePageBinding 这套
///   GetxController 创建/销毁模式) — 不再 permanent
/// - lyricController 实例跨切歌复用,但跨页路由销毁
class LyricsController extends GetxController {
  final LyricController lyricController = LyricController();

  final PlayerController _player = Get.find<PlayerController>();
  final AudioPlayerService _player2 = Get.find<AudioPlayerService>();

  /// 正在拉 lyric 的 song id (防止重复请求 — currentSong 流偶尔抖)
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
    _player2.invalidateLyric(song.id);
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
    // 防抖: 快速连续两次同一首不重拉
    if (_fetchingSongId == songId) return;
    _fetchingSongId = songId;

    final lyric = await _player2.fetchLyric(songId);
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
