import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import 'AppShell.dart';
import 'AppShellController.dart';
import 'PlayPage/LyricsController.dart';
import 'PlayPage/PlayerController.dart';
import 'services/NewAudioPlayerService.dart';
import 'sdk/netease_api.dart';
import 'services/LikedService.dart';
import 'services/repositories/lyrics_repository.dart';
import 'services/repositories/song_repository.dart';
import 'services/repositories/liked_repository.dart';
import 'services/repositories/search_repository.dart';
import 'services/repositories/playlist_repository.dart';
import 'services/repositories/album_repository.dart';
import 'services/repositories/artist_repository.dart';
import 'services/repositories/library_repository.dart';
import 'controller/AuthController.dart';
import 'theme/AppTheme.dart';
import 'theme/ThemeController.dart';
import 'widgets/netease_image.dart' show NeteaseHttpOverrides;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 全局 HttpClient UA 伪装:NetEase CDN 把 Dart 默认 UA 拉黑
  // (Image.network 的 headers 参数在 Android 不一定生效,直接 override 最稳)
  HttpOverrides.global = NeteaseHttpOverrides();
  await GetStorage.init();
  Get.put<ThemeController>(ThemeController(), permanent: true);
  // 网易云 SDK:创建 NeteaseCloudMusicApi 实例 + 恢复持久化 cookie
  // (必须在 GetStorage.init 之后)
  await initNeteaseApi();
  // Repositories 集中 API 调用 —— 必须在依赖它们的 service / controller 之前 put。
  // 构造注入 NeteaseApi, 注册顺序错误会编译期暴露 (README 阶段 1.1)。
  Get.put<LyricsRepository>(
    LyricsRepository(Get.find<NeteaseApi>()),
    permanent: true,
  );
  Get.put<SongRepository>(
    SongRepository(Get.find<NeteaseApi>()),
    permanent: true,
  );
  Get.put<SearchRepository>(
    SearchRepository(Get.find<NeteaseApi>()),
    permanent: true,
  );
  Get.put<PlaylistRepository>(
    PlaylistRepository(Get.find<NeteaseApi>()),
    permanent: true,
  );
  Get.put<AlbumRepository>(
    AlbumRepository(Get.find<NeteaseApi>()),
    permanent: true,
  );
  Get.put<ArtistRepository>(
    ArtistRepository(Get.find<NeteaseApi>()),
    permanent: true,
  );
  Get.put<LibraryRepository>(
    LibraryRepository(Get.find<NeteaseApi>()),
    permanent: true,
  );
  // AuthController 是全局凭证持有者 (lib/controller/), 持有 AuthInfo (cookie + loggedIn + uid)
  // 真正的 SDK 调用走 NeteaseApi, LoginController 等 UI 层从这里拿凭证
  await Get.putAsync<AuthController>(() async {
    final controller = AuthController();
    await controller.loadAuthInfo();
    return controller;
  }, permanent: true);
  Get.put<LikedRepository>(
    LikedRepository(Get.find<NeteaseApi>()),
    permanent: true,
  );
  // 单一 LikedService: 之前 4 个 service (Songs/Albums/Artists/Playlists) 都合并到这里,
  // 按 LikedType 分桶, API 调用走 LikedRepository
  Get.put<LikedService>(LikedService(), permanent: true);

  // ---- 音频服务层 (唯一入口) -----------------------------------------------
  // NewAudioPlayerService 把"PlayQueueService + 老 AudioPlayerService +
  // PlaybackService + LyricsService"四者吸收到一个 wrapper + handler:
  //   - 业务 API: playlist / currentIndex / mode / selectIndex / setMode /
  //     playSong / playSongs / removeSong / nextIndex / prevIndex / fetchLyric /
  //     invalidateLyric
  //   - 音频命令: play / pause / seek / skipToNext / skipToPrevious
  //   - 状态聚合: Rx<PlaybackSnapshot> (isPlaying/processingState/position/
  //     bufferedPosition/currentSong/queue/currentIndex/playOrder/isCurrentSongLiked)
  //   - 后台: AudioService.init 在 wrapper.onInit 里跑 (handler 内部负责
  //     audio_service + just_audio 桥接),单例 handler 暴露给锁屏/通知
  //
  // 注册顺序要求:
  //   1. Repository (SongRepository / LyricsRepository / LikedService) 在前
  //      (handler 构造依赖)
  //   2. wrapper 在 PlayerController 之前:playerController.onInit 会 Get.find 它
  //   3. PlayerController 在 LyricsController 之前:lyricsController 订阅 currentSong
  //   4. 用 putAsync 等 wrapper.onInit 完成(handler 构造 + GetStorage hydrate +
  //      5 路 stream 订阅就绪),否则 PlayerController.onInit 跟 wrapper.audioHandler
  //      有竞态 (handler 异步构造但 audioHandler 字段是 late)
  await Get.putAsync<AudioPlayerService>(() async {
    final wrapper = AudioPlayerService();
    // Get.putAsync 会等 onInit future 完成才 resolve
    return wrapper;
  }, permanent: true);

  Get.put<PlayerController>(PlayerController(), permanent: true);
  // LyricsController 依赖 PlayerController (订阅 currentSong) + wrapper.fetchLyric。
  // 注册顺序: wrapper → PlayerController → LyricsController。
  // permanent: true 是为了 LyricController 跨 PlayPage 路由活 (跟 PlayerController 同生命周期),
  // 保证 Lyrics widget 任何时候 mount 都能从 lyricNotifier.value 拿到当前 lyric.
  Get.put<LyricsController>(LyricsController(), permanent: true);

  runApp(const FlutterNeteaseMusicApp());
}

class FlutterNeteaseMusicApp extends StatelessWidget {
  const FlutterNeteaseMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Get.find<ThemeController>();
    return Obx(
      () => GetMaterialApp(
        title: 'Flutter Netease Music',
        debugShowCheckedModeBanner: false,
        initialBinding: AppShellBinding(),
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: theme.mode.value,
        home: const AppShell(),
      ),
    );
  }
}