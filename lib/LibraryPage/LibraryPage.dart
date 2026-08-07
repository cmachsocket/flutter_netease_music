import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../AppShell.dart';
import '../ArtistPage/ArtistController.dart';
import '../ArtistPage/ArtistDetail.dart';
import '../widgets/aspect_driven_grid.dart';
import '../SongListPage/SongListCard.dart';
import 'LibraryController.dart';

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  // tabIndex -> 中文标签:歌单 / 专辑 / 艺人
  // 专辑 tab 暂时也复用 SongListCard 默认导航(stub 阶段);等 AlbumDetail 出来再单独 override
  static const _labelOf = {1: '歌单', 2: '专辑', 3: '艺人'};

  @override
  Widget build(BuildContext context) {
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
                final id = 'tab-$tab-$index';
                return SongListCard(
                  playlistId: id,
                  title: '$label $index',
                  subtitle: 'xx首歌曲',
                  imageUrl:
                      'https://cdn.jsdelivr.net/gh/cmachsocket/resources/avatar.png',
                  // 艺人 tab 走 ArtistDetail,其他 tab 走 SongListCard 默认导航
                  onTap: tab == 3 ? () => _openArtist(id) : null,
                );
              },
            ),
          ),
        ],
      );
    });
  }

  /// 艺人卡片点击:推到 AppShell 的嵌套 Navigator,绑定 ArtistController(路由 pop 时自动销毁)
  void _openArtist(String artistId) {
    Get.to(
      () => ArtistDetail(artistId: artistId),
      id: AppShell.shellNavigatorId,
      binding: ArtistDetailBinding(artistId: artistId),
    );
  }
}
