import 'package:flutter/material.dart';
import 'SongListCard.dart';

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
              child: SongListCard(
                playlistId: 'daily',
                title: '每日推荐',
                subtitle: 'xx首歌曲',
                imageUrl:
                    'https://cdn.jsdelivr.net/gh/cmachsocket/resources/avatar.png',
              ),
            ),
            Expanded(
              child: SongListCard(
                playlistId: 'private-fm',
                title: '私人FM',
                subtitle: 'xx首歌曲',
                imageUrl:
                    'https://cdn.jsdelivr.net/gh/cmachsocket/resources/avatar.png',
              ),
            ),
          ],
        ),

        Text('推荐歌单', style: textTheme.titleLarge, textAlign: TextAlign.left),
        Expanded(
          child: ListView.builder(
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
