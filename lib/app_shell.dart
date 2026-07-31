import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'app_shell_controller.dart';
import 'SettingsPage/settings.dart';

/// 顶层 Scaffold:AppBar 标题随 tab 切换,IndexedStack 占位。
/// 内容 tab 留空给各页面目录自行实现。
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  static const _titles = ['发现', '搜索', '我的', '设置'];

  @override
  Widget build(BuildContext context) {
    final tab = Get.find<AppShellController>();

    return Scaffold(
      appBar: AppBar(
        title: Obx(() {
          final i = tab.index.value.clamp(0, _titles.length - 1);
          return Text(_titles[i]);
        }),
      ),
      body: Obx(
        () => IndexedStack(
          index: tab.index.value,
          children: const [
            Center(child: Text('发现')),
            Center(child: Text('搜索')),
            Center(child: Text('我的')),
            Center(child: Settings()),
          ],
        ),
      ),
      bottomNavigationBar: Obx(
        () => BottomNavigationBar(
          currentIndex: tab.index.value,
          onTap: tab.change,
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
      ),
    );
  }
}
