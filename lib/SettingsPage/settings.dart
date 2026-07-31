import 'package:flutter/material.dart';
import 'theme_switcher.dart';

/// 设置 tab 内容(放进 app_shell 的 IndexedStack)。
/// 父级 IndexedStack 必须被 Expanded 包裹 —— 否则 Column 的主轴给的是
/// 0..Infinity,ListView 里的 RenderViewport 拿到 unbounded height 报错。
class Settings extends StatelessWidget {
  const Settings({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: const [
        ListTile(
          leading: Icon(Icons.brightness_6_outlined),
          title: Text('主题'),
          subtitle: Text('跟随系统 / 浅色 / 深色'),
          trailing: ThemeSwitcher(),
        ),
      ],
    );
  }
}
