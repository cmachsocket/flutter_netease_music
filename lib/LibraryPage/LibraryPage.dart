import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../widgets/aspect_driven_grid.dart';
import '../widgets/SongListCard.dart';
import 'LibraryController.dart';

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 列数 / 间距 / item 比例全部从容器宽高比派生，零硬编码
    final controller = Get.find<LibraryController>();
    return Column(
      children: [
        SegmentedButton(
          segments: const [
            ButtonSegment(
              label: Text("歌单"),
              icon: Icon(Icons.playlist_play),
              value: 1,
            ),
            ButtonSegment(label: Text("专辑"), icon: Icon(Icons.album), value: 2),
            ButtonSegment(
              label: Text("艺人"),
              icon: Icon(Icons.person),
              value: 3,
            ),
          ],
          selected: {controller.tabIndex.value},
          onSelectionChanged: (s) {
            controller.setTabIndex(s.first);
          },
        ),
        Expanded(
          child: AspectDrivenGrid(
            minColumns: 2,
            itemCount: 10,
            itemBuilder: (context, index) {
              return SongListCard(
                playlistId: 'recommended-$index',
                title: '我的收藏 $index',
                subtitle: 'xx首歌曲',
                imageUrl:
                    'https://cdn.jsdelivr.net/gh/cmachsocket/resources/avatar.png',
              );
            },
          ),
        ),
      ],
    );
  }
}
