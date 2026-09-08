import 'package:flutter/material.dart';

class LongPressDialog extends StatelessWidget {
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
