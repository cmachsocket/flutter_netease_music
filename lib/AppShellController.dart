import 'package:get/get.dart';

import 'HomePage/HomeController.dart';

class AppShellController extends GetxController {
  final RxInt index = 0.obs;
  void change(int i) => index.value = i;
}

class AppShellBinding extends Bindings {
  @override
  void dependencies() {
    // 懒加载：只有被 Find 到时才创建
    Get.lazyPut<AppShellController>(() => AppShellController());
    Get.lazyPut<HomeController>(() => HomeController());
  }
}
