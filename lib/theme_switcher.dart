import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'theme/theme_controller.dart';

/// 设置页用的三段主题切换器
class ThemeSwitcher extends StatelessWidget {
  const ThemeSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Get.find<ThemeController>();
    return Obx(() => SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(
              value: ThemeMode.system,
              icon: Icon(Icons.brightness_auto),
              label: Text('跟随系统'),
            ),
            ButtonSegment(
              value: ThemeMode.light,
              icon: Icon(Icons.light_mode),
              label: Text('浅色'),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              icon: Icon(Icons.dark_mode),
              label: Text('深色'),
            ),
          ],
          selected: {theme.mode.value},
          onSelectionChanged: (s) => theme.set(s.first),
        ));
  }
}
