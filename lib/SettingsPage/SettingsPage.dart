import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../sdk/netease_api.dart';
import 'LoginController.dart' show LoginPageBinding;
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

  /// 退出登录入口(已登录态才显示):直接走 [NeteaseApi.logout],
  /// 不依赖 LoginController(用户可能从没进过 LoginPage,LoginController 未注入)
  static void _doLogout() {
    Get.find<NeteaseApi>().logout();
    Get.snackbar('已退出', '本地登录态已清除', snackPosition: SnackPosition.BOTTOM);
  }

  @override
  Widget build(BuildContext context) {
    final api = Get.find<NeteaseApi>();
    return ListView(
      children: [
        const ListTile(
          leading: Icon(Icons.brightness_6_outlined),
          title: Text('主题'),
          subtitle: Text('跟随系统 / 浅色 / 深色'),
          trailing: ThemeSwitcher(),
        ),

        // 登录账号:已登录 → "已登录 (退出)" / 未登录 → "登录账号"
        Obx(
          () => ListTile(
            leading: Icon(
              api.loggedIn.value
                  ? Icons.account_circle
                  : Icons.account_circle_outlined,
            ),
            title: Text(api.loggedIn.value ? '已登录' : '登录账号'),
            subtitle: Text(
              api.loggedIn.value
                  ? '本地登录态已保存,点击退出'
                  : '手机号 + 验证码',
            ),
            trailing: api.loggedIn.value
                ? const Icon(Icons.logout)
                : const Icon(Icons.chevron_right),
            onTap: () =>
                api.loggedIn.value ? _doLogout() : _openLogin(),
          ),
        ),
      ],
    );
  }
}