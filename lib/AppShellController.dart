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
    // HomeController 走这里:tab 0 是 AppShell 启动时的默认 tab,
    // AppShell._navigator(0) 用 raw Navigator 直接渲染 HomePage,
    // 不会走 Get.to(binding:),所以 per-tab 的 HomePageBinding 不会触发。
    // 必须在启动时这里 lazyPut,HomePage.build 才能 Get.find<HomeController>()。
    // HomePageBinding 作为 per-tab 兑底(切走再切回来时重新触发 dependencies)
    // ——两个注册点都允许(GetX lazyPut 同类型第二次会忽略)
  }
}
