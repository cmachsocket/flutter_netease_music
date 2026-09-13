import 'package:flutter/material.dart';
import 'package:get/get.dart';
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
