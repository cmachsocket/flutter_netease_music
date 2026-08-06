# musiclibrary SDK 使用文档

> 适配本项目 (`flutter_netease_music`) 的网易云音乐 / 酷狗音乐 FFI 绑定包
> 底层: Go + WebKit JSContext → 通过 Dart FFI 调用
> 仓库: https://github.com/2061360308/NeteaseCloudMusic_PythonSDK
> 本文档只覆盖 **网易云音乐 (NeteaseCloudMusicApi)** 接口,酷狗 (KugouCloudMusicApi) 同理但本项目暂未使用

---

## 目录

1. [安装与初始化](#1-安装与初始化)
2. [响应结构 MusicResponse](#2-响应结构-musicresponse)
3. [调用模式](#3-调用模式)
4. [接口完整索引](#4-接口完整索引) — 335 个方法
5. [常用流程示例](#5-常用流程示例)
6. [注意事项](#6-注意事项)
7. [对应本项目的接入点](#7-对应本项目的接入点)

---

## 1. 安装与初始化

`pubspec.yaml` 已经声明:

```yaml
dependencies:
  musiclibrary:
    git:
      url: https://github.com/2061360308/NeteaseCloudMusic_PythonSDK.git
      path: src/dart
```

```dart
import 'package:flutter_music_library/netease_cloud_music_api.dart';
import 'package:flutter_music_library/core.dart';

final api = NeteaseCloudMusicApi(
  env: NcmProcessEnv(
    cnIp: '...',              // 选填,留空则 SDK 内部随机生成
    anonymousToken: '...',    // 选填,留空则 SDK 内部随机生成
  ),
  libraryDir: null,           // 选填,自定义 .so/.dll/.dylib 路径
);
```

构造时会自动 `init_engine` + `ncm_init`,并在内部维护一个 JSContext。

退出时记得 `dispose()` 释放 native 内存:

```dart
api.dispose();
```

---

## 2. 响应结构 `MusicResponse`

**所有接口统一返回 `MusicResponse`:**

```dart
class MusicResponse {
  final Map<String, dynamic> headers;  // HTTP 头,登录接口的 Set-Cookie 在这
  final Map<String, dynamic> body;     // 业务 JSON,key 因接口而异
  final int status;                    // HTTP status code (200 / 301 / 400 / 502 ...)

  Map<String, dynamic> get data => body;
  String get cookies;                  // headers['Set-Cookie'] 字符串
}
```

业务错误判定:

```dart
final r = api.song_detail(ids: '123');
if (r.status != 200 || r.body['code'] != 200) {
  // 失败
}
```

注意: SDK 是 **同步阻塞** (FFI → C → 阻塞调用 JS),在 UI 线程里用要套 `Future` / `compute` / `Isolate`:

```dart
final r = await compute(() => api.playlist_detail(id: id), null);
```

---

## 3. 调用模式

每个方法本质都是 `request(path, query: ...)` 的薄壳,**所有方法都额外接这两个可选参数**:

```dart
MusicResponse xxx(
  String requiredArg,                       // 必选业务参数
  {                                           // 可选业务参数
    String? optArg,
    Map<String, String> cookie = const {},   // 单次调用 cookie 覆盖
    NcmProcessEnv? env,                      // 单次调用 env 覆盖 (高级)
  }
)
```

### Cookie 管理

SDK 内部有一个全局 cookie map (`_cookie`),**登录成功后必须把后端返回的 cookie 灌进去**,后续调用才会带上身份:

```dart
final r = await compute(() => api.login_cellphone(phone: '138xxx', password: 'xxx'), null);
api.set_cookie({
  'MUSIC_U': extractCookie(r.cookies, 'MUSIC_U'),
  '__csrf': extractCookie(r.cookies, '__csrf'),
  // ... 其他需要的字段
});
```

不登录也能用大部分接口(只读的歌单/歌曲/搜索),但有限制:
- `personal_fm`、`like`、`recommend_songs` 等需要用户身份 → 触发 400 "需要登录"
- 部分 VIP 内容需要 VIP cookie

### 写操作需要登录 cookie

所有写接口(收藏 / 评论 / 创建歌单 / 上传头像 / 关注 ...)**必须带 cookie**,否则会 301/400/403。

### 单次 cookie 覆盖

如果只想某次调用临时换 cookie 而不动全局,可以走 `cookie:` 参数:

```dart
api.search(keywords: '周杰伦', cookie: someOtherCookie);
```

---

## 4. 接口完整索引

> 共 **335 个** 方法,按业务分类列出。每个方法的:
> - **路径**: 网易官方接口路径(可对照 [binaryify/NeteaseCloudMusicApi](https://binaryify.github.io/NeteaseCloudMusicApi/#/) 看返回结构)
> - **签名**: Dart 端的方法签名
> - **说明**: 一句话简介(摘自上游 SDK 注释)

### 登录 / 注册

#### `activate_init_profile` → `/activate/init/profile`

- **签名**: `(String nickname, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 初始化昵称

#### `captcha_sent` → `/captcha/sent`

- **签名**: `(String phone, {String? ctcode, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 发送验证码

#### `captcha_verify` → `/captcha/verify`

- **签名**: `(String phone, String captcha, {String? ctcode, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 验证验证码

#### `cellphone_existence_check` → `/cellphone/existence/check`

- **签名**: `(String phone, {String? countrycode, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 检测手机号码是否已注册

#### `login` → `/login`

- **签名**: `(String email, String password, {String? md5_password, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: email: 163 网易邮箱

#### `login_cellphone` → `/login/cellphone`

- **签名**: `(String phone, {String? password, String? countrycode, String? md5_password, String? captcha, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: phone: 手机号码

#### `login_qr_check` → `/login/qr/check`

- **签名**: `(String key, {String? noCookie, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: (无描述)

#### `login_qr_create` → `/login/qr/create`

- **签名**: `(String key, {String? qrimg, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: (无描述)

#### `login_qr_key` → `—`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: (无描述)

#### `login_refresh` → `—`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 刷新登录

#### `login_status` → `—`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 登录状态

#### `logout` → `—`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 退出登录

#### `nickname_check` → `/nickname/check`

- **签名**: `(String nickname, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 重复昵称检测

#### `rebind` → `/rebind`

- **签名**: `(String oldcaptcha, String captcha, String phone, {String? ctcode, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 更换绑定手机

#### `register_anonimous` → `—`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 游客登录

#### `register_cellphone` → `/register/cellphone`

- **签名**: `(String captcha, String phone, String password, String nickname, {String? countrycode, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 注册(修改密码)


### 用户

#### `avatar_upload` → `/avatar/upload`

- **签名**: `({String? imgSize, String? imgX, String? imgY, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 更新头像

#### `countries_code_list` → `—`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 国家编码列表

#### `pl_count` → `/pl/count`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 私信和通知接口

#### `user_account` → `/user/account`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取账号信息

#### `user_audio` → `/user/audio`

- **签名**: `(String uid, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 用户电台

#### `user_binding` → `/user/binding`

- **签名**: `(String uid, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取用户绑定信息

#### `user_cloud` → `/user/cloud`

- **签名**: `({String? limit, String? offset, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 云盘

#### `user_cloud_del` → `/user/cloud/del`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 云盘歌曲删除

#### `user_cloud_detail` → `/user/cloud/detail`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 云盘数据详情

#### `user_comment_history` → `/user/comment/history`

- **签名**: `(String uid, {String? limit, String? time, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取用户历史评论

#### `user_detail` → `/user/detail`

- **签名**: `(String uid, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取用户详情

#### `user_dj` → `/user/dj`

- **签名**: `(String uid, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取用户电台

#### `user_event` → `/user/event`

- **签名**: `(String uid, {String? limit, String? lasttime, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取用户动态

#### `user_follow_mixed` → `/user/follow/mixed`

- **签名**: `({String? size, String? cursor, String? scene, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 当前账号关注的用户/歌手

#### `user_followeds` → `/user/followeds`

- **签名**: `(String uid, {String? limit, String? offset, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取用户粉丝列表

#### `user_follows` → `/user/follows`

- **签名**: `(String uid, {String? limit, String? offset, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取用户关注列表

#### `user_level` → `/user/level`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取用户等级信息

#### `user_medal` → `/user/medal`

- **签名**: `(String uid, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 用户徽章

#### `user_mutualfollow_get` → `/user/mutualfollow/get`

- **签名**: `(String uid, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 用户是否互相关注

#### `user_playlist` → `/user/playlist`

- **签名**: `(String uid, {String? limit, String? offset, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取用户歌单

#### `user_playlist_collect` → `/user/playlist/collect`

- **签名**: `(String uid, {String? limit, String? offset, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 用户的收藏歌单列表

#### `user_playlist_create` → `/user/playlist/create`

- **签名**: `(String uid, {String? limit, String? offset, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 用户的创建歌单列表

#### `user_record` → `/user/record`

- **签名**: `(String uid, {String? type, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取用户播放记录

#### `user_replacephone` → `/user/replacephone`

- **签名**: `(String phone, String oldcaptcha, String captcha, {String? countrycode, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 用户绑定手机

#### `user_social_status` → `/user/social/status`

- **签名**: `(String uid, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 用户状态

#### `user_social_status_edit` → `—`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 用户状态 - 编辑

#### `user_social_status_rcmd` → `—`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 用户状态 - 相同状态的用户

#### `user_social_status_support` → `—`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 用户状态 - 支持设置的状态

#### `user_subcount` → `/user/subcount`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取用户信息 , 歌单，收藏，mv, dj 数量

#### `user_update` → `/user/update`

- **签名**: `(String gender, String birthday, String nickname, String province, String city, String signature, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 更新用户信息


### 歌单

#### `comment_playlist` → `/comment/playlist`

- **签名**: `(String id, {String? limit, String? offset, String? before, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 歌单评论

#### `listentogether_sync_playlist_get` → `—`

- **签名**: `(String roomId, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 一起听相关

#### `playlist_catlist` → `/playlist/catlist`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 歌单分类

#### `playlist_cover_update` → `/playlist/cover/update`

- **签名**: `(String id, {String? imgSize, String? imgX, String? imgY, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 歌单封面上传

#### `playlist_create` → `/playlist/create`

- **签名**: `(String name, {String? privacy, String? type, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 新建歌单

#### `playlist_delete` → `/playlist/delete`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 删除歌单

#### `playlist_desc_update` → `/playlist/desc/update`

- **签名**: `(String id, String desc, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 更新歌单描述

#### `playlist_detail` → `/playlist/detail`

- **签名**: `(String id, {String? s, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取歌单详情

#### `playlist_detail_dynamic` → `/playlist/detail/dynamic`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 歌单详情动态

#### `playlist_detail_rcmd_get` → `/playlist/detail/rcmd/get`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 相关歌单推荐

#### `playlist_highquality_tags` → `/playlist/highquality/tags`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 精品歌单标签列表

#### `playlist_hot` → `/playlist/hot`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 热门歌单分类

#### `playlist_import_name_task_create` → `/playlist/import/name/task/create`

- **签名**: `({String? importStarPlaylist, String? playlistName, String? local, String? text, String? link, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 歌单导入 - 元数据/文字/链接导入

#### `playlist_import_task_status` → `/playlist/import/task/status`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 歌单导入 - 任务状态

#### `playlist_mylike` → `/playlist/mylike`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取点赞过的视频

#### `playlist_name_update` → `/playlist/name/update`

- **签名**: `(String id, String name, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 更新歌单名

#### `playlist_order_update` → `/playlist/order/update`

- **签名**: `(String ids, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 调整歌单顺序

#### `playlist_privacy` → `—`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 公开隐私歌单

#### `playlist_subscribe` → `/playlist/subscribe`

- **签名**: `(String t, String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 收藏/取消收藏歌单

#### `playlist_subscribers` → `/playlist/subscribers`

- **签名**: `(String id, {String? limit, String? offset, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 歌单收藏者

#### `playlist_tags_update` → `/playlist/tags/update`

- **签名**: `(String id, String tags, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 更新歌单标签

#### `playlist_track_add` → `/playlist/track/add`

- **签名**: `(String pid, String ids, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 收藏视频到视频歌单

#### `playlist_track_all` → `/playlist/track/all`

- **签名**: `(String id, {String? limit, String? offset, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取歌单所有歌曲

#### `playlist_track_delete` → `/playlist/track/delete`

- **签名**: `(String pid, String ids, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 删除视频歌单里的视频

#### `playlist_tracks` → `/playlist/tracks`

- **签名**: `(String op, String pid, String tracks, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 对歌单添加或删除歌曲

#### `playlist_update` → `/playlist/update`

- **签名**: `(String id, String name, String desc, String tags, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 更新歌单

#### `playlist_update_playcount` → `/playlist/update/playcount`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 歌单更新播放量

#### `playlist_video_recent` → `/playlist/video/recent`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 最近播放的视频

#### `record_recent_playlist` → `/record/recent/playlist`

- **签名**: `({String? limit, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 最近播放-歌单

#### `related_playlist` → `/related/playlist~~`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 相关歌单

#### `send_playlist` → `/send/playlist`

- **签名**: `(String user_ids, String msg, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 发送私信(带歌单)

#### `simi_playlist` → `/simi/playlist`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取相似歌单

#### `style_playlist` → `/style/playlist`

- **签名**: `(String tagId, {String? size, String? cursor, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 曲风-歌单

#### `top_playlist` → `/top/playlist`

- **签名**: `({String? order, String? cat, String? limit, String? offset, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 歌单 ( 网友精选碟 )

#### `top_playlist_highquality` → `/top/playlist/highquality`

- **签名**: `({String? cat, String? limit, String? before, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取精品歌单


### 歌曲

#### `check_music` → `/check/music`

- **签名**: `(String id, {String? br, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 音乐是否可用

#### `song_chorus` → `/song/chorus`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 副歌时间

#### `song_detail` → `/song/detail`

- **签名**: `(String ids, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取歌曲详情

#### `song_downlist` → `/song/downlist`

- **签名**: `({String? limit, String? offset, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 会员下载歌曲记录

#### `song_download_url` → `—`

- **签名**: `(String id, {String? br, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取客户端歌曲下载 url

#### `song_dynamic_cover` → `/song/dynamic/cover`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 歌曲动态封面

#### `song_like_check` → `/song/like/check`

- **签名**: `(String ids, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 歌曲是否喜爱

#### `song_lyrics_mark` → `/song/lyrics/mark`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 歌词摘录 - 歌词摘录信息

#### `song_lyrics_mark_add` → `—`

- **签名**: `(String id, String data, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 歌词摘录 - 添加/修改摘录歌词

#### `song_lyrics_mark_del` → `/song/lyrics/mark/del`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 歌词摘录 - 删除摘录歌词

#### `song_lyrics_mark_user_page` → `/song/lyrics/mark/user/page`

- **签名**: `({String? limit, String? offset, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 歌词摘录 - 我的歌词本

#### `song_monthdownlist` → `/song/monthdownlist`

- **签名**: `({String? limit, String? offset, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 会员本月下载歌曲记录

#### `song_music_detail` → `/song/music/detail`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 歌曲音质详情

#### `song_order_update` → `/song/order/update`

- **签名**: `(String pid, String ids, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 调整歌曲顺序

#### `song_purchased` → `/song/purchased`

- **签名**: `({String? limit, String? offset, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 已购单曲

#### `song_red_count` → `/song/red/count`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 歌曲红心数量

#### `song_singledownlist` → `/song/singledownlist`

- **签名**: `({String? limit, String? offset, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 已购买单曲

#### `song_url` → `/song/url`

- **签名**: `(String id, {String? br, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取音乐 url

#### `song_wiki_summary` → `/song/wiki/summary`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 音乐百科 - 简要信息

#### `top_song` → `/top/song`

- **签名**: `(String type, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 新歌速递


### 歌词

#### `lyric` → `/lyric`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取歌词

#### `lyric_new` → `/lyric/new`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取逐字歌词


### 专辑

#### `album` → `/album`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取专辑内容

#### `album_detail` → `/album/detail`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 数字专辑详情

#### `album_detail_dynamic` → `/album/detail/dynamic`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 专辑动态信息

#### `album_list` → `/album/list`

- **签名**: `({String? limit, String? offset, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 数字专辑-新碟上架

#### `album_list_style` → `/album/list/style`

- **签名**: `({String? limit, String? offset, String? area, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 数字专辑-语种风格馆

#### `album_new` → `/album/new`

- **签名**: `({String? limit, String? offset, String? area, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 全部新碟

#### `album_newest` → `/album/newest`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 最新专辑

#### `album_privilege` → `/album/privilege`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取专辑歌曲的音质

#### `album_songsaleboard` → `/album_songsaleboard`

- **签名**: `({String? limit, String? offset, String? albumType, String? type, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 数字专辑&数字单曲-榜单

#### `album_sub` → `/album/sub`

- **签名**: `(String id, String t, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 收藏/取消收藏专辑

#### `album_sublist` → `/album/sublist`

- **签名**: `({String? limit, String? offset, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取已收藏专辑列表


### 艺人

#### `artist_album` → `/artist/album`

- **签名**: `(String id, {String? limit, String? offset, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取歌手专辑

#### `artist_desc` → `/artist/desc`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取歌手描述

#### `artist_detail` → `/artist/detail`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取歌手详情

#### `artist_detail_dynamic` → `/artist/detail/dynamic`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 歌手详情动态

#### `artist_fans` → `/artist/fans`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 歌手粉丝

#### `artist_follow_count` → `/artist/follow/count`

- **签名**: `(String id, {String? limit, String? offset, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 歌手粉丝数量

#### `artist_list` → `/artist/list`

- **签名**: `({String? limit, String? offset, String? initial, String? type, String? area, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 歌手分类列表

#### `artist_mv` → `/artist/mv`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取歌手 mv

#### `artist_new_mv` → `/artist/new/mv`

- **签名**: `({String? limit, String? before, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 关注歌手新 MV

#### `artist_new_song` → `/artist/new/song`

- **签名**: `({String? limit, String? before, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 关注歌手新歌

#### `artist_songs` → `/artist/songs`

- **签名**: `(String id, {String? order, String? limit, String? offset, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 歌手全部歌曲

#### `artist_sub` → `/artist/sub`

- **签名**: `(String id, String t, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 收藏/取消收藏歌手

#### `artist_sublist` → `/artist/sublist`

- **签名**: `({String? limit, String? offset, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 收藏的歌手列表

#### `artist_top_song` → `/artist/top/song`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 歌手热门 50 首歌曲

#### `artist_video` → `/artist/video`

- **签名**: `(String id, {String? size, String? cursor, String? order, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取歌手视频

#### `artists` → `/artists`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取歌手单曲

#### `simi_artist` → `/simi/artist`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取相似歌手

#### `simi_mv` → `/simi/mv`

- **签名**: `(String mvid, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 相似 mv

#### `simi_song` → `/simi/song`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取相似音乐

#### `simi_user` → `/simi/user`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取最近 5 个听了这首歌的用户


### 视频 / MV / 直播

#### `broadcast_category_region_get` → `/broadcast/category/region/get`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 广播电台 - 分类/地区信息

#### `broadcast_channel_collect_list` → `/broadcast/channel/collect/list`

- **签名**: `({String? limit, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 广播电台 - 我的收藏

#### `broadcast_channel_currentinfo` → `/broadcast/channel/currentinfo`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 广播电台 - 电台信息

#### `broadcast_channel_list` → `/broadcast/channel/list`

- **签名**: `({String? categoryId, String? regionId, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 广播电台 - 全部电台

#### `mlog_music_rcmd` → `—`

- **签名**: `(String songid, {String? mvid, String? limit, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 歌曲相关视频

#### `mlog_to_video` → `/mlog/to/video`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 将 mlog id 转为视频 id

#### `mlog_url` → `/mlog/url`

- **签名**: `(String id, {String? res, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取 mlog 播放地址

#### `mv_all` → `/mv/all`

- **签名**: `({String? area, String? type, String? order, String? limit, String? offset, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 全部 mv

#### `mv_detail` → `/mv/detail`

- **签名**: `(String mvid, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取 mv 数据

#### `mv_detail_info` → `/mv/detail/info`

- **签名**: `(String mvid, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取 mv 点赞转发评论数数据

#### `mv_exclusive_rcmd` → `/mv/exclusive/rcmd`

- **签名**: `({String? limit, String? offset, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 网易出品 mv

#### `mv_first` → `/mv/first`

- **签名**: `({String? area, String? limit, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 最新 mv

#### `mv_sub` → `/mv/sub`

- **签名**: `(String mvid, String t, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 收藏/取消收藏 MV

#### `mv_sublist` → `/mv/sublist`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 收藏的 MV 列表

#### `mv_url` → `/mv/url`

- **签名**: `(String id, {String? r, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: mv 地址

#### `video_category_list` → `/video/category/list`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取视频分类列表

#### `video_detail` → `/video/detail`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 视频详情

#### `video_detail_info` → `/video/detail/info`

- **签名**: `(String vid, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取视频点赞转发评论数数据

#### `video_group` → `/video/group`

- **签名**: `(String id, {String? offset, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取视频标签/分类下的视频

#### `video_group_list` → `/video/group/list`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取视频标签列表

#### `video_sub` → `/video/sub`

- **签名**: `(String id, String t, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 收藏视频

#### `video_timeline_all` → `/video/timeline/all`

- **签名**: `({String? offset, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取全部视频列表

#### `video_timeline_recommend` → `/video/timeline/recommend`

- **签名**: `({String? offset, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取推荐视频

#### `video_url` → `/video/url`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取视频播放地址


### 电台 / 声音

#### `dj_banner` → `/dj/banner`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 电台 banner

#### `dj_category_excludehot` → `/dj/category/excludehot`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 电台 - 非热门类型

#### `dj_category_recommend` → `/dj/category/recommend`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 电台 - 推荐类型

#### `dj_catelist` → `/dj/catelist`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 电台 - 分类

#### `dj_detail` → `/dj/detail`

- **签名**: `(String rid, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 电台 - 详情

#### `dj_hot` → `/dj/hot`

- **签名**: `({String? limit, String? offset, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 热门电台

#### `dj_paygift` → `/dj/paygift`

- **签名**: `({String? limit, String? offset, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 电台 - 付费精选

#### `dj_personalize_recommend` → `/dj/personalize/recommend`

- **签名**: `({String? limit, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 电台个性推荐

#### `dj_program` → `/dj/program`

- **签名**: `(String rid, {String? limit, String? offset, String? asc, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 电台 - 节目

#### `dj_program_detail` → `/dj/program/detail`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 电台 - 节目详情

#### `dj_program_toplist` → `/dj/program/toplist`

- **签名**: `({String? limit, String? offset, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 电台 - 节目榜

#### `dj_program_toplist_hours` → `/dj/program/toplist/hours`

- **签名**: `({String? limit, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 电台 - 24 小时节目榜

#### `dj_radio_hot` → `/dj/radio/hot`

- **签名**: `({String? limit, String? offset, String? cateId, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 电台 - 类别热门电台

#### `dj_recommend` → `/dj/recommend`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 电台 - 推荐

#### `dj_recommend_type` → `/dj/recommend/type`

- **签名**: `(String type, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 电台 - 分类推荐

#### `dj_sub` → `/dj/sub`

- **签名**: `(String rid, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 电台 - 订阅

#### `dj_sublist` → `/dj/sublist`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 电台的订阅列表

#### `dj_subscriber` → `/dj/subscriber`

- **签名**: `(String id, {String? time, String? limit, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 电台订阅者列表

#### `dj_today_perfered` → `/dj/today/perfered`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 电台 - 今日优选

#### `dj_toplist` → `/dj/toplist`

- **签名**: `({String? limit, String? offset, String? type, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 电台 - 新晋电台榜/热门电台榜

#### `dj_toplist_hours` → `/dj/toplist/hours`

- **签名**: `({String? limit, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 电台 - 24 小时主播榜

#### `dj_toplist_newcomer` → `/dj/toplist/newcomer`

- **签名**: `({String? limit, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 电台 - 主播新人榜

#### `dj_toplist_pay` → `/dj/toplist/pay`

- **签名**: `({String? limit, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 电台 - 付费精品

#### `dj_toplist_popular` → `/dj/toplist/popular`

- **签名**: `({String? limit, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 电台 - 最热主播榜

#### `voice_delete` → `/voice/delete`

- **签名**: `(String ids, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 播客删除

#### `voice_detail` → `/voice/detail`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 播客声音详情

#### `voice_lyric` → `/voice/lyric`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取声音歌词

#### `voice_upload` → `/voice/upload`

- **签名**: `(String voiceListId, String coverImgId, String categoryId, String secondCategoryId, String description, {String? songName, String? privacy, String? publishTime, String? autoPublish, String? autoPublishText, String? orderNo, String? composedSongs, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 播客上传声音

#### `voicelist_detail` → `/voicelist/detail`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 播客列表详情

#### `voicelist_list` → `/voicelist/list`

- **签名**: `(String voiceListId, {String? limit, String? offset, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 播客声音列表

#### `voicelist_list_search` → `/voicelist/list/search`

- **签名**: `({String? displayStatus, String? limit, String? name, String? offset, String? radioId, String? type, String? voiceFeeType, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 播客声音搜索

#### `voicelist_search` → `/voicelist/search`

- **签名**: `({String? limit, String? offset, String? podcastName, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 播客列表

#### `voicelist_trans` → `/voicelist/trans`

- **签名**: `(String limit, String offset, String position, String programId, String radioId, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 播客声音排序


### 排行榜

#### `top_album` → `/top/album`

- **签名**: `({String? area, String? type, String? year, String? month, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 新碟上架

#### `top_artists` → `/top/artists`

- **签名**: `({String? limit, String? offset, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 热门歌手

#### `top_list` → `/top/list~~`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 排行榜详情

#### `top_mv` → `/top/mv`

- **签名**: `({String? limit, String? area, String? offset, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: mv 排行

#### `toplist` → `/toplist`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 所有榜单

#### `toplist_artist` → `/toplist/artist`

- **签名**: `({String? type, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 歌手榜

#### `toplist_detail` → `/toplist/detail`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 所有榜单内容摘要


### 搜索

#### `search` → `/search`

- **签名**: `(String keywords, {String? limit, String? offset, String? type, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 搜索

#### `search_default` → `—`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 默认搜索关键词

#### `search_hot` → `/search/hot`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 热搜列表(简略)

#### `search_hot_detail` → `/search/hot/detail`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 热搜列表(详细)

#### `search_match` → `/search/match`

- **签名**: `(String title, String album, String artist, String duration, String md5, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 本地歌曲文件匹配网易云歌曲信息

#### `search_multimatch` → `/search/multimatch`

- **签名**: `(String keywords, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 搜索多重匹配

#### `search_suggest` → `/search/suggest`

- **签名**: `(String keywords, {String? type, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 搜索建议


### 评论

#### `comment` → `/comment`

- **签名**: `(String t, String type, String id, String content, {String? commentId, String? threadId, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 发送/删除评论

#### `comment_album` → `/comment/album`

- **签名**: `(String id, {String? limit, String? offset, String? before, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 专辑评论

#### `comment_dj` → `/comment/dj`

- **签名**: `(String id, {String? limit, String? offset, String? before, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 电台节目评论

#### `comment_event` → `/comment/event`

- **签名**: `(String threadId, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取动态评论

#### `comment_floor` → `/comment/floor`

- **签名**: `(String parentCommentId, String id, String type, {String? limit, String? time, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 楼层评论

#### `comment_hot` → `/comment/hot`

- **签名**: `(String id, String type, {String? limit, String? offset, String? before, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 热门评论

#### `comment_hotwall_list` → `/comment/hotwall/list`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 云村热评(官方下架,暂不能用)

#### `comment_hug_list` → `/comment/hug/list`

- **签名**: `(String uid, String cid, String sid, {String? page, String? cursor, String? idCursor, String? pageSize, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 评论抱一抱列表

#### `comment_like` → `/comment/like`

- **签名**: `(String id, String cid, String t, String type, {String? threadId, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 给评论点赞

#### `comment_music` → `/comment/music`

- **签名**: `(String id, {String? limit, String? offset, String? before, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 歌曲评论

#### `comment_mv` → `/comment/mv`

- **签名**: `(String id, {String? limit, String? offset, String? before, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: mv 评论

#### `comment_new` → `/comment/new`

- **签名**: `(String id, String type, {String? pageNo, String? pageSize, String? sortType, String? cursor, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 新版评论接口

#### `comment_video` → `/comment/video`

- **签名**: `(String id, {String? limit, String? offset, String? before, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 视频评论

#### `hug_comment` → `/hug/comment`

- **签名**: `(String uid, String cid, String sid, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 抱一抱评论


### 动态 / 话题

#### `event` → `/event`

- **签名**: `(String pagesize, String lasttime, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取动态列表

#### `event_del` → `/event/del`

- **签名**: `(String evId, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 删除用户动态

#### `event_forward` → `/event/forward`

- **签名**: `(String uid, String evId, String forwards, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 转发用户动态

#### `hot_topic` → `/hot/topic`

- **签名**: `({String? limit, String? offset, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取热门话题

#### `share_resource` → `/share/resource`

- **签名**: `(String id, {String? type, String? msg, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 分享文本、歌曲、歌单、mv、电台、电台节目到动态

#### `topic_detail` → `/topic/detail`

- **签名**: `({String? actid, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取话题详情

#### `topic_detail_event_hot` → `/topic/detail/event/hot`

- **签名**: `({String? actid, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取话题详情热门动态

#### `topic_sublist` → `/topic/sublist`

- **签名**: `({String? limit, String? offset, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 收藏的专栏


### 关注

#### `follow` → `/follow`

- **签名**: `(String id, String t, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 关注/取消关注用户


### 播放模式

#### `playmode_intelligence_list` → `/playmode/intelligence/list`

- **签名**: `(String id, String pid, {String? sid, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 心动模式/智能播放


### 私信

#### `msg_comments` → `/msg/comments`

- **签名**: `(String uid, {String? limit, String? before, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 通知 - 评论

#### `msg_forwards` → `/msg/forwards`

- **签名**: `({String? limit, String? offset, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 通知 - @我

#### `msg_notices` → `/msg/notices`

- **签名**: `({String? limit, String? lasttime, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 通知 - 通知

#### `msg_private` → `/msg/private`

- **签名**: `({String? limit, String? offset, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 通知 - 私信

#### `msg_private_history` → `////msg/private/history`

- **签名**: `(String uid, {String? limit, String? before, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 私信内容

#### `msg_recentcontact` → `/msg/recentcontact`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 最近联系人

#### `send_album` → `/send/album`

- **签名**: `(String user_ids, String id, String msg, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 发送私信(带专辑)

#### `send_song` → `/send/song`

- **签名**: `(String user_ids, String id, String msg, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 发送私信(带歌曲)

#### `send_text` → `/send/text`

- **签名**: `(String user_ids, String msg, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 发送私信


### 云盘

#### `cloud` → `/cloud`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 云盘上传

#### `cloud_import` → `/cloud/import`

- **签名**: `(String song, String fileType, String fileSize, String bitrate, String md5, {String? id, String? artist, String? album, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 云盘导入歌曲

#### `cloud_match` → `/cloud/match`

- **签名**: `(String uid, String sid, String asid, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 云盘歌曲信息匹配纠正


### 云贝

#### `yunbei` → `/yunbei`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 云贝

#### `yunbei_info` → `/yunbei/info`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 云贝账户信息

#### `yunbei_rcmd_song` → `/yunbei/rcmd/song`

- **签名**: `(String id, {String? reason, String? yunbeiNum, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 云贝推歌

#### `yunbei_rcmd_song_history` → `/yunbei/rcmd/song/history`

- **签名**: `({String? size, String? cursor, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 云贝推歌历史记录

#### `yunbei_sign` → `/yunbei/sign`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 云贝签到

#### `yunbei_task_finish` → `/yunbei/task/finish`

- **签名**: `(String userTaskId, {String? depositCode, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 云贝完成任务

#### `yunbei_tasks` → `/yunbei/tasks`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 云贝所有任务

#### `yunbei_tasks_expense` → `/yunbei/tasks/expense`

- **签名**: `({String? limit, String? offset, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 云贝支出

#### `yunbei_tasks_receipt` → `/yunbei/tasks/receipt`

- **签名**: `({String? limit, String? offset, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 云贝收入

#### `yunbei_tasks_todo` → `/yunbei/tasks/todo`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 云贝 todo 任务

#### `yunbei_today` → `/yunbei/today`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 云贝今日签到信息


### VIP

#### `vip_growthpoint` → `/vip/growthpoint`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: vip 成长值

#### `vip_growthpoint_details` → `/vip/growthpoint/details`

- **签名**: `({String? limit, String? offset, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: vip 成长值获取记录

#### `vip_growthpoint_get` → `/vip/growthpoint/get`

- **签名**: `(String ids, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 领取 vip 成长值

#### `vip_info` → `/vip/info`

- **签名**: `({String? uid, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取 VIP 信息

#### `vip_tasks` → `/vip/tasks`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: vip 任务

#### `vip_timemachine` → `/vip/timemachine`

- **签名**: `({String? startTime, String? endTime, String? limit, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 黑胶时光机


### 音乐人

#### `musician_cloudbean` → `/musician/cloudbean`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 账号云豆数

#### `musician_cloudbean_obtain` → `/musician/cloudbean/obtain`

- **签名**: `(String id, String period, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 领取云豆

#### `musician_data_overview` → `/musician/data/overview`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 音乐人数据概况

#### `musician_play_trend` → `/musician/play/trend`

- **签名**: `(String startTime, String endTime, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 音乐人播放趋势

#### `musician_sign` → `/musician/sign`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 音乐人签到

#### `musician_tasks` → `/musician/tasks`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 音乐人任务

#### `musician_tasks_new` → `/musician/tasks/new`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 音乐人任务(新)


### UGC

#### `ugc_album_get` → `/ugc/album/get`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 专辑简要百科信息

#### `ugc_artist_get` → `/ugc/artist/get`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 歌手简要百科信息

#### `ugc_artist_search` → `/ugc/artist/search`

- **签名**: `(String keyword, {String? limit, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 搜索歌手

#### `ugc_detail` → `/ugc/detail`

- **签名**: `(String type, {String? limit, String? offset, String? auditStatus, String? order, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 用户贡献内容

#### `ugc_mv_get` → `/ugc/mv/get`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: mv简要百科信息

#### `ugc_song_get` → `/ugc/song/get`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 歌曲简要百科信息

#### `ugc_user_devote` → `/ugc/user/devote`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 用户贡献条目、积分、云贝数量


### 风格

#### `style_album` → `/style/album`

- **签名**: `(String tagId, {String? size, String? cursor, String? sort, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 曲风-专辑

#### `style_artist` → `/style/artist`

- **签名**: `(String tagId, {String? size, String? cursor, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 曲风-歌手

#### `style_detail` → `/style/detail`

- **签名**: `(String tagId, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 曲风详情

#### `style_list` → `/style/list`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 曲风列表

#### `style_preference` → `/style/preference`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 曲风偏好

#### `style_song` → `/style/song`

- **签名**: `(String tagId, {String? size, String? cursor, String? sort, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 曲风-歌曲


### 乐谱

#### `sheet_list` → `/sheet/list`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 乐谱列表

#### `sheet_preview` → `/sheet/preview`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 乐谱内容


### 设置 / Banner

#### `banner` → `/banner`

- **签名**: `({String? type, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: banner

#### `setting` → `/setting`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 设置


### 个性化推荐

#### `daily_signin` → `/daily_signin`

- **签名**: `({String? type, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 签到

#### `fm_trash` → `/fm_trash`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 垃圾桶

#### `history_recommend_songs` → `/history/recommend/songs`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取历史日推可用日期列表

#### `history_recommend_songs_detail` → `/history/recommend/songs/detail`

- **签名**: `(String date, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取历史日推详情数据

#### `like` → `/like`

- **签名**: `(String id, {String? like, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 喜欢音乐

#### `likelist` → `/likelist`

- **签名**: `(String uid, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 喜欢音乐列表

#### `personal_fm` → `/personal_fm`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 私人 FM

#### `personal_fm_mode` → `—`

- **签名**: `(String mode, {String? submode, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 私人 FM 模式选择

#### `personalized` → `/personalized`

- **签名**: `({String? limit, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 推荐歌单

#### `personalized_djprogram` → `/personalized/djprogram`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 推荐电台

#### `personalized_mv` → `/personalized/mv`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 推荐 mv

#### `personalized_newsong` → `/personalized/newsong`

- **签名**: `({String? limit, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 推荐新音乐

#### `personalized_privatecontent` → `/personalized/privatecontent`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 独家放送(入口列表)

#### `personalized_privatecontent_list` → `/personalized/privatecontent/list`

- **签名**: `({String? limit, String? offset, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 独家放送列表

#### `program_recommend` → `/program/recommend`

- **签名**: `({String? limit, String? offset, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 推荐节目

#### `recommend_resource` → `/recommend/resource`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取每日推荐歌单

#### `recommend_songs` → `/recommend/songs`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 获取每日推荐歌曲

#### `recommend_songs_dislike` → `/recommend/songs/dislike`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 每日推荐歌曲-不感兴趣

#### `sign_happy_info` → `—`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 乐签信息


### 一起听

#### `listentogether_accept` → `—`

- **签名**: `(String roomId, String inviterId, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 一起听相关

#### `listentogether_end` → `—`

- **签名**: `(String roomId, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 一起听相关

#### `listentogether_play_command` → `—`

- **签名**: `(String roomId, String progress, String commandType, String formerSongId, String targetSongId, String clientSeq, String playStatus, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 一起听相关

#### `listentogether_room_check` → `—`

- **签名**: `(String roomId, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 一起听相关

#### `listentogether_room_create` → `—`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 一起听相关

#### `listentogether_status` → `—`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 一起听相关

#### `listentogether_sync_list_command` → `—`

- **签名**: `(String roomId, String commandType, String userId, String version, String playMode, String displayList, String randomList, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 一起听相关


### 验证 / 匹配

#### `audio_match` → `/audio/match`

- **签名**: `(String duration, String audioFP, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 听歌识曲

#### `get_userids` → `/get/userids`

- **签名**: `(String nicknames, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 根据nickname获取userid

#### `verify_qrcodestatus` → `/verify/qrcodestatus`

- **签名**: `(String qr, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 验证接口-二维码检测


### 其他 / 统计

#### `aidj_content_rcmd` → `/aidj/content/rcmd`

- **签名**: `({String? longitude, String? latitude, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 私人 DJ

#### `inner_version` → `/inner/version`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 内部版本接口

#### `listen_data_realtime_report` → `/listen/data/realtime/report`

- **签名**: `(String type, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 听歌足迹 - 本周/本月收听时长

#### `listen_data_report` → `/listen/data/report`

- **签名**: `(String type, {String? endTime, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 听歌足迹 - 周/月/年收听报告

#### `listen_data_today_song` → `—`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 听歌足迹 - 今日收听

#### `listen_data_total` → `—`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 听歌足迹 - 总收听时长

#### `listen_data_year_report` → `—`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 听歌足迹 - 年度听歌足迹

#### `music_first_listen_info` → `/music/first/listen/info`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 回忆坐标

#### `recent_listen_list` → `—`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 最近听歌列表

#### `record_recent_album` → `/record/recent/album`

- **签名**: `({String? limit, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 最近播放-专辑

#### `record_recent_dj` → `/record/recent/dj`

- **签名**: `({String? limit, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 最近播放-播客

#### `record_recent_song` → `/record/recent/song`

- **签名**: `({String? limit, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 最近播放-歌曲

#### `record_recent_video` → `/record/recent/video`

- **签名**: `({String? limit, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 最近播放-视频

#### `record_recent_voice` → `/record/recent/voice`

- **签名**: `({String? limit, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 最近播放-声音

#### `signin_progress` → `/signin/progress`

- **签名**: `({String? moduleId, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 签到进度

#### `starpick_comments_summary` → `—`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 云村星评馆 - 简要评论

#### `summary_annual` → `/summary/annual`

- **签名**: `(String year, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 年度听歌报告


### 其他

#### `batch` → `/batch`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: batch 批量请求接口

#### `calendar` → `/calendar`

- **签名**: `(String startTime, String endTime, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 音乐日历

#### `homepage_block_page` → `/homepage/block/page`

- **签名**: `({String? refresh, String? cursor, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 首页-发现

#### `homepage_dragon_ball` → `—`

- **签名**: `({Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 首页-发现-圆形图标入口列表

#### `related_allvideo` → `/related/allvideo`

- **签名**: `(String id, {Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 相关视频

#### `resource_like` → `/resource/like`

- **签名**: `(String type, String t, {String? id, String? threadId, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 资源点赞( MV,电台,视频)

#### `scrobble` → `/scrobble`

- **签名**: `(String id, String sourceid, {String? time, Map<String, String> cookie = const {}, NcmProcessEnv? env})`
- **说明**: 听歌打卡



---

## 5. 常用流程示例

### 5.1 匿名访问(游客)

SDK 构造时不传 env → 内部会自动生成 `cnIp` + `anonymousToken`,大部分只读接口都能直接调:

```dart
final api = NeteaseCloudMusicApi();

// 搜索
final search = await compute(() => api.search(keywords: '周杰伦', type: '1'), null);

// 取歌单详情(公开歌单)
final pl = await compute(() => api.playlist_detail(id: '1234567890'), null);

// 取歌手信息
final artist = await compute(() => api.artists(id: '6452'), null); // 周杰伦
final songs = await compute(() => api.artist_songs(id: '6452'), null);
final albums = await compute(() => api.artist_album(id: '6452'), null);
```

### 5.2 二维码登录

```dart
// 1. 生成 key
final keyRes = await compute(() => api.login_qr_key(), null);
final key = keyRes.body['data']['unikey'] as String;

// 2. 生成二维码图片 base64
final qrRes = await compute(() => api.login_qr_create(key: key, qrimg: '1'), null);
final qrBase64 = qrRes.body['data']['qrimg'] as String;
Image.memory(base64Decode(qrBase64.split(',').last));

// 3. 轮询扫码状态(800 过期 / 801 待扫码 / 802 待确认 / 803 登录成功)
final check = await compute(() => api.login_qr_check(key: key), null);
final code = check.body['code'];
if (code == 803) {
  api.set_cookie(parseCookieString(check.body['cookie'] as String));
}
```

### 5.3 取歌曲播放 URL

```dart
final r = await compute(() => api.song_url(id: '1234567', level: 'standard'), null);
// r.body['data'][0]['url'] → 临时 mp3 直链,有过期时间
```

### 5.4 拉歌单所有曲目(分页)

`playlist_detail` 默认只给前 1000 首,完整列表走 `playlist_track_all`:

```dart
final all = await compute(() => api.playlist_track_all(id: 'xxx'), null);
// all.body['songs'] → List<Map>
```

### 5.5 搜索(type 参数)

```dart
// 1: 单曲 / 10: 专辑 / 100: 艺人 / 1000: 歌单 / 1002: 用户 / 1004: MV / 1006: 歌词 / 1009: 电台 / 1014: 视频
final songs = await compute(() => api.search(keywords: '周杰伦', type: '1', limit: 30), null);
final artists = await compute(() => api.search(keywords: '周杰伦', type: '100'), null);
```

---

## 6. 注意事项

### 6.1 风控

- **不要频繁调登录接口**(被风控会要求扫码验证)
- **不要高频调 `personal_fm`**(单次最多给一首,后端会限流)
- `scrobble`(听歌打卡)别刷,封号

### 6.2 网易云盾

- 2024 年起密码登录大量触发云盾验证,**优先用**:
  - 二维码登录(`login_qr_*`)
  - 短信验证码登录(`captcha_sent` → `login_cellphone(phone, captcha)`)
  - 游客 cookie(`register_anonimous`)绕过验证

### 6.3 VIP / 版权

- 灰色歌曲(无版权) `song_url` 会返回 `url: null`,`fee: 1`
- 部分歌曲需要 VIP,`level` 参数切 `standard` / `exhigh` / `lossless` / `jymaster` 等

### 6.4 必选参数缺失

很多接口的必选参数在 Dart 端是 nullable(`String?`),SDK 不会编译期拦截。**调用前自己校验**,否则后端返 400 查不到原因。

### 6.5 资源释放

`api.dispose()` 会销毁 JSContext 并释放 native 内存。**测试 / 热重载场景**频繁创建 `NeteaseCloudMusicApi` 容易 OOM,建议全局单例。

### 6.6 已知 stub

- `lyric_new` 返回的逐字时间戳字段顺序跟上游 Python SDK 不一致(1=起始ms / 2=总时长ms / 3=逐字ms / 4=逐字cs / 5=未知 / 6=文字)
- `verify_qrcodestatus` 和 `verify_getQr` 是新版云盾验证接口,字段经常变

---

## 7. 对应本项目的接入点

当前 `SongListController` / `ArtistController` / `ArtistDetail` 都是 stub 数据,接入 SDK 时:

```dart
// SongListController.load 改成
final r = await compute(
  () => api.playlist_detail(id: playlistId),
  null,
);
if (r.status == 200 && r.body['code'] == 200) {
  final tracks = (r.body['playlist']['tracks'] as List)
      .cast<Map<String, dynamic>>()
      .map(Song.fromNeteaseJson)  // 自己写 fromJson
      .toList();
  songs.assignAll(tracks);
}

// ArtistController.load 拆成三步并行
final results = await Future.wait([
  compute(() => api.artists(id: artistId), null),
  compute(() => api.artist_album(id: artistId), null),
  compute(() => api.artist_songs(id: artistId), null),
]);
```

模型 `Song.fromNeteaseJson` / `Artist.fromNeteaseJson` / `Album.fromNeteaseJson` 之后另写,本项目目前模型在 `lib/PlayListPage/PlayListController.dart` 和 `lib/ArtistPage/{Artist,Album}.dart`。
