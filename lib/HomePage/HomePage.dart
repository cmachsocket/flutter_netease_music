import 'package:flutter/material.dart';
import '../widgets/SongListCard.dart';

import '../widgets/aspect_driven_grid.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        Row(
          children: const [
            Expanded(
              child: TopSongListCard(
                playlistId: 'daily',
                title: '每日推荐',
                subtitle: 'xx首歌曲',
                imageUrl:
                    'https://cdn.jsdelivr.net/gh/cmachsocket/resources/avatar.png',
              ),
            ),
            Expanded(
              child: TopSongListCard(
                playlistId: 'private-fm',
                title: '私人雷达',
                subtitle: 'xx首歌曲',
                imageUrl:
                    'https://cdn.jsdelivr.net/gh/cmachsocket/resources/avatar.png',
              ),
            ),
          ],
        ),

        Text('推荐歌单', style: textTheme.titleLarge, textAlign: TextAlign.left),
        Expanded(
          child: AspectDrivenGrid(
            childAspectRatio: 0.8,
            minColumns: 2,
            itemCount: 10,
            itemBuilder: (context, index) {
              return SongListCard(
                playlistId: 'recommended-$index',
                title: '推荐歌单 $index',
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
