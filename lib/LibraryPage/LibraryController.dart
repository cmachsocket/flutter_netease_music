import 'package:get/get.dart';

class LibraryController extends GetxController {
  final tabIndex = 1.obs;

  void setTabIndex(int index) {
    tabIndex.value = index;
  }
}

class LibraryBinding extends Bindings {
  @override
  void dependencies() => Get.lazyPut(() => LibraryController());
}
