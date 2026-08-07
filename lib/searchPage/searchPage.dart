import 'package:flutter/material.dart' hide SearchController;
import 'package:get/get.dart';

import '../AppShell.dart';
import '../ArtistPage/Artist.dart';
import '../ArtistPage/ArtistDetail.dart';
import '../SongListPage/SongListBody.dart';
import '../SongListPage/SongListCard.dart';
import '../SongListPage/SongListDetail.dart';
import '../models/Album.dart';
import '../models/Song.dart';
import '../widgets/aspect_driven_grid.dart';
import 'SearchController.dart';

/// 搜索页(主 tab 之一)
///
/// - 顶部 [SegmentedButton] 在 4 个 [SearchType] 之间切换
/// - 4 个 view 各自走对应的容器:
///   - 单曲 → [SongListBody]
///   - 专辑 / 艺人 / 歌单 → [AspectDrivenGrid] + [SongListCard]
/// - 暂不接 SDK:view 内直接给一组 stub 数据;接 SDK 后换成 SearchController.search(type, keyword)
class SearchPage extends StatelessWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<SearchController>();
    return Column(
      children: [
        const _SearchBar(),
        // SegmentedButton 直接放在 Column 顶部,跟 LibraryPage 的 SegmentedButton 布局一致
        Obx(
          () => SegmentedButton<SearchType>(
            segments: [
              for (final t in SearchType.values)
                ButtonSegment(value: t, label: Text(t.label)),
            ],
            selected: {controller.type.value},
            onSelectionChanged: (s) => controller.setType(s.first),
            showSelectedIcon: false,
          ),
        ),
        Expanded(child: Obx(() => _SearchResults(type: controller.type.value))),
      ],
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.type});

  final SearchType type;

  @override
  Widget build(BuildContext context) {
    return switch (type) {
      SearchType.song => SongListBody(songs: _stubSongs, isLoading: false),
      SearchType.album => _grid<Album>(
        items: _stubAlbums,
        toCard: (a) => SongListCard(
          playlistId: 'album-${a.id}',
          title: a.name,
          subtitle: '${a.type.label} · ${a.songCount}首',
          imageUrl: a.coverUrl,
          onTap: () => Get.to(
            () => SongListDetail(playlistId: 'album-${a.id}'),
            id: AppShell.shellNavigatorId,
            binding: SongListDetailBinding(playlistId: 'album-${a.id}'),
          ),
        ),
      ),
      SearchType.artist => _grid<Artist>(
        items: _stubArtists,
        toCard: (a) => SongListCard(
          playlistId: a.id,
          title: a.name,
          subtitle: '${a.albumCount}张专辑 · ${a.songCount}首歌',
          imageUrl: a.photoUrl,
          onTap: () => Get.to(
            () => ArtistDetail(artistId: a.id),
            id: AppShell.shellNavigatorId,
            binding: ArtistDetailBinding(artistId: a.id),
          ),
        ),
      ),
      SearchType.playlist => _grid<_PlaylistStub>(
        items: _stubPlaylists,
        toCard: (p) => SongListCard(
          playlistId: p.id,
          title: p.name,
          subtitle: '${p.trackCount}首歌',
          imageUrl: p.coverUrl,
          // 默认导航 → SongListDetail.open(playlistId),onTap 传 null 即可
          onTap: null,
        ),
      ),
    };
  }
}

/// 搜索栏:TextField + 搜索图标 + 清除按钮
///
/// - 显式绑 [SearchController.textController] 给 [TextField.controller],
///   清除按钮才能真正清空输入框(不显式绑时 TextField 内部 state 复用看不见的 controller,
///   点清除只改了 RxString,输入框不响应)
/// - keyword 通过 [textController] listener 自动同步,Obx 驱动 suffixIcon 显示/隐藏
/// - 接 SDK 后:用 `ever(controller.keyword, ...)` debounce 触发 search
class _SearchBar extends StatelessWidget {
  const _SearchBar();

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<SearchController>();
    return Obx(
      () => TextField(
        // 显式绑 controller,清除按钮才能真正清空输入框
        controller: controller.textController,
        textInputAction: TextInputAction.search,
        onSubmitted: (s) => controller.search(s),
        onChanged: (s) => controller.setKeyword(s),
        decoration: InputDecoration(
          hintText: '搜索歌曲、艺人、专辑、歌单',
          prefixIcon: IconButton(
            onPressed: () => controller.search(controller.textController.text),
            icon: const Icon(Icons.search),
          ),
          suffixIcon: controller.keyword.value.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: controller.clearKeyword,
                  tooltip: '清除',
                ),
        ),
      ),
    );
  }
}

