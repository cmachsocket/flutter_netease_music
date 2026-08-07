import 'package:flutter/material.dart';
import 'package:get/get.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('登录')),
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            // 模拟登录成功，返回上一页
            Get.back();
          },
          child: const Text('登录'),
        ),
      ),
    );
  }
}
