import 'package:flutter/material.dart';
import 'theme_switcher.dart';

/// Tab 内容(放进 app_shell 的 IndexedStack),不再自己包 Scaffold/AppBar,
/// 也不做嵌套命名路由 —— ThemeSwitcher 就直接挂在 ListTile 的 trailing。
class Settings extends StatelessWidget {
  const Settings({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: const [
        ListTile(
          title: Text('主题模式'),
          subtitle: Text('跟随系统 / 浅色 / 深色'),
          trailing: ThemeSwitcher(),
        ),
      ],
    );
  }
}
