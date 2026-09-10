# flutter_netease_music

一个 Flutter 写的网易云音乐客户端,底层 API 来自
[`NeteaseCloudMusic_PythonSDK`](https://github.com/2061360308/NeteaseCloudMusic_PythonSDK)
([`MusicLibrary`](https://github.com/2061360308/MusicLibrary) 的 Dart 绑定)。

SDK 的架构是 **JavaScript → QuickJS (C) → Dart FFI** —— API 逻辑用
JavaScript/Node.js 实现,打包后由内嵌的 QuickJS 引擎通过 C ABI 执行,
再通过 `dart:ffi` 暴露给 Dart。预编译的原生库 (`libmusiclibrary.so` /
`.dll` / `.dylib`) 随包发布,只有约 2 MB。

## 特色

Flutter 原生跨平台

原生 UI , 性能优秀

仅音乐功能，去除广告、社区、视频、直播等非音乐功能

## 功能

- 搜索 / 歌单 / 专辑 / 艺人 / 我的收藏
- 后台播放 + 锁屏 / 通知栏控制(基于 `audio_service` + `just_audio`)
- 同步歌词(基于 `flutter_lyric`)
- 收藏的歌曲 / 专辑 / 艺人 / 歌单
- 亮 / 暗主题

## 跑起来

```bash
flutter pub get
flutter run                  # 选个设备
flutter analyze
```

Flutter SDK 约束:`^3.12.2`。`musiclibrary` 是本地 path 包
(`NeteaseCloudMusic_PythonSDK/src/dart`),API 细节见 `MUSICLIBRARY.md`。


### TODO

- 在linux上的状态栏歌词接口，应该与 YesPlayMusic / VutronMusic 在 KDE 的实现一致。
- 在MusicLibrary底层库能够解析xeapi后，添加对音质的选择，支持高音质播放。
- 提供音质选择功能后，会考虑提供下载功能。

## 项目结构

```
lib/
  main.dart                       # 启动入口:GetStorage → API → repos → wrapper → controllers
  AppShell.dart                   # 底部导航壳(发现 / 歌单 / 我的 / 设置)
  HomePage/                       # 发现 tab
  PlayListPage/                   # 歌单 tab
  SongListPage/                   # 复用的歌曲列表 UI:SongListBody / SongRowTile
  ArtistPage/                     # 艺人详情
  LibraryPage/                    # 我的
  SettingsPage/                   # 设置 + 登录
  PlayPage/                       # 全屏播放页(封面 + 歌词)
  searchPage/                     # 搜索
  sdk/
    NeteaseApi.dart               # 包 FFI SDK + 持久化 cookie
    AuthController.dart           # 全局 AuthInfo 持有者
    ApiCall.dart                  # 通用调用辅助
  services/
    AudioPlayerWrapper.dart       # AudioPlayerService —— 播放层唯一真相源
    AudioPlayerHandler.dart       # just_audio + audio_service 桥
    LikedController.dart          # 统一的收藏 controller(song / album / artist / playlist)
    repositories/                 # SongRepository / LyricsRepository / SearchRepository /
                                  # PlaylistRepository / AlbumRepository / ArtistRepository /
                                  # LibraryRepository / LikedRepository
  models/                         # Song / Album / Artist / Playlist / Snapshot / AuthInfo ...
  widgets/                        # SongCover / NeteaseImage / LinkedDetailText ...
  theme/                          # AppTheme + ThemeController
```

## 架构

### 分层

```
Widget
  └─ Page Controller(Obx 驱动的薄 facade,只存 UI 状态)
       └─ AudioPlayerService(wrapper —— 唯一真相源)
            ├─ AudioPlayerHandler  (just_audio + audio_service)
            └─ Repositories        (Song / Lyrics / Liked / ...)
                 └─ NeteaseApi    (FFI SDK)
```

- **Repositories** —— 被动的 API 调用者,不持 Rx,无 GetX 生命周期。
  通过构造函数注入 `NeteaseApi`。
- **AudioPlayerService (wrapper)** —— 播放相关全部入口都集中在这里。
  把状态聚合成 `Rx<PlaybackSnapshot>`,内部持有 `AudioPlayerHandler`。
- **AudioPlayerHandler** —— 实现 `BaseAudioHandler`,在
  `just_audio` ⇄ `audio_service` 之间架桥,主动把状态推推 wrapper。
- **Page controllers**(`PlayerController`、`LyricsController` ...)——
  薄 facade。用 `Obx` / `ever` 订阅 wrapper 的 snapshot,再把命令转发
  回 wrapper。**不重复存状态**。
- **LikedController** —— 一套 controller 管 4 种 类型(song / album /
  artist / playlist),按 `LikedType` 分桶,调用 `LikedRepository`。

### 启动顺序(`main.dart`)

顺序靠**构造函数注入**保证 —— 写错是编译报错,不是运行时崩:

1. `GetStorage.init()`
2. `ThemeController`(同步)
3. `initNeteaseApi()`—— 恢复持久化的 cookie
4. Repositories(需要 `NeteaseApi`)
5. `AuthController` —— `Get.putAsync` 让 `loadAuthInfo()` 在被使用前跑完
6. `LikedRepository` + `LikedController`
7. `AudioPlayerService` —— `Get.putAsync` + builder 内
   `await wrapper.init()`。**不要**先 `Get.put` 再单独 `await init()`
   (会留一个"已注册但还没初始化"的窗口);**不要**把异步逻辑放到
   `onInit` 里(GetX 的 `_onStart` 是同步调用并丢弃 future)。
8. `PlayerController`(`lazyPut`)和 `LyricsController`(`permanent` —
   `flutter_lyric` 自带的 `LyricController` 持有高亮 / 滚动位置,
   跨路由切换不重建才能保留这些状态)。

## 音频 + 锁屏行为

- `audio_service` 0.18.19 —— `QueueHandler.updateQueue` 在内部对缓存的
  `nvalue` 列表做原地修改。**传给 `super.updateQueue` 的必须是可变
  `List`**(比如 `_queue.toList()`),传 `List.unmodifiable()` 第二次
  `setQueue` 会直接炸。
- `preloadArtwork: false` —— 锁屏 / 通知封面按需下载。开 `true` 会让
  `_loadAllArtwork` 在后台 isolate 上并发迭代队列,下一次 `updateQueue`
  期间原地改 `nvalue` → `Concurrent modification during iteration`
  unhandled 异常。
- `AudioServiceConfig.androidCompactActionIndices` 在 Android 13+ 上
  **失效**:platform interface 在 `SDK_INT >= 33` 时跳过
  `setShowActionsInCompactView`,直接用 controls 列表前 3 个当 compact
  槽位。需要出现在锁屏的自定义按钮(如 `SongRowTile` 风格的 like)必须
  放在 controls 列表的前 3 位。
