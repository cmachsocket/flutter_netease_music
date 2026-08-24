import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../theme/ThemeController.dart';

/// 设置页用的三段主题切换器
/// 使用 ToggleButtons 替代 SegmentedButton 以解决 Android 渲染黑屏问题
class ThemeSwitcher extends StatelessWidget {
  const ThemeSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Get.find<ThemeController>();
    return Obx(() {
      final current = theme.mode.value;
      return ToggleButtons(
        isSelected: [
          current == ThemeMode.system,
          current == ThemeMode.light,
          current == ThemeMode.dark,
        ],
        onPressed: (index) {
          final modes = [ThemeMode.system, ThemeMode.light, ThemeMode.dark];
          theme.set(modes[index]);
        },
        children: const [
          Icon(Icons.brightness_auto),
          Icon(Icons.light_mode),
          Icon(Icons.dark_mode),
        ],
      );
    });
  }
}
