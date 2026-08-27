import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import 'AppShell.dart';
import 'AppShellController.dart';
import 'PlayPage/PlayerController.dart';
import 'services/AudioPlayerService.dart';
import 'services/PlaybackService.dart';
import 'services/PlayQueueService.dart';
import 'sdk/netease_api.dart';
import 'services/LikedSongsService.dart';
import 'services/liked_albums_service.dart';
import 'services/liked_artists_service.dart';
import 'services/liked_playlists_service.dart';
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
  // LikedSongsService 依赖 NeteaseApi(调 /likelist / /like),必须 NeteaseApi 注册后才能 put
  Get.put<LikedSongsService>(LikedSongsService(), permanent: true);
  Get.put<LikedAlbumsService>(LikedAlbumsService(), permanent: true);
  Get.put<LikedArtistsService>(LikedArtistsService(), permanent: true);
  Get.put<LikedPlaylistsService>(LikedPlaylistsService(), permanent: true);
  // PlayerController 必须在 AudioService.init 之前 put,
  // 因为 PlaybackService 内部 Get.find<PlayerController>() 依赖它存在
  Get.put<PlayerController>(PlayerController(), permanent: true);
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
