import 'package:flutter/material.dart' hide SearchController;
import 'package:get/get.dart';

import '../models/Default.dart';
import '../ArtistPage/ArtistDetail.dart';
import '../SongListPage/SongListBody.dart';
import '../SongListPage/SongListBodyController.dart';
import '../SongListPage/SongListCard.dart';
import '../SongListPage/SongListDetail.dart';
import '../models/Album.dart';
import '../models/Artist.dart';
import '../widgets/aspect_driven_grid.dart';
import '../services/repositories/SearchRepository.dart'
    show SearchType, SearchPlaylistSummary;
import 'SearchController.dart';
import '../models/LibrarySummary.dart' show PlaylistSource;

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
///
/// **数据源**:不再调后端(`/playlist/track/all?id=X`)。通过 [SongListBodyController]
/// 的 `loadSongsCustom` 钩子,直接把 `SearchController.songResults` 喂给 body。
///
/// **响应式**:`Obx` 监听 `c.songResults` 变化时,手动 `body.songs.assignAll(...)`
/// 同步 —— body 内部的 Obx 检测到 `songs` Rx 变化触发重建。
///
/// **生命周期**(纯 StatelessWidget,不用 StatefulWidget —— 这是项目硬要求):
/// - Obx 多次 rebuild 时,`!isRegistered` 守卫保证同一个 tag 只 put 一次
/// - 重复进 build 走 else 分支同步数据,不创建新 controller,不会触发 `onInit` 二次初始化
/// - keyword 切换时,旧 tag 的 controller 在路由 pop(`permanent: false`)时被 GetX 自动清理
/// - `[SongListBodyController.ready]` 用 `late`(不是 `late final`),即使 controller
///   实例被复用过 onInit 二次跑也不会抛 `LateInitializationError`
class _SongView extends StatelessWidget {
  const _SongView({required this.c});

  final SearchController c;

