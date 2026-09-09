import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../SongListPage/SongListDetail.dart';
import '../SongListPage/SongListHeadController.dart';
import '../models/Default.dart';
import '../models/LibrarySummary.dart' show PlaylistSource;

/// 艺人详情页 —— 复用 [SongListDetail] 路径。
///
/// **架构**:
/// - 不再有 [ArtistController] —— 全部走 [SongListDetailBinding]
/// - binding 注入 `source: PlaylistSource.artist`:
///   - head → [ArtistHeadController] (`/artists` 拉元信息,`LikedType.artist`)
///   - body → [SongListBodyController] (`/artist/songs` 拉所有歌曲)
/// - widget 只剩"AppBar 标题" + `SongListDetail` 主体(head + body)
/// - 专辑列表:**砍掉了**(本轮简化范围,后续如果需要可以单独实现)
class ArtistDetail extends StatelessWidget {
  const ArtistDetail({super.key, required this.artistId});

  final String artistId;

  /// 跟 `SongListDetailBinding` 共享的 controller tag(playlistId + source)
  String get _controllerTag => '$artistId${PlaylistSource.artist}';

  @override
  Widget build(BuildContext context) {
    // 读 head controller 拿名字给 AppBar
    final head = Get.find<SongListHeadControllerBase>(tag: _controllerTag);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Get.back(id: DefaultValues.shellNavigatorId),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Obx(() {
          final name = head.title.value?.trim();
          return Text('艺人 · ${name?.isNotEmpty == true ? name : artistId}');
        }),
      ),
      // 复用 SongListDetail 的 head + body 组合
      body: SongListDetail(controllerTag: _controllerTag),
    );
  }
}

/// 艺人详情页 binding —— 复用 [SongListDetailBinding] 逻辑。
///
/// **不再独立的 `ArtistDetailBinding`** —— 跟 [SongListDetailBinding]
/// 共用一套 head / body 注入 + source 路由。
class ArtistDetailBinding extends Bindings {
  ArtistDetailBinding({required this.artistId});

  final String artistId;

  @override
  void dependencies() {
    final binding = SongListDetailBinding(
      playlistId: artistId,
      source: PlaylistSource.artist,
    );
    binding.dependencies();
  }
}
