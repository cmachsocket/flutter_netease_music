import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../models/ApiException.dart';
import '../models/LibrarySummary.dart';
import '../models/Song.dart';
import '../sdk/AuthController.dart';
import '../services/AudioPlayerWrapper.dart';
import '../services/repositories/LibraryRepository.dart';
import '../services/repositories/PlaylistRepository.dart';

/// 长按 [SongRowTile] 弹出的菜单。
/// **校准状态**:
/// - `PlaylistRepository.removeTracks`:**未真机校准**,沿用 `addTracks` 经验值
///   `body['code'] == 200`,失败时会额外 log raw body 方便贴回来校准
/// - `AudioPlayerHandler.addQueueItem` override:**未真机校准**,trigger 后看
///   queue 列表 UI 是否刷新 + shuffle 模式下 next/prev 顺序是否正确
class LongPressDialog extends StatelessWidget {
  const LongPressDialog({
    super.key,
    required this.song,
    required this.index,
    required this.source,
    required this.playlistId,
  });
  final Song song;
  final int index;
  final PlaylistSource source;
  final String? playlistId;

  static const _tag = 'longPressDialog';

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<LongPressDialogController>(tag: _tag)) {
      Get.put(
        LongPressDialogController(
          song: song,
          index: index,
          source: source,
          playlistId: playlistId,
        ),
        tag: _tag,
      );
    }
    final controller = Get.find<LongPressDialogController>(tag: _tag);
    return Dialog(
      child: Obx(() {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: controller.isChoosingPlaylist.value
              ? _PlaylistPicker(
                  key: const ValueKey('picker'),
                  controller: controller,
                )
              : _MainMenu(key: const ValueKey('main'), controller: controller),
        );
      }),
    );
  }
}

// ---- 一级菜单 --------------------------------------------------------------

class _MainMenu extends StatelessWidget {
  const _MainMenu({super.key, required this.controller});

  final LongPressDialogController controller;

  @override
  Widget build(BuildContext context) {
    final song = controller.song;
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 标题区:歌曲名 + 艺人 + 关闭按钮
        // 用 ListTile.contentPadding(M3 默认)代替手写 EdgeInsets;
        // 右侧 8 是为了让 trailing IconButton 跟边缘紧凑(M3 默认 16 会过宽)
        ListTile(
          title: Text(
            song.title,
            style: textTheme.titleMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            song.artist,
            style: textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Get.back<void>(),
          ),
        ),
        const Divider(),

        // 添加到歌单
        ListTile(
          leading: const Icon(Icons.playlist_add),
          title: const Text('添加到歌单'),
          onTap: controller.openPlaylistPicker,
        ),

        // 添加到播放列表(末尾)
        ListTile(
          leading: const Icon(Icons.queue_music),
          title: const Text('添加到播放列表'),
          onTap: controller.addToQueue,
        ),

        // 从歌单中删除:仅自建歌单内显示
        if (controller.source == PlaylistSource.created &&
            controller.playlistId != null)
          ListTile(
            leading: Icon(
              Icons.remove_circle_outline,
              color: theme.colorScheme.error,
            ),
            title: Text(
              '从歌单中删除',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            onTap: controller.removeFromPlaylist,
          ),
      ],
    );
  }
}

// ---- 二级:选歌单 -----------------------------------------------------------

class _PlaylistPicker extends StatelessWidget {
  const _PlaylistPicker({super.key, required this.controller});

  final LongPressDialogController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 标题 + 返回
        ListTile(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: controller.closePlaylistPicker,
          ),
          title: Text('选择歌单', style: textTheme.titleMedium),
        ),
        const Divider(),

        // loading
        if (controller.pickerLoading.value)
          // vertical: 32 是 loading 指示器的"呼吸感"留白,Material 标准
          Center(child: CircularProgressIndicator())
        // 空
        else if (controller.userPlaylists.isEmpty)
          Text(
            controller.pickerError.value ?? '暂无歌单',
            style: textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          )
        // 列表:物理 maxHeight 是为了避免 dialog 超过屏幕,不能从 theme 派生
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: controller.userPlaylists.length,
              itemBuilder: (context, i) {
                final p = controller.userPlaylists[i];
                return ListTile(
                  leading: const Icon(Icons.playlist_play),
                  title: Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${p.trackCount} 首',
                    style: textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  onTap: () => controller.addToPlaylist(p.id, p.name),
                );
              },
            ),
          ),
      ],
    );
  }
}

// ---- Controller ------------------------------------------------------------

