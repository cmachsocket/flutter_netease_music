import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../widgets/aspect_driven_grid.dart';
import '../widgets/SongListCard.dart';
import 'LibraryController.dart';

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  // tabIndex -> 中文标签:三个 tab 都复用 SongListCard,只换 title 让用户看得到切了
  static const _labelOf = {1: '歌单', 2: '专辑', 3: '艺人'};

  @override
  Widget build(BuildContext context) {
    // 列数 / 间距 / item 比例全部从容器宽高比派生,零硬编码
    final controller = Get.find<LibraryController>();

    return Obx(() {
      final tab = controller.tabIndex.value;
      final label = _labelOf[tab] ?? _labelOf[1]!;
      return Column(
        children: [
          SegmentedButton(
            segments: const [
              ButtonSegment(
                label: Text("歌单"),
                icon: Icon(Icons.playlist_play),
                value: 1,
              ),
              ButtonSegment(
                label: Text("专辑"),
                icon: Icon(Icons.album),
                value: 2,
              ),
              ButtonSegment(
                label: Text("艺人"),
                icon: Icon(Icons.person),
                value: 3,
              ),
            ],
            selected: {tab},
            onSelectionChanged: (s) => controller.setTabIndex(s.first),
          ),
          Expanded(
            child: AspectDrivenGrid(
              // key 跟 tab 走:切 tab 时 Flutter 把 grid 当成新实例,
              // 丢弃旧 list state / scroll position / image cache
              key: ValueKey(tab),
              minColumns: 2,
              itemCount: 10,
              itemBuilder: (context, index) {
                return SongListCard(
                  playlistId: 'tab-$tab-$index',
                  title: '$label $index',
                  subtitle: 'xx首歌曲',
                  imageUrl:
                      'https://cdn.jsdelivr.net/gh/cmachsocket/resources/avatar.png',
                );
              },
            ),
          ),
        ],
      );
    });
  }
}
