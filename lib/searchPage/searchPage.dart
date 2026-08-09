import 'package:flutter/material.dart' hide SearchController;
import 'package:get/get.dart';

import '../AppShell.dart';
import '../ArtistPage/ArtistDetail.dart';
import '../SongListPage/SongListBody.dart';
import '../SongListPage/SongListCard.dart';
import '../SongListPage/SongListDetail.dart';
import '../models/Album.dart';
import '../ArtistPage/Artist.dart';
import '../widgets/aspect_driven_grid.dart';
import 'SearchController.dart';

/// 搜索页(主 tab 之一)
///
/// - 顶部 [TextField] 输入关键词,提交触发 [SearchController.search]
/// - [SegmentedButton] 切 [SearchType]:同 keyword 自动重搜
/// - 4 个 view 各自走对应的容器:
///   - 单曲 → [SongListBody](空态 / loading / 错误三态)
///   - 专辑 / 艺人 / 歌单 → [AspectDrivenGrid] + [SongListCard]
class SearchPage extends StatelessWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<SearchController>();
    return Column(
      children: [
        const _SearchBar(),
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
    final controller = Get.find<SearchController>();
    return switch (type) {
      SearchType.song => _SongView(c: controller),
      SearchType.album => _AlbumGridView(c: controller),
      SearchType.artist => _ArtistGridView(c: controller),
      SearchType.playlist => _PlaylistGridView(c: controller),
    };
  }
}

/// 单曲列表:复用 SongListBody(已有 loading / empty / list 三态)
class _SongView extends StatelessWidget {
  const _SongView({required this.c});

  final SearchController c;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (c.isLoading.value && c.songResults.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      if (c.errorMessage.value != null && c.songResults.isEmpty) {
        return _ErrorView(text: c.errorMessage.value!);
      }
      if (c.songResults.isEmpty && c.keyword.value.isEmpty) {
        return const _HintView(text: '输入关键词开始搜索');
      }
      if (c.songResults.isEmpty) {
        return _HintView(text: '没有匹配 "${c.keyword.value}" 的单曲');
      }
      return SongListBody(songs: c.songResults.toList(), isLoading: false);
    });
  }
}

class _AlbumGridView extends StatelessWidget {
  const _AlbumGridView({required this.c});

  final SearchController c;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (c.isLoading.value && c.albumResults.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      if (c.albumResults.isEmpty && c.keyword.value.isEmpty) {
        return const _HintView(text: '输入关键词开始搜索');
      }
      if (c.albumResults.isEmpty) {
        return _HintView(text: '没有匹配 "${c.keyword.value}" 的专辑');
      }
      return _grid<Album>(
        items: c.albumResults.toList(),
        toCard: (a) => SongListCard(
          playlistId: 'album-${a.id}',
          title: a.name,
          subtitle: '${a.type.label} · ${a.songCount}首',
          imageUrl: a.coverUrl,
          onTap: () => Get.to(
            () => SongListDetail(
              playlistId: 'album-${a.id}',
              displayTitle: a.name,
            ),
            id: AppShell.shellNavigatorId,
            binding: SongListDetailBinding(playlistId: 'album-${a.id}'),
          ),
        ),
      );
    });
  }
}

class _ArtistGridView extends StatelessWidget {
  const _ArtistGridView({required this.c});

  final SearchController c;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (c.isLoading.value && c.artistResults.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      if (c.artistResults.isEmpty && c.keyword.value.isEmpty) {
        return const _HintView(text: '输入关键词开始搜索');
      }
      if (c.artistResults.isEmpty) {
        return _HintView(text: '没有匹配 "${c.keyword.value}" 的艺人');
      }
      return _grid<Artist>(
        items: c.artistResults.toList(),
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
      );
    });
  }
}

class _PlaylistGridView extends StatelessWidget {
  const _PlaylistGridView({required this.c});

  final SearchController c;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (c.isLoading.value && c.playlistResults.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      if (c.playlistResults.isEmpty && c.keyword.value.isEmpty) {
        return const _HintView(text: '输入关键词开始搜索');
      }
      if (c.playlistResults.isEmpty) {
        return _HintView(text: '没有匹配 "${c.keyword.value}" 的歌单');
      }
      return _grid<PlaylistSummary>(
        items: c.playlistResults.toList(),
        toCard: (p) => SongListCard(
          playlistId: p.id,
          title: p.name,
          subtitle: '${p.creatorName} · ${p.trackCount}首',
          imageUrl: p.coverUrl,
          onTap: () => Get.to(
            () => SongListDetail(playlistId: p.id, displayTitle: p.name),
            id: AppShell.shellNavigatorId,
            binding: SongListDetailBinding(playlistId: p.id),
          ),
        ),
      );
    });
  }
}

/// 通用 grid 容器(避免 AspectDrivenGrid 包法重复)
Widget _grid<T>({
  required List<T> items,
  required Widget Function(T item) toCard,
}) {
  return AspectDrivenGrid(
    itemCount: items.length,
    itemBuilder: (context, index) => toCard(items[index]),
  );
}

/// 错误占位
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text('加载失败:$text', textAlign: TextAlign.center));
  }
}

/// 提示占位(空状态 / 未输入)
class _HintView extends StatelessWidget {
  const _HintView({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(text, textAlign: TextAlign.center));
  }
}

/// 搜索栏:TextField + 搜索图标 + 清除按钮
///
/// - 显式绑 [SearchController.textController] 给 [TextField.controller],
///   清除按钮才能真正清空输入框(不显式绑时 TextField 内部 state 复用看不见的 controller,
///   点清除只改了 RxString,输入框不响应)
/// - 提交触发 search;切 tab 由 controller.setType 内部自动重搜
class _SearchBar extends StatelessWidget {
  const _SearchBar();

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<SearchController>();
    return Obx(
      () => TextField(
        controller: controller.textController,
        textInputAction: TextInputAction.search,
        onSubmitted: controller.search,
        onChanged: controller.setKeyword,
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
