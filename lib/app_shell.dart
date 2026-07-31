import 'package:flutter/material.dart';
import 'package:flutter_netease_music/PlayPage/BottomPlayer.dart';
import 'package:get/get.dart';
import 'package:responsive_builder/responsive_builder.dart';

import 'HomePage/HomePage.dart';
import 'LibraryPage/LibraryPage.dart';
import 'PlayPage/BottomPlayer.dart';
import 'SettingsPage/settings.dart';
import 'app_shell_controller.dart';
import 'searchPage/searchPage.dart';

/// 顶层 Scaffold,IndexedStack 那一格换成 Navigator。
/// 切 tab 用 GetX:Get.to() + id 推到 shell 自己的 navigator。
/// tab 状态完全交给 GetxController(AppShellController),本类 StatelessWidget。
/// 主体布局用 responsive_builder 按屏幕宽度切 flex 值。
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  /// AppShell 这一层 Navigator 在 Get 中的 id,跟 Settings 的内嵌 id 区分
  static const int shellNavigatorId = 0;

  static const _titles = ['发现', '搜索', '我的', '设置'];

  /// 按 index 返回 tab 内容
  static Widget _content(int i) {
    switch (i) {
      case 0:
        return const HomePage();
      case 1:
        return const SearchPage();
      case 2:
        return const LibraryPage();
      case 3:
        return const Settings();
    }
    return const HomePage();
  }

  /// shell 这一层的 Navigator,内容跟着 tab index 走
  static Widget _navigator(int i) {
    return Navigator(
      key: Get.nestedKey(shellNavigatorId),
      initialRoute: '/',
      onGenerateRoute: (settings) {
        if (settings.name == '/') {
          return GetPageRoute(page: () => _content(i));
        }
        return null;
      },
    );
  }

  /// 按屏幕朝向走不同 flex 配置
  /// - portrait:Navigator 用 Expanded 吃剩余高度,BottomPlay 自身高度
  /// - landscape:Navigator flex=4,BottomPlay flex=1(横屏播放器按比例拉大)
  static Widget _responsiveBody(int i) {
    return OrientationLayoutBuilder(
      portrait: (_) => Column(
        children: [
          Expanded(child: _navigator(i)),
          const BottomPlayer(),
        ],
      ),
      landscape: (_) => Column(
        children: [
          Expanded(flex: 4, child: _navigator(i)),
          const Expanded(flex: 1, child: BottomPlayer()),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tab = Get.find<AppShellController>();

    return Obx(() {
      final i = tab.index.value.clamp(0, 3);
      return Scaffold(
        appBar: AppBar(title: Text(_titles[i])),
        body: _responsiveBody(i),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: i,
          onTap: (j) {
            if (j == i) return;
            tab.change(j);
            // 用 GetX 的导航 API 推到 shell 自己的 navigator
            Get.to(() => _content(j.clamp(0, 3)), id: shellNavigatorId);
          },
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.explore_outlined),
              activeIcon: Icon(Icons.explore),
              label: '发现',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.search_outlined),
              activeIcon: Icon(Icons.search),
              label: '搜索',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.library_music_outlined),
              activeIcon: Icon(Icons.library_music),
              label: '我的',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              activeIcon: Icon(Icons.settings),
              label: '设置',
            ),
          ],
        ),
      );
    });
  }
}
