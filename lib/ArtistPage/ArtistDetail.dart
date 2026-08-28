import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../SongListPage/SongListBody.dart';
import '../SongListPage/SongListCard.dart';
import '../models/Album.dart';
import '../widgets/aspect_driven_grid.dart';
import '../widgets/netease_image.dart';
import 'Artist.dart';
import 'ArtistController.dart';
import '../models/default.dart';

/// 艺人详情页
///
/// - 进入路由时绑定的 [ArtistController] 已按 [artistId] 完成初始化,这里只消费
/// - 顶部 header:头像 + 名字 + 简介 + (关注 / 播放全部)
/// - 中部 [SegmentedButton] 在 "专辑 / EP" 网格 和 "所有歌曲" 列表之间切换
/// - 专辑视图直接复用 [SongListCard] + [AspectDrivenGrid],不抽新组件
/// - 歌曲视图直接复用 [SongListBody] (→ 内部用 [SongRowTile])
class ArtistDetail extends StatelessWidget {
  ArtistDetail({super.key, required this.artistId});

  final String artistId;

  final controller = Get.find<ArtistController>();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Obx(
          () => Text('艺人 · ${controller.artist.value?.name ?? artistId}'),
        ),
      ),
      body: Obx(() {
        // 顶层加载 / 错误:仅在 artist 元信息还没出来时生效
        // (songs / albums 是同一个 load() 一次性 assign 的,这里 atomic)
        if (controller.isLoading.value && controller.artist.value == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final err = controller.errorMessage.value;
        if (err != null && controller.artist.value == null) {
          final scheme = Theme.of(context).colorScheme;
          return Center(
            child: Text('加载失败: $err', style: TextStyle(color: scheme.error)),
          );
        }
        final artist = controller.artist.value;
        if (artist == null) {
          return const Center(child: Text('找不到该艺人'));
        }

        return Column(
          children: [
            _ArtistHeader(artist: artist),
            _SectionSwitcher(controller: controller),
            Expanded(child: _SectionContent(controller: controller)),
          ],
        );
      }),
    );
  }
}

class _ArtistHeader extends StatelessWidget {
  const _ArtistHeader({required this.artist});
  final Artist artist;
  static const artistBioMaxLines = 4;
  @override
  Widget build(BuildContext context) {
    final controller = Get.find<ArtistController>();
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    // 不套 ListTile(它的 trailing 槽高度被限死 ~56dp,装不下两个 TextButton.icon);
    // 跟 SongListDetail 头部同款套路:Row + 头像 / Expanded 文本列 / 按钮列
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CircleAvatar(
          backgroundImage: neteaseNetworkImage(artist.photoUrl),
          onBackgroundImageError: (_, _) {},
          backgroundColor: scheme.surfaceContainerHigh,
          child: Icon(Icons.person, color: scheme.onSurfaceVariant),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(artist.name, style: textTheme.titleLarge),
              Text(
                artist.bio,
                maxLines: artistBioMaxLines,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton.icon(
              onPressed: controller.playAll,
              icon: const Icon(Icons.play_arrow),
              label: const Text('播放全部'),
            ),
            TextButton.icon(
              onPressed: controller.toggleFollow,
              icon: Obx(
                () => Icon(
                  controller.isFollowing.value
                      ? Icons.favorite
                      : Icons.favorite_border,
                ),
              ),
              label: Text(controller.isFollowing.value ? '已关注' : '关注'),
            ),
          ],
        ),
      ],
    );
  }
}

class _SectionSwitcher extends StatelessWidget {
  const _SectionSwitcher({required this.controller});
  final ArtistController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => SegmentedButton<ArtistView>(
        segments: const [
          ButtonSegment(
            value: ArtistView.albums,
            label: Text('专辑 / EP'),
            icon: Icon(Icons.album),
          ),
          ButtonSegment(
            value: ArtistView.songs,
            label: Text('所有歌曲'),
            icon: Icon(Icons.queue_music),
          ),
        ],
        selected: {controller.view.value},
        onSelectionChanged: (s) => controller.setView(s.first),
      ),
    );
  }
}

class _SectionContent extends StatelessWidget {
  const _SectionContent({required this.controller});
  final ArtistController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      switch (controller.view.value) {
        case ArtistView.albums:
          return _AlbumsSection(albums: controller.albums.toList());
        case ArtistView.songs:
          return SongListBody(
            songs: controller.songs.toList(),
            isLoading: false,
            onToggleFavorite: (song) => controller.toggleFavorite(song.id),
            onPlay: controller.playSong,
            isLiked: (song) => controller.isLiked(song.id),
          );
      }
    });
  }
}

/// 专辑 / EP 网格:直接复用 SongListCard + AspectDrivenGrid
///
/// 跳转链路:
/// - 卡片 onTap → SongListCard 默认 _defaultNavigate (传 `playlistId = 'album-${album.id}'`)
/// - SongListDetail 看 playlistId 以 `album-` 开头 → 标题前缀加 "专辑"
/// - SongListController.load 看到 `_albumPrefix` → 走 `_loadAlbum` 调 NCM `/album`
///   拿真专辑元信息 + songs 数组(不是占位)
class _AlbumsSection extends StatelessWidget {
  const _AlbumsSection({required this.albums});
  final List<Album> albums;
  @override
  Widget build(BuildContext context) {
    final controller = Get.find<ArtistController>();
    if (albums.isEmpty) {
      return const Center(child: Text('暂无专辑'));
    }
    return OrientationBuilder(
      builder: (context, orientation) {
        final aspectRatio = orientation == Orientation.portrait
            ? DefaultValues.portraitGridChildAspectRatio
            : DefaultValues.landscopeGridChildAspectRatio;
        return AspectDrivenGrid(
          itemCount: albums.length,
          childAspectRatio: aspectRatio,
          minColumns: DefaultValues.gridMinColumns,
          itemBuilder: (context, index) {
            final album = albums[index];
            return SongListCard(
              playlistId: 'album-${album.id}',
              title: album.name,
              subtitle: '${album.type.label} · ${album.songCount}首',
              imageUrl: album.coverUrl,
              isLiked: () => controller.isAlbumLiked(album.id),
              onToggleFavorite: () => controller.toggleAlbumFavorite(album.id),
            );
          },
        );
      },
    );
  }
}

class ArtistDetailBinding extends Bindings {
  final String artistId;

  ArtistDetailBinding({required this.artistId});

  @override
  void dependencies() {
    Get.lazyPut<ArtistController>(() => ArtistController(artistId: artistId));
  }
}
