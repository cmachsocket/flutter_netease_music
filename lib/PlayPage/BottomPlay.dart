import 'package:flutter/material.dart';
import 'package:get/get.dart';

class BottomPlay extends StatelessWidget {
  const BottomPlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(icon: const Icon(Icons.skip_previous), onPressed: () {}),
          IconButton(icon: const Icon(Icons.play_arrow), onPressed: () {}),
          IconButton(icon: const Icon(Icons.skip_next), onPressed: () {}),
        ],
      ),
    );
  }
}