/// 3 个 entity view 共用的 grid 容器(避免 AspectDrivenGrid 包法重复 3 遍)
Widget _grid<T>({
  required List<T> items,
  required Widget Function(T item) toCard,
}) {
  return AspectDrivenGrid(
    itemCount: items.length,
    itemBuilder: (context, index) => toCard(items[index]),
  );
}

// ─── stub 数据 ───────────────────────────────────────────────────────────────
//
// TODO: 接 SDK 后换成 SearchController.search(type: SearchType, keyword: String)
// 当前 stub 不分关键词,每个 type 给一组固定假数据,跟现有 ArtistController /
// SongListController 的 seed 风格一致

const _cover = 'https://cdn.jsdelivr.net/gh/cmachsocket/resources/avatar.png';

final _stubSongs = <Song>[
  Song(
    id: 's1',
    title: '搜索结果 - 红莲',
    artist: '艺术家 A',
    album: '示例专辑 1',
    coverUrl: _cover,
    duration: Duration(minutes: 3, seconds: 30),
  ),
  Song(
    id: 's2',
    title: '搜索结果 - 远海',
    artist: '艺术家 B',
    album: '示例专辑 2',
    coverUrl: _cover,
    duration: Duration(minutes: 4, seconds: 5),
  ),
  Song(
    id: 's3',
    title: '搜索结果 - 夜行',
    artist: '艺术家 C',
    album: '示例 EP',
    coverUrl: _cover,
    duration: Duration(minutes: 2, seconds: 56),
  ),
  Song(
    id: 's4',
    title: '搜索结果 - 微风',
    artist: '艺术家 D',
    album: '秋日私语',
    coverUrl: _cover,
    duration: Duration(minutes: 3, seconds: 47),
  ),
];

final _stubAlbums = <Album>[
  Album(
    id: 'sa1',
    name: '搜索专辑 - 夏夜',
    artist: '艺术家 A',
    coverUrl: _cover,
    songCount: 12,
    releaseDate: DateTime(2024, 3, 15),
    type: AlbumType.album,
  ),
  Album(
    id: 'sa2',
    name: '搜索 EP - 微光',
    artist: '艺术家 B',
    coverUrl: _cover,
    songCount: 5,
    releaseDate: DateTime(2023, 11, 8),
    type: AlbumType.ep,
  ),
  Album(
    id: 'sa3',
    name: '搜索单曲 - 夜行',
    artist: '艺术家 C',
    coverUrl: _cover,
    songCount: 1,
    releaseDate: DateTime(2024, 6, 1),
    type: AlbumType.single,
  ),
  Album(
    id: 'sa4',
    name: '搜索专辑 - 山海',
    artist: '艺术家 D',
    coverUrl: _cover,
    songCount: 8,
    releaseDate: DateTime(2022, 9, 20),
    type: AlbumType.album,
  ),
];

final _stubArtists = <Artist>[
  Artist(
    id: 'sar1',
    name: '搜索艺人 - 林深',
    bio: '民谣 / 独立音乐人',
    photoUrl: _cover,
    songCount: 24,
    albumCount: 3,
  ),
  Artist(
    id: 'sar2',
    name: '搜索艺人 - 远海',
    bio: '电子 / 氛围',
    photoUrl: _cover,
    songCount: 36,
    albumCount: 5,
  ),
  Artist(
    id: 'sar3',
    name: '搜索艺人 - 夜行',
    bio: '后摇 / 器乐',
    photoUrl: _cover,
    songCount: 18,
    albumCount: 2,
  ),
];

// 歌单没有顶层 model,先用一个轻量 record-ish class 等接 SDK 时再决定要不要
// 抽到 models/。字段对齐网易云 playlist 关键信息
class _PlaylistStub {
  final String id;
  final String name;
  final String coverUrl;
  final int trackCount;
  const _PlaylistStub({
    required this.id,
    required this.name,
    required this.coverUrl,
    required this.trackCount,
  });
}

final _stubPlaylists = <_PlaylistStub>[
  _PlaylistStub(
    id: 'sp1',
    name: '搜索歌单 - 通勤必备',
    coverUrl: _cover,
    trackCount: 30,
  ),
  _PlaylistStub(
    id: 'sp2',
    name: '搜索歌单 - 学习专注',
    coverUrl: _cover,
    trackCount: 45,
  ),
  _PlaylistStub(
    id: 'sp3',
    name: '搜索歌单 - 深夜独处',
    coverUrl: _cover,
    trackCount: 22,
  ),
];
