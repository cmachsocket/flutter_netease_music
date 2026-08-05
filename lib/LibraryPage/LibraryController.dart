import 'package:flutter/material.dart';
import 'package:get/get.dart';

class LibraryController extends GetxController {
  final tabIndex = 1.obs;

  void setTabIndex(int index) {
    tabIndex.value = index;
  }
}