  /// 每条搜索结果对应一个 body controller tag(用 keyword 区分,
  /// 不同关键词产生不同 controller 实例 —— 防止切关键词时旧数据残留)。
  String _tagFor(String keyword) => 'search-$keyword-${PlaylistSource.pure}';

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final keyword = c.submittedKeyword.value;
      // loading + 错误 + 空 三态分流
      if (c.isLoading.value && c.songResults.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      if (c.errorMessage.value != null && c.songResults.isEmpty) {
        return _ErrorView(text: c.errorMessage.value!);
      }
      if (c.songResults.isEmpty && keyword.isEmpty) {
        return const _HintView(text: '输入关键词开始搜索');
      }
      if (c.songResults.isEmpty) {
        return _HintView(text: '没有匹配 "$keyword" 的单曲');
      }

      final tag = _tagFor(keyword);

      // 确保 body controller 已注册(用 lazyPut 首次 build 时创建,
      // 后续 build 复用同一个实例 —— 避免重复初始化)。
      if (!Get.isRegistered<SongListBodyController>(tag: tag)) {
        Get.put(
          SongListBodyController(
            playlistId: keyword, // 用 keyword 当 playlistId(占位)
            source: PlaylistSource.pure,
            // **钩子只接收 controller 引用,绝不调 Get.find 同 tag**。
            // 在 onInit 同步链中调 Get.find 同 tag 会触发 GetX 内部
            // reentrant _initDependencies → 重复 onInit → stack overflow。
            // body 参数是 SongListBodyController.this,直接用即可。
            loadSongsCustom: (body) async {
              // 先等下一个 microtask,让 onInit 同步链完整结束 —— 这是
              // **真正的修复**:async 函数立即同步执行到第一个 await,
              // 但 Future.microtask 之前没 await,所以 body 字段还没准备好?
              // 这里直接读 songs(没赋值,因为 _loadSongs 推迟到 microtask)。
              // **安全做法**:在异步链上做赋值。
              Future.microtask(() {
                body.songs.assignAll(c.songResults.toList(growable: false));
              });
            },
          ),
          tag: tag,
          permanent: false,
        );
      } else {
        // 已注册 → 直接同步一次最新数据(防止 Obx 没触发但数据变了)
        Get.find<SongListBodyController>(
          tag: tag,
        ).songs.assignAll(c.songResults.toList(growable: false));
      }

      return SongListBody(controllerTag: tag);
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
      if (c.albumResults.isEmpty && c.submittedKeyword.value.isEmpty) {
        return const _HintView(text: '输入关键词开始搜索');
      }
      if (c.albumResults.isEmpty) {
        return _HintView(text: '没有匹配 "${c.submittedKeyword.value}" 的专辑');
      }
      return _grid<Album>(
        items: c.albumResults.toList(),
        toCard: (a) => SongListCard(
          playlistId: a.id,
          source: PlaylistSource.album,
          title: a.name,
          subtitle: '${a.songCount}首',
          imageUrl: a.coverUrl,
          isLiked: () => c.isAlbumLiked(a.id),
          onToggleFavorite: () => c.toggleAlbumLike(a.id),
          onTap: () => Get.to(
            () => SongListDetail(
              displayTitle: a.name,
              controllerTag: a.id + PlaylistSource.album.toString(),
            ),
            id: DefaultValues.shellNavigatorId,
            binding: SongListDetailBinding(
              playlistId: 'album-${a.id}',
              source: PlaylistSource.album,
            ),
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
      if (c.artistResults.isEmpty && c.submittedKeyword.value.isEmpty) {
        return const _HintView(text: '输入关键词开始搜索');
      }
      if (c.artistResults.isEmpty) {
        return _HintView(text: '没有匹配 "${c.submittedKeyword.value}" 的艺人');
      }
      return _grid<Artist>(
        items: c.artistResults.toList(),
        toCard: (a) => SongListCard(
          playlistId: a.id,
          source: PlaylistSource.artist,
          title: a.name,
          subtitle: '${a.albumCount}张专辑 · ${a.songCount}首歌',
          imageUrl: a.photoUrl,
          isLiked: () => c.isArtistLiked(a.id),
          onToggleFavorite: () => c.toggleArtistLike(a.id),
          onTap: () => Get.to(
            () => ArtistDetail(artistId: a.id),
            id: DefaultValues.shellNavigatorId,
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
      if (c.playlistResults.isEmpty && c.submittedKeyword.value.isEmpty) {
        return const _HintView(text: '输入关键词开始搜索');
      }
      if (c.playlistResults.isEmpty) {
        return _HintView(text: '没有匹配 "${c.submittedKeyword.value}" 的歌单');
      }
      return _grid<SearchPlaylistSummary>(
        items: c.playlistResults.toList(),
        toCard: (p) => SongListCard(
          playlistId: p.id,
          source: PlaylistSource.collected,
          title: p.name,
          subtitle: '${p.trackCount}首',
          imageUrl: p.coverUrl,
          isLiked: () => c.isPlaylistLiked(p.id),
          onToggleFavorite: () => c.togglePlaylistLike(p.id),
          onTap: () => Get.to(
            () => SongListDetail(
              displayTitle: p.name,
              controllerTag: p.id + PlaylistSource.collected.toString(),
            ),
            id: DefaultValues.shellNavigatorId,
            binding: SongListDetailBinding(
              playlistId: p.id,
              source: PlaylistSource.collected,
            ),
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
  return OrientationBuilder(
    builder: (context, orientation) {
      final aspectRatio = orientation == Orientation.portrait
          ? DefaultValues.portraitGridChildAspectRatio
          : DefaultValues.landscopeGridChildAspectRatio;
      return AspectDrivenGrid(
        childAspectRatio: aspectRatio,
        itemCount: items.length,
        itemBuilder: (context, index) => toCard(items[index]),
      );
    },
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
