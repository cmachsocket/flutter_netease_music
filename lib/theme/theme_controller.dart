import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

/// 全局主题模式(跟随系统 / 浅色 / 深色)
class ThemeController extends GetxController {
  static const _key = 'themeMode';
  final _box = GetStorage();

  late final Rx<ThemeMode> mode;

  @override
  void onInit() {
    super.onInit();
    final saved = _box.read<String>(_key);
    mode =
        (saved == null
                ? ThemeMode.system
                : ThemeMode.values.firstWhere(
                    (e) => e.name == saved,
                    orElse: () => ThemeMode.system,
                  ))
            .obs;
  }

  Future<void> set(ThemeMode m) async {
    mode.value = m;
    await _box.write(_key, m.name);
    Get.changeThemeMode(m); // 立刻全 app 切换,不用重启
  }
}
