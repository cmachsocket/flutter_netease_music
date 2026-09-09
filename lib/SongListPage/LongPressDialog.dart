import 'package:flutter/material.dart';
import '../models/Song.dart';
import 'package:get/get.dart';
import '../models/LibrarySummary.dart' show PlaylistSource;

class LongPressDialog extends StatelessWidget {
  const LongPressDialog({
    super.key,
    required this.song,
    required this.index,
    required this.source,
    required this.playlistId,
  });
  final Song song;
  final int index;
  final PlaylistSource source;
  final String? playlistId;
  //占位
  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<LongPressDialogController>()) {
      Get.put(
        LongPressDialogController(
          song: song,
          index: index,
          source: source,
          playlistId: playlistId,
        ),
      );
    }
    final controller = Get.find<LongPressDialogController>();
    return Dialog(
      child: Obx(() {
        return controller.isChooseToAdd.value == false
            ? Column(
                children: [
                  ListTile(title: Text('添加到歌单')),
                  if (source == PlaylistSource.created && playlistId != null)
                    ListTile(title: Text('从歌单中删除')),
                  ListTile(title: Text('添加到播放队列')),
                ],
              )
            : Column(children: [ListTile(title: Text('选择歌单'))]);
      }),
    );
  }
}

class LongPressDialogController extends GetxController {
  LongPressDialogController({
    required this.song,
    required this.index,
    required this.source,
    required this.playlistId,
  });
  final Song song;
  final int index;
  final PlaylistSource source;
  final String? playlistId;
  final RxBool isChooseToAdd = false.obs;
  void onAddToPlaylist(Song song) {}
}
