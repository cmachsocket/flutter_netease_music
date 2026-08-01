import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'Lyrics.dart';

class Player extends StatelessWidget {
  const Player({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      child: Column(
        children: [
          GestureDetector(
            onTap: () {},
            child: Obx(
              () => IndexedStack(
                index: 0,
                children: [
                  Image(
                    //todo: bind to actual cover
                    image: NetworkImage(
                      'https://cdn.jsdelivr.net/gh/cmachsocket/resources/avatar.png',
                    ),
                    fit: BoxFit.cover,
                  ),
                  Lyrics(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