/// LongPressDialog 的 GetX controller。
///
/// **生命周期**:widget build 时 `Get.put(..., tag: 'longPressDialog')`,
/// dialog 关闭(`Get.back`)时 controller 仍存活直到下次 build 复用。
/// 想彻底清:在 `Get.back` 前 `Get.delete<LongPressDialogController>(tag: _tag)`。
///
/// **依赖**:
/// - `PlaylistRepository` — 添加/删除歌单曲目
/// - `LibraryRepository` + `AuthController` — 拉用户歌单列表(用于二级菜单)
/// - `AudioPlayerService` — addToQueue(wrapper 新增 API)
class LongPressDialogController extends GetxController {
  LongPressDialogController({
    required this.song,
    required this.index,
    required this.source,
    required this.playlistId,
  });

  final Song song;
  final int index;
  final PlaylistSource source;
  final String? playlistId;

  // ---- 依赖(注入而非全局查找,便于测试)-----------------------------------

  final PlaylistRepository _playlistRepo = Get.find<PlaylistRepository>();
  final LibraryRepository _libraryRepo = Get.find<LibraryRepository>();
  final AuthController _auth = Get.find<AuthController>();
  final AudioPlayerService _player = Get.find<AudioPlayerService>();

  // ---- 状态 ---------------------------------------------------------------

  /// 是否在二级"选歌单"面板
  final RxBool isChoosingPlaylist = false.obs;

  /// 二级面板:加载 / 错误 / 歌单列表
  final RxBool pickerLoading = false.obs;
  final RxnString pickerError = RxnString();
  final RxList<PlaylistSummary> userPlaylists = <PlaylistSummary>[].obs;

  /// 通用:某次操作进行中(防止用户重复点击)
  final RxBool isBusy = false.obs;

  // ---- 操作 ---------------------------------------------------------------

  /// 打开二级选歌单面板(首次触发拉取列表)
  Future<void> openPlaylistPicker() async {
    isChoosingPlaylist.value = true;
    if (userPlaylists.isEmpty) {
      await _loadUserPlaylists();
    }
  }

  void closePlaylistPicker() {
    isChoosingPlaylist.value = false;
  }

  /// 用户选了某个歌单:加歌 + 反馈 + 关闭整个 dialog
  Future<void> addToPlaylist(String playlistId, String playlistName) async {
    if (isBusy.value) return;
    isBusy.value = true;
    try {
      final ok = await _playlistRepo.addTracks(playlistId, [song.id]);
      Get.back<void>();
      if (ok) {
        _toast('已添加到 $playlistName');
      } else {
        _toast('添加失败');
        if (kDebugMode) {
          debugPrint(
            '[LongPressDialog] addTracks failed: playlistId=$playlistId, songId=${song.id}',
          );
        }
      }
    } finally {
      isBusy.value = false;
    }
  }

  /// 从当前所在的自建歌单删除这首歌
  Future<void> removeFromPlaylist() async {
    final pid = playlistId;
    if (pid == null) return;
    if (isBusy.value) return;
    isBusy.value = true;
    try {
      final ok = await _playlistRepo.removeTracks(pid, [song.id]);
      Get.back<void>();
      if (ok) {
        _toast('已从歌单删除');
        // 通知上层 controller 刷新 body 列表(删除的那一行没了)
        // 这里不直接调 controller,LongPressDialog 不知道上层是哪个 ——
        // 调用方应在 Get.back 后自行 reload。
      } else {
        _toast('删除失败');
        if (kDebugMode) {
          debugPrint(
            '[LongPressDialog] removeTracks failed: playlistId=$pid, songId=${song.id}',
          );
        }
      }
    } finally {
      isBusy.value = false;
    }
  }

  /// 追加到当前播放队列末尾
  Future<void> addToQueue() async {
    if (isBusy.value) return;
    isBusy.value = true;
    try {
      await _player.addToQueue(song);
      Get.back<void>();
      _toast('已添加到播放列表');
    } catch (e) {
      Get.back<void>();
      _toast('添加失败: $e');
      if (kDebugMode) {
        debugPrint('[LongPressDialog] addToQueue failed: $e');
      }
    } finally {
      isBusy.value = false;
    }
  }

  // ---- 私有 ---------------------------------------------------------------

  Future<void> _loadUserPlaylists() async {
    pickerLoading.value = true;
    pickerError.value = null;
    try {
      final uid = _auth.currentUid;
      if (uid == 0) {
        pickerError.value = '请先登录';
        userPlaylists.clear();
        return;
      }
      final list = await _libraryRepo.fetchPlaylists(uid.toString());
      userPlaylists.assignAll(list);
    } on ApiException catch (e) {
      pickerError.value = e.message;
      userPlaylists.clear();
    } catch (e) {
      pickerError.value = '加载歌单失败: $e';
      userPlaylists.clear();
    } finally {
      pickerLoading.value = false;
    }
  }

  void _toast(String msg) {
    Get.snackbar(
      '',
      msg,
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
      // 不传 margin —— GetX 默认 margin 是 16,跟 ListTile.contentPadding 一致
    );
  }
}
