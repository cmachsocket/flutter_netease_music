import 'package:get/get.dart';

import 'PlayPage/PlayerController.dart';
import 'PlayListPage/PlayListController.dart';

class AppShellController extends GetxController {
  final RxInt index = 0.obs;
  void change(int i) => index.value = i;
}

class AppShellBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<AppShellController>(() => AppShellController());
    Get.lazyPut<PlayerController>(() => PlayerController());
    Get.lazyPut<PlayListController>(() => PlayListController());
  }
}
