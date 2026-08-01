import 'package:get/get.dart';

class AppShellController extends GetxController {
  final RxInt index = 0.obs;
  void change(int i) => index.value = i;
}

class AppShellBinding extends Bindings {
  @override
  void dependencies() {
    // 懒加载：只有被 Find 到时才创建
    Get.lazyPut<AppShellController>(() => AppShellController());

    // 或者立即创建：Get.put(HomeController());
  }
}
