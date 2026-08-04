import 'package:flutter/material.dart';

import '../widgets/aspect_driven_grid.dart';
import '../widgets/SongListCard.dart';

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 列数 / 间距 / item 比例全部从容器宽高比派生，零硬编码
    return Column(
      children: [
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
