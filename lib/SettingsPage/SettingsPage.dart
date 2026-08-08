import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'LoginController.dart';
import 'LoginPage.dart';
import 'ThemeSwitcher.dart';

/// 设置 tab 内容(放进 app_shell 的 IndexedStack)。
/// 父级 IndexedStack 必须被 Expanded 包裹 —— 否则 Column 的主轴给的是
/// 0..Infinity,ListView 里的 RenderViewport 拿到 unbounded height 报错。
class Settings extends StatelessWidget {
  const Settings({super.key});

  /// 跳登录页入口:跟 AppShell tab 切换同款 Get.to(binding:) 模式
  static void _openLogin() =>
      Get.to(() => const LoginPage(), binding: LoginPageBinding());

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        // 登录账号入口:stub 阶段只是跳过去再跳回来,接 SDK 后这里再分
        // "未登录 → 登录账号" / "已登录 → 退出登录" 双态
        ListTile(
          leading: const Icon(Icons.account_circle_outlined),
          title: const Text('登录账号'),
          subtitle: const Text('手机号 + 验证码'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _openLogin,
        ),
        const ListTile(
          leading: Icon(Icons.brightness_6_outlined),
          title: Text('主题'),
          subtitle: Text('跟随系统 / 浅色 / 深色'),
          trailing: ThemeSwitcher(),
        ),
      ],
    );
  }
}
