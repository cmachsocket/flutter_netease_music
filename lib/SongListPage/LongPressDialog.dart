import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../models/Song.dart';
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
    return AlertDialog(
      title: const Text('长按操作'),
      content: const Text('你长按了这个元素。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
