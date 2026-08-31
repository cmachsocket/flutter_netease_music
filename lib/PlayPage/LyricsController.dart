import 'dart:async';

import 'package:flutter_lyric/flutter_lyric.dart';
import 'package:get/get.dart';

import '../models/Song.dart';
import '../services/NewAudioPlayerService.dart';

/// 歌词控制器 —— 直接订阅 [AudioPlayerService.snapshot] 拉歌词、推进度。
///
/// ## 依赖关系
///
/// **只依赖 [AudioPlayerService]**(音频 wrapper),不依赖 [PlayerController]。
///
/// 之前依赖 PlayerController 的原因:PlayerController 自己订阅 just_audio
/// stream 并维护 currentSong/position Rx,歌词想拿进度只能从那里读。但现在:
///   - 音频真相全部在 wrapper (snapshot.currentSong / snapshot.position)
///   - PlayerController 只是 wrapper 的 UI facade,本身不持有音频流
///
/// 既然 wrapper 已经直接暴露这些字段,LyricsController 不该再绕一层 facade
/// ——耦合 PlayerController 会导致:
///   1. 业务路径变长(UI → PlayerController → wrapper → handler → just_audio),
///      调试时不清楚该信哪一层的状态
///   2. LyricsController 跟 PlayerController 生命周期绑死(都 permanent: true
///      时不会出问题,但语义上歌词跟音频状态对齐,跟 UI facade 不该有依赖)
///
/// 改为直接订阅 wrapper.snapshot.stream,在回调里 diff 出 currentSong /
/// position 的变化,触发 lyric 加载 / 高亮推进。
///
/// 为什么不拆出 wrapper.currentSong / wrapper.position Rx:
///   - wrapper.snapshot 是单一真相,拆出 6+ 个 Rx 容易双写不同步
///   - 直接 stream.listen + 内部 diff 单测简单
///
/// 生命周期:
/// - **permanent: true** (main.dart 注册),跟 wrapper 同生命周期
/// - lyricController 实例跨切歌复用,跨页路由销毁
/// - permanent 是为了跨路由(从 PlayerPage 跳到 PlayListPage 再回来)LyricView
///   重新 mount 时能从 lyricNotifier.value 立刻拿到当前 lyric,不再重拉
class LyricsController extends GetxController {
  final LyricController lyricController = LyricController();

  final AudioPlayerService _audio = Get.find<AudioPlayerService>();

  /// 正在拉 lyric 的 song id (防止重复请求 — currentSong 流偶尔抖)
  String? _fetchingSongId;

  /// 当前持有的 lyric (UI 调试 / 备用 — flutter_lyric 主用 lyricNotifier)
  final Rxn<String> currentLyric = Rxn<String>();

  /// 上一次 snapshot 里的 currentSong / position,用于内部 diff 判断字段变化
  Song? _lastSong;
  Duration _lastPosition = Duration.zero;

  StreamSubscription<PlaybackSnapshot>? _snapshotSub;

  @override
  void onInit() {
    super.onInit();
    // 订阅 wrapper.snapshot 整体流,内部 diff 出当前歌 / 进度变化
    // snapshot 每次都 new 一份(PlayOrderSnapshot.copyWith),stream 等价 onChange,
    // 但我们只对 currentSong / position 字段变化感兴趣
    final initial = _audio.snapshot.value;
    _lastSong = initial.currentSong;
    _lastPosition = initial.position;
    _snapshotSub = _audio.snapshot.stream.listen(_onSnapshot);
    // 启动时主动触发一次(可能 wrapper 启动比 LyricsController 晚,
    // 初始 snapshot.currentSong 已经有值)
    _onSnapshot(initial);
    // 点击歌词行 → 直接 seek wrapper (不走 PlayerController facade)
    lyricController.setOnTapLineCallback(_audio.seek);
  }

  @override
  void onClose() {
    _snapshotSub?.cancel();
    super.onClose();
  }

  /// snapshot 变化 → diff 出 currentSong / position 的字段级变化
  ///
  /// - currentSong 变 → 拉新歌词(触发 _onCurrentSongChanged)
  /// - position 变 → 推送给 flutter_lyric 做高亮 + 自动滚动
  /// - 同首歌同个 position 不重复触发(GetX snapshot.copyWith 每次都 new 对象,
  ///   stream 会 fire 一次,但内部 diff 让 lyric setProgress 是幂等操作,
  ///   多 fire 几次没问题;真正重的"fetch lyric"用 _fetchingSongId 防抖)
  void _onSnapshot(PlaybackSnapshot s) {
    final song = s.currentSong;
    if (song?.id != _lastSong?.id) {
      _onCurrentSongChanged(song);
    }
    _lastSong = song;

    if (s.position != _lastPosition) {
      lyricController.setProgress(s.position);
    }
    _lastPosition = s.position;
  }

  /// 用户手动刷新当前歌词 (UI "重试"按钮)
  Future<void> refreshCurrent() async {
    final song = _audio.snapshot.value.currentSong;
    if (song == null) return;
    _audio.invalidateLyric(song.id);
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

    final lyric = await _audio.fetchLyric(songId);
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
}