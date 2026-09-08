import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/default.dart';
import '../models/LibrarySummary.dart' show PlaylistSource;
import 'SongListBody.dart';
import 'SongListBodyController.dart';
import 'SongListHead.dart';
import 'SongListHeadController.dart';

/// 歌单详情页(主页 [SongListCard] 点进来后看到)
///
/// - 由 binding 同时注入两个 sibling controller:
///   - [SongListHeadController]:head 行(标题/封面/描述/playlistSource/按钮命令)
///   - [SongListBodyController]:body(歌曲列表 + 加载/错误)
/// - widget 层只组合 [SongListHead] + [SongListBody],不直接 Get.find controller。
/// - 业务侧零硬编码 —— 列表渲染 / 单元格都走现成 widget。
class SongListDetail extends StatelessWidget {
  const SongListDetail({super.key, this.displayTitle});

  /// 进入页面时 fallback 标题(head controller 拉完元信息后会覆盖)
  final String? displayTitle;

  @override
  Widget build(BuildContext context) {
    final head = Get.find<SongListHeadController>();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Get.back(id: DefaultValues.shellNavigatorId),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Obx(() {
          // 优先用 head 拉到的 title;没拉到时用 displayTitle 兜底
          final remoteTitle = head.title.value?.trim() ?? '';
          final fallbackTitle = displayTitle?.trim() ?? '歌单';
          final title = remoteTitle.isNotEmpty ? remoteTitle : fallbackTitle;
          final prefix = head.playlistSource.value == PlaylistSource.album
              ? '专辑'
              : '歌单';
          return Text('$prefix · $title');
        }),
      ),
      body: Column(
        children: [
          SongListHead(controller: head),
          Expanded(
            child: //嵌套导航
            Navigator(
              key: Get.nestedKey(DefaultValues.songListBodyNavigatorId),
              initialRoute: '/songlistbody',
              onGenerateRoute: (settings) {
                if (settings.name == '/songlistbody') {
                  return GetPageRoute(
                    page: () => SongListBody(),
                    binding: SongListBodyBinding(
                      playlistId: head.playlistId,
                      source: head.source,
                    ),
                  );
                }
                return null;
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 歌单详情页 binding —— 同时注入 head / body 两个 controller。
///
/// **单向关联**:head 的 `onPlayAll` 指向 body 的 `playAll`,这样 head 是
/// 纯命令执行器,不知道 songs 在哪(解耦)。其它 head 命令(toggleFavorite /
/// isPlaylistFavorite / deletePlaylist)只跟全局服务交互,不依赖 body。
class SongListDetailBinding extends Bindings {
  SongListDetailBinding({required this.playlistId, required this.source});

  final int playlistId;
  final PlaylistSource source;

  @override
  void dependencies() {
    final body = SongListBodyController(playlistId: playlistId, source: source);
    Get.lazyPut<SongListBodyController>(
      () => body,
      tag: playlistId.toString() + source.toString(),
    );
    Get.lazyPut<SongListHeadController>(
      () => SongListHeadController(
        playlistId: playlistId,
        source: source,
        onPlayAll: body.playAll,
      ),
      tag: playlistId.toString() + source.toString(),
    );

    // 把 body.playAll 注入 head 的 onPlayAll 钩子(head 不知道 body 的存在,
    // 只接一个 Future<void> Function())
  }
}

/// 不带参数的老 binding 占位(其它地方可能 import 这个名字)。
/// 之前 [SongListBinding] 是空类 —— 删掉,统一用 [SongListDetailBinding]。
class SongListBinding extends Bindings {
  @override
  void dependencies() {
    // 参数由 [SongListDetailBinding] 携带,这里 no-op。
  }
}
