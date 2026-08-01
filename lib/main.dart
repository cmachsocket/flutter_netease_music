import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import 'AppShell.dart';
import 'AppShellController.dart';
import 'PlayPage/PlayerController.dart';
import 'theme/AppTheme.dart';
import 'theme/ThemeController.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GetStorage.init();
  Get.lazyPut(() => ThemeController());
  Get.lazyPut(() => AppShellController());
  // 全局播放状态:AppShell 的 BottomPlayer 一启动就要能 find 到
  Get.lazyPut(() => PlayerController());
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
