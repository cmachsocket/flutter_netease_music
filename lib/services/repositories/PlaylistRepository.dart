import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:musiclibrary/music_library.dart';

import '../../models/LibrarySummary.dart' show PlaylistSource;
import '../../models/Song.dart';
import '../../sdk/ApiCall.dart';
import '../../models/ApiException.dart';
import '../../sdk/NeteaseApi.dart';
import '../../models/Playlist.dart';
import '../PlaylistEventsController.dart';

/// 歌单 repository —— 集中 `/playlist/detail` + `/playlist/track/all`
/// 两个 API 调用
///
/// 把散落在 [SongListController._loadPlaylist] 里的两个 `apiCall` + 元信息 +
/// 曲目解析集中到这里。
///
/// - **不做** title/coverUrl/description 等 Rx 写回 —— 这些是业务状态,
///   保留在 [SongListController]。
/// - **只做**: 调 API + 解析 + 返回强类型结果。
class PlaylistRepository extends GetxService {
  final NeteaseApi _api;

  PlaylistRepository(this._api);

  /// 全局歌单事件中心(addTracks / removeTracks / deletePlaylist 成功后 emit)。
  /// 注入而非全局 Get.find,便于测试时 mock。
  final PlaylistEventsController _events =
      Get.find<PlaylistEventsController>();

  /// 拉歌单元信息(标题/封面/描述 + source)。
  ///
  /// API: `/playlist/detail?id=X`, 响应:
  /// ```
  /// { playlist: { id, name, coverImgUrl, description, subscribed, ... } }
  /// ```
  ///
  /// 返回 null: API 失败。返回空数据: 成功但 playlist 字段缺失。
  ///
  /// **source 解析**:后端 `playlist.subscribed` bool —— 真值映射在
  /// [fetchMeta] 内一次完成,调用方只读 enum。专辑(id 以 `album-`
  /// 开头)不走这条路径,source 字段没有意义。
  Future<PlaylistMeta?> fetchMeta(String playlistId) async {
    try {
      final r = await apiCall(
        () => _api.raw.playlist_detail(playlistId),
        what: '拉歌单详情',
      );
      final playlist = r.body['playlist'];
      if (playlist is! Map) return null;
      final p = Map<String, dynamic>.from(playlist);
      return PlaylistMeta(
        name: (p['name'] ?? '').toString(),
        coverUrl: (p['coverImgUrl'] ?? '').toString(),
        description: (p['description'] ?? '').toString(),
        source: p['subscribed'] == true
            ? PlaylistSource.collected
            : PlaylistSource.created,
      );
    } on ApiException {
      return null;
    }
  }

