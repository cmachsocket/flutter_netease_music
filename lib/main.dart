import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import 'AppShell.dart';
import 'AppShellController.dart';
import 'PlayPage/PlayerController.dart';
import 'sdk/netease_api.dart';
import 'theme/AppTheme.dart';
import 'theme/ThemeController.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GetStorage.init();
  // Bootstrap binding:这些 controller 在 AppShell 一启动就要被 find,
  // 所以必须在 runApp 之前注入。route-level(比如 LibraryController)
  // 的 binding 在 Get.to(binding:) 时按需触发。
  Get.lazyPut(() => ThemeController());
  Get.lazyPut(() => AppShellController());
  Get.lazyPut(() => PlayerController());
  // 网易云 SDK:创建 NeteaseCloudMusicApi 实例 + 恢复持久化 cookie
  // (必须在 GetStorage.init 之后)
  await initNeteaseApi();
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
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: theme.mode.value,
        home: const AppShell(),
      ),
    );
  }
}
