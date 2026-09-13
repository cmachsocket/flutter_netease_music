import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:file_picker/file_picker.dart';
import 'SettingsController.dart';
import '../models/Default.dart';

class DownloadPage extends StatelessWidget {
  const DownloadPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Get.back(id: DefaultValues.shellNavigatorId);
          },
        ),
        title: const Text('下载状态'),
      ),
      body: const Center(child: Text('下载页')),
    );
  }
}

class DownloadPathSwitcher extends StatelessWidget {
  const DownloadPathSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsCtrl = Get.find<SettingsController>();
    return IconButton(
      icon: const Icon(Icons.folder_open),
      onPressed: () async {
        String? selectedDirectory = await FilePicker.getDirectoryPath();
        if (selectedDirectory != null) {
          await settingsCtrl.setDownloadPath(selectedDirectory);
          Get.snackbar(
            '下载路径已更新',
            selectedDirectory,
            snackPosition: SnackPosition.BOTTOM,
          );
        }
      },
    );
  }
}