  /// 拉歌单所有曲目。
  ///
  /// API: `/playlist/track/all?id=X`, 响应:
  /// ```
  /// { songs: [{ id, name, ar, al, dt, ... }, ...] }
  /// ```
  /// (track_all 而非 detail.tracks,后者只返前 1000 首)
  ///
  /// 返回空列表: API 失败 / songs 字段缺失。
  Future<List<Song>> fetchTracks(String playlistId) async {
    try {
      final r = await apiCall(
        () => _api.raw.playlist_track_all(playlistId),
        what: '拉歌单曲目',
      );
      final songsList = r.body['songs'];
      if (songsList is! List) return [];
      return songsList
          .whereType<Map>()
          .map((m) => Song.fromNeteaseJson(Map<String, dynamic>.from(m)))
          .toList();
    } on ApiException {
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // 歌单写入 API
  //
  // SDK 暴露的两个端点:
  //   - `playlist_create(String name, ...)`     -> /playlist/create
  //   - `playlist_tracks(String op, String pid, String tracks, ...)`
  //                                            -> /playlist/tracks?op=add&pid=X&tracks=Y,Y
  //
  // 真实响应结构(已用真机 raw body 校准):
  //   create 成功: status=200, body={code: 200, playlist: {...}, id: <新歌单 id>}
  //               body['playlist']['id'] 是数字,body['id'] 也是数字(冗余)。
  //   add 成功判定 (待校准): body['code'] == 200(网易云业务 code)。
  //                          status 一直是 200 即使失败(API 包了一层),
  //                          所以 **必须** 看 body.code,不能只查 status。

  /// 创建新歌单。
  ///
  /// API: `/playlist/create?name=X`,成功响应:
  /// ```
  /// {
  ///   code: 200,
  ///   playlist: { id: 18362465054, name: "...", userId: ..., trackCount: 0, ... },
  ///   id: 18362465054     // 顶层冗余 id
  /// }
  /// ```
  ///
  /// 返回:
  /// - 新歌单 id(成功)
  /// - `null`(业务 code != 200 / body 结构异常)
  Future<String?> createPlaylist(String name) async {
    final MusicResponse r;
    try {
      r = await apiCall(
        () => _api.raw.playlist_create(name),
        what: '创建歌单',
      );
    } on ApiException {
      return null;
    }
    return _extractNewPlaylistId(r);
  }

  /// 把歌曲加入歌单。
  ///
  /// API: `/playlist/tracks?op=add&pid=X&tracks=id1,id2,...`
  ///
  /// 返回:
  /// - `true` 业务 code == 200
  /// - `false` 业务 code != 200 / API 异常
  ///
  /// songIds 会被 join(',') 一次性提交;网易云单次上限 ~1000,超出
  /// 应该由调用方在 controller 层分批 — repository 不做静默截断。
  ///
  /// **校准日志**:任何失败路径都 `debugPrint` raw body,方便贴回来校准
  /// `body['code'] == 200` 是否是真正的成功判定。
  Future<bool> addTracks(String playlistId, List<String> songIds) async {
    if (songIds.isEmpty) return false;
    final tracks = songIds.join(',');
    final MusicResponse r;
    try {
      r = await apiCall(
        () => _api.raw.playlist_tracks('add', playlistId, tracks),
        what: '添加歌曲到歌单',
      );
    } on ApiException catch (e) {
      // 路径 1:apiCall 内部 checkResponse 已抛 ApiException(HTTP 非 200 /
      // body.code 是 int 且 != 200)。raw body 在异常抛出时已装进 e.rawBody
      // (see ApiCall.checkResponse),失败时打整段 body 方便校准。
      if (kDebugMode) {
        debugPrint(
          '[PlaylistRepository.addTracks] FAILED ApiException code=${e.code} '
          'message=${e.message}\n'
          'raw body: ${e.rawBody}\n'
          'params: playlistId=$playlistId tracks=$tracks',
        );
      }
      return false;
    }
    // 路径 2:apiCall 成功 → _extractAddResult 判 body.code
    // (这里 body.code 不是 200 但也不是 int,或者其它异常情况)
    if (!_extractAddResult(r)) {
      if (kDebugMode) {
        debugPrint(
          '[PlaylistRepository.addTracks] FAILED raw body: ${r.body}\n'
          'params: playlistId=$playlistId tracks=$tracks',
        );
      }
      return false;
    }
    // 成功:emit delta 事件,LibraryPage 等显示 trackCount 的地方实时更新
    _events.applyDelta(playlistId, songIds.length);
    return true;
  }

  /// 从歌单删除歌曲。
  ///
  /// API: `/playlist/tracks?op=del&pid=X&tracks=id1,id2,...`
  /// (op='del' 沿用 SDK `playlist_tracks` 接口,MUSICLIBRARY.md 文档)
  ///
  /// **返回 / 字段校准状态**:**未真机校准**。沿用 `addTracks` 的成功判定
  /// 经验值 `body['code'] == 200`,真机跑出来 body 结构对不上时改
  /// `_extractRemoveResult`。
  ///
  /// 返回:
  /// - `true` 业务 code == 200
  /// - `false` 业务 code != 200 / API 异常
  ///
  /// **日志**:失败路径 `debugPrint` raw body 方便贴回来校准。
  Future<bool> removeTracks(String playlistId, List<String> songIds) async {
    if (songIds.isEmpty) return false;
    final tracks = songIds.join(',');
    final MusicResponse r;
    try {
      r = await apiCall(
        () => _api.raw.playlist_tracks('del', playlistId, tracks),
        what: '从歌单删除歌曲',
      );
    } on ApiException catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[PlaylistRepository.removeTracks] FAILED ApiException code=${e.code} '
          'message=${e.message}\n'
          'raw body: ${e.rawBody}\n'
          'params: playlistId=$playlistId tracks=$tracks',
        );
      }
      return false;
    }
    if (!_extractRemoveResult(r)) {
      if (kDebugMode) {
        debugPrint(
          '[PlaylistRepository.removeTracks] FAILED raw body: ${r.body}\n'
          'params: playlistId=$playlistId tracks=$tracks',
        );
      }
      return false;
    }
    // 成功:emit delta 事件
    _events.applyDelta(playlistId, -songIds.length);
    return true;
  }

  bool _extractRemoveResult(MusicResponse r) {
    // 跟 addTracks 同款:body 结构双层兼容(真机校准:code 在 r.body['body']['code'])
    final topLevel = r.body['code'];
    if (topLevel is int && topLevel == 200) return true;
    final nestedBody = r.body['body'];
    if (nestedBody is Map) {
      final innerCode = nestedBody['code'];
      if (innerCode is int && innerCode == 200) return true;
    }
    return false;
  }

  // ---- 响应解析(已校准:网易云业务 code 在 body['code'])---------------------

  /// 网易云 `/playlist/create` 的真实响应字段路径:
  ///   body['playlist']['id'] (数字) 或 顶层 body['id'] (数字) — 任一即可。
  /// 失败时 body['code'] != 200,这种情况下应该返回 null。
  String? _extractNewPlaylistId(MusicResponse r) {
    if (r.body['code'] != 200) return null;
    final playlist = r.body['playlist'];
    if (playlist is Map) {
      final id = playlist['id'];
      if (id is int) return id.toString();
      if (id is String) return id;
    }
    // 顶层冗余 id
    final top = r.body['id'];
    if (top is int) return top.toString();
    if (top is String) return top;
    return null;
  }

  /// 网易云 `/playlist/tracks` 成功条件:**双层 body 兼容**。
  ///
  /// 真机 raw 证据(2026-09-08 校准):
  /// ```
  /// r.body = {
  ///   status: 200,
  ///   body:   {trackIds: [3414798944], code: 200, count: 2, cloudCount: 0},
  ///   cookie: [...]
  /// }
  /// ```
  /// **`code` 在 `r.body['body']['code']` 而不是顶层**。可能是 SDK 端点
  /// wrapper 解析差异(其它端点如 playlist_create 的 code 在顶层,
  /// 这个端点在嵌套 body 里)。
  ///
  /// 兼容策略:**两层都查** —— 单层(顶层有 code 用顶层)+ 双层
  /// (顶层没 code 找 body.body.code)。
  bool _extractAddResult(MusicResponse r) {
    final topLevel = r.body['code'];
    if (topLevel is int && topLevel == 200) return true;
    final nestedBody = r.body['body'];
    if (nestedBody is Map) {
      final innerCode = nestedBody['code'];
      if (innerCode is int && innerCode == 200) return true;
    }
    return false;
  }

  /// 删除歌单(只能删自建的,收藏的只能取消订阅 —— 上层 toggleFavorite)。
  ///
  /// API: `/playlist/delete?id=X`,成功响应(沿用 `/playlist/create` 经验):
  /// ```
  /// { code: 200, ... }      // 业务 code 200 即成功
  /// ```
  /// 待真机校准:如果业务 code 路径不对(比如 code 在 body.data 下),
  /// 按实际 raw body 修正 `_extractDeleteResult`。
  ///
  /// 返回:
  /// - `true` 业务 code == 200
  /// - `false` 业务 code != 200 / API 异常
  ///
  /// 注意:删除成功 → UI 应该 reload Library 歌单列表(因为这条 id 已不存在),
  /// reload 逻辑放 controller,repository 只负责单次 HTTP。
  Future<bool> deletePlaylist(String playlistId) async {
    final MusicResponse r;
    try {
      r = await apiCall(
        () => _api.raw.playlist_delete(playlistId),
        what: '删除歌单',
      );
    } on ApiException {
      return false;
    }
    final ok = _extractDeleteResult(r);
    if (ok) {
      // 成功:重置这个 playlistId 的 delta(歌单已不存在,本地不再需要 offset)
      _events.resetDelta(playlistId);
    }
    return ok;
  }

  bool _extractDeleteResult(MusicResponse r) {
    return r.body['code'] == 200;
  }
  // ---------------------------------------------------------------------------
}
