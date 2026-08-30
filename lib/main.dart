import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import 'AppShell.dart';
import 'AppShellController.dart';
import 'PlayPage/LyricsController.dart';
import 'PlayPage/PlayerController.dart';
import 'services/AudioPlayerService.dart';
import 'services/LyricsService.dart';
import 'services/PlaybackService.dart';
import 'services/PlayQueueService.dart';
import 'sdk/netease_api.dart';
import 'services/LikedSongsService.dart';
import 'services/LikedAlbumsService.dart';
import 'services/LikedArtistsService.dart';
import 'services/LikedPlaylistsService.dart';
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
  // services 除外:仍然在启动时创建,controller 交给各组件自己的 binding
  Get.put<PlayQueueService>(PlayQueueService(), permanent: true);
  Get.put<AudioPlayerService>(AudioPlayerService(), permanent: true);
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
  // Liked 4 个 service 现在都继承 LikedCollectionService 基类 (构造接 NeteaseApi),
  // API 调用走对应的 Repository。
  Get.put<LikedSongsService>(LikedSongsService(), permanent: true);
  Get.put<LikedAlbumsService>(LikedAlbumsService(), permanent: true);
  Get.put<LikedArtistsService>(LikedArtistsService(), permanent: true);
  Get.put<LikedPlaylistsService>(LikedPlaylistsService(), permanent: true);
  // PlayerController 必须在 AudioService.init 之前 put,
  // 因为 PlaybackService 内部 Get.find<PlayerController>() 依赖它存在

  // LyricsService 内部 Get.find<LyricsRepository>, 上面 Repository 已 put
  Get.put<LyricsService>(LyricsService(), permanent: true);
  Get.put<PlayerController>(PlayerController(), permanent: true);
  // LyricsController 依赖 PlayerController (订阅 currentSong) + LyricsService (拉歌词).
  // 注册顺序: LyricsService → PlayerController → LyricsController.
  // permanent: true 是为了 LyricController 跨 PlayPage 路由活 (跟 PlayerController 同生命周期),
  // 保证 Lyrics widget 任何时候 mount 都能从 lyricNotifier.value 拿到当前 lyric.
  Get.put<LyricsController>(LyricsController(), permanent: true);
  // LyricsService 依赖 PlayerController (订阅 currentSong 自动拉歌词),
  // audio_service: 初始化后台播放 handler
  // - 必须在 WidgetsFlutterBinding.ensureInitialized() 之后 (官方文档要求)
  // - 必须在 AudioPlayerService 注册之后 (PlaybackService 内部 Get.find 依赖)
  // - builder 返回 PlaybackService 实例, AudioService.init 内部会立刻实例化一次
  //   然后把它作为 AudioHandler 暴露给 native 侧
  final playback = await AudioService.init<PlaybackService>(
    builder: () => PlaybackService(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.flutter_netease_music.audio',
      androidNotificationChannelName: '网易云音乐播放',
      androidNotificationOngoing: true,
    ),
  );
  // 把 handler 也通过 Get 暴露给业务层(单例)
  Get.put<PlaybackService>(playback, permanent: true);
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
