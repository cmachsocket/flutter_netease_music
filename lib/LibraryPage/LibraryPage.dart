import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../AppShell.dart';
import '../ArtistPage/ArtistDetail.dart';
import '../SongListPage/SongListDetail.dart';
import '../SongListPage/SongListCard.dart';
import '../sdk/netease_api.dart';
import '../widgets/aspect_driven_grid.dart';
import 'LibraryController.dart';

/// 我的 tab 内容
///
/// 三个 tab 都需登录。未登录展示"请先登录"占位,登录后按 tab 走对应 SDK 接口
class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  static const Map<int, String> _labelOf = {
    1: '歌单',
    2: '专辑',
    3: '艺人',
  };

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
                label: Text('歌单'),
                icon: Icon(Icons.playlist_play),
                value: 1,
              ),
              ButtonSegment(
                label: Text('专辑'),
                icon: Icon(Icons.album),
                value: 2,
              ),
              ButtonSegment(
                label: Text('艺人'),
                icon: Icon(Icons.person),
                value: 3,
              ),
            ],
            selected: {tab},
            onSelectionChanged: (s) => controller.setTabIndex(s.first),
          ),
          Expanded(child: _TabContent(tab: tab, label: label)),
        ],
      );
    });
  }
}

/// 各 tab 的具体内容(包含未登录占位)
class _TabContent extends StatelessWidget {
  const _TabContent({required this.tab, required this.label});

  final int tab;
  final String label;

  @override
  Widget build(BuildContext context) {
    final api = Get.find<NeteaseApi>();
    return Obx(() {
      if (!api.loggedIn.value) {
        return const _LoginRequiredHint();
      }
      switch (tab) {
        case 1:
          return _PlaylistsView();
        case 2:
          return _AlbumsView();
        case 3:
          return _ArtistsView();
      }
      return _PlaylistsView();
    });
  }
}

/// "请先登录"占位卡
class _LoginRequiredHint extends StatelessWidget {
  const _LoginRequiredHint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: ListTile(
          leading: const Icon(Icons.login),
          title: const Text('登录后查看我的歌单 / 专辑 / 艺人'),
          subtitle: const Text('点底部「我」tab 进入设置 → 登录账号'),
        ),
      ),
    );
  }
}

/// 歌单 grid
class _PlaylistsView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = Get.find<LibraryController>();
    return Obx(() {
      if (c.playlistsLoading.value) {
        return const Center(child: CircularProgressIndicator());
      }
      if (c.playlistsError.value != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '加载失败:${c.playlistsError.value}',
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
      if (c.playlists.isEmpty) {
        return const Center(child: Text('暂无歌单'));
      }
      return AspectDrivenGrid(
        minColumns: 2,
        childAspectRatio: 0.8,
        itemCount: c.playlists.length,
        itemBuilder: (context, index) {
          final p = c.playlists[index];
          return SongListCard(
            playlistId: p.id,
            title: p.name,
            subtitle: '${p.trackCount} 首',
            imageUrl: p.picUrl,
          );
        },
      );
    });
  }
}

/// 专辑 grid
class _AlbumsView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = Get.find<LibraryController>();
    return Obx(() {
      if (c.albumsLoading.value) {
        return const Center(child: CircularProgressIndicator());
      }
      if (c.albumsError.value != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '加载失败:${c.albumsError.value}',
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
      if (c.albums.isEmpty) {
        return const Center(child: Text('暂无订阅专辑'));
      }
      return AspectDrivenGrid(
        minColumns: 2,
        childAspectRatio: 0.8,
        itemCount: c.albums.length,
        itemBuilder: (context, index) {
          final a = c.albums[index];
          return SongListCard(
            playlistId: 'album-${a.id}',
            title: a.name,
            subtitle: a.artist,
            imageUrl: a.picUrl,
          );
        },
      );
    });
  }
}

/// 艺人 grid(跳 ArtistDetail,不走 SongListDetail)
class _ArtistsView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = Get.find<LibraryController>();
    return Obx(() {
      if (c.artistsLoading.value) {
        return const Center(child: CircularProgressIndicator());
      }
      if (c.artistsError.value != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '加载失败:${c.artistsError.value}',
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
      if (c.artists.isEmpty) {
        return const Center(child: Text('暂无关注艺人'));
      }
      return AspectDrivenGrid(
        minColumns: 3,
        childAspectRatio: 0.8,
        itemCount: c.artists.length,
        itemBuilder: (context, index) {
          final a = c.artists[index];
          return SongListCard(
            playlistId: a.id,
            title: a.name,
            subtitle: '',
            imageUrl: a.picUrl,
            onTap: () => Get.to(
              () => ArtistDetail(artistId: a.id),
              id: AppShell.shellNavigatorId,
              binding: ArtistDetailBinding(artistId: a.id),
            ),
          );
        },
      );
    });
  }
}