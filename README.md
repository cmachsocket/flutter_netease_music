分析完成。我已经看完了核心的 service/controller 代码，下面给出完整的架构诊断和重构建议。

## 一、当前架构的核心问题

### 1. 分层边界模糊：Controller 持有 UI 组件的 controller

**最典型的就是 `LyricsController`**：

```dart
class LyricsController extends GetxController {
  final LyricController lyricController = LyricController(); // flutter_lyric 的 View 控制器
  ...
}
```

`LyricController` 是 `flutter_lyric` 库的 View 层对象（一堆 `ValueNotifier`，给 `LyricView` widget 用的）。它本质是 **UI 状态**，却被塞进了一个 `permanent: true` 的全局 GetX controller 里。

带来的问题：
- `LyricsController` 同时是"取歌词的控制器"和"歌词 View 的状态持有者"
- `onClose()` 里 `lyricController.dispose()` 永远不会执行（permanent 不销毁），资源管理形同虚设
- UI 生命周期和业务生命周期被强行绑死

### 2. `PlayerController` 是个"上帝控制器"

看它的成员就能发现职责爆炸：

```dart
class PlayerController extends GetxController {
  // 播放状态投影
  final Rx<Duration> position = ...;
  final Rx<Duration> duration = ...;
  final Rx<Duration> buffered = ...;
  final RxBool isPlaying = ...;
  final Rxn<Song> currentSong = ...;
  final RxBool isLoadingSong = ...;
  final RxBool isLiked = ...;

  // 队列同步
  bool _queueSyncScheduled = false;
  Worker? _queueIndexWorker;
  Worker? _queuePlaylistWorker;

  // 自动切歌
  bool _autoNextFired = false;
  bool _lastNearEnd = false;

  // 直接依赖所有东西
  final LikedSongsService _likedService = Get.find<LikedSongsService>();
  final NeteaseApi api = Get.find<NeteaseApi>();
  final PlayQueueService queue = Get.find<PlayQueueService>();
  late final AudioPlayerService _audio;
}
```

它同时承担了：
- **页面 UI 状态**（播放页要展示什么）
- **全局播放核心**（loadSong、next/prev、自动切歌）
- **队列同步编排**（监听 queue 变化去同步音频）
- **liked 状态联动**

### 3. 隐式依赖链脆弱

`main.dart` 里的注册顺序必须严格：

```dart
Get.put<LyricsService>(LyricsService(), permanent: true);      // 必须先
Get.put<PlayerController>(PlayerController(), permanent: true); // 然后这个
Get.put<LyricsController>(LyricsController(), permanent: true); // 最后这个
```

因为每个都通过 `Get.find<>()` 在字段初始化时直接拉取依赖。顺序错了直接运行时崩溃，没有任何编译期保护。

### 4. Liked 系列四个 Service 重复

`LikedSongsService`、`LikedAlbumsService`、`LikedArtistsService`、`LikedPlaylistsService` 结构几乎一样：
- 一个 `RxSet<String> likedIds`
- `fetch()` 从 API 拉数据
- `toggle()` 调用 API
- GetStorage 持久化

只有 API 端点和实体类型不同。

### 5. Service 直接依赖其他 Service

```dart
class LyricsService extends GetxService {
  final NeteaseApi _api = Get.find<NeteaseApi>(); // 直接横跳
}
```

Service 应该是**被动**的，依赖应该通过构造函数注入，而不是运行时全局查找。

---

## 二、重构目标架构

### 核心分层原则

```
UI Widget
   ↓
Page Controller（页面级，短命，UI 状态）
   ↓
Core Controller（全局级，long-lived，播放核心业务）
   ↓
Service（纯被动，无 UI 状态，不监听 Rx，不依赖其他 service）
   ↓
SDK / Repo（NetEase API、存储）
```

### 具体分类

| 层级 | 职责 | 生命周期 | 示例 |
|------|------|---------|------|
| **Service** | 纯被动：API 调用、缓存、持久化；**不订阅任何 Rx，不持有 UI 状态** | 全局 | `LyricsService`、`LikedSongsService` |
| **Core Controller** | 全局业务核心：播放队列、播放状态、自动切歌 | 全局 permanent | 新的 `PlaybackController` |
| **Page Controller** | 页面 UI 状态：当前 Tab、滚动位置、表单状态 | 页面级 | `PlayPageController`、`SearchController` |
| **Widget** | 纯渲染，通过 `Get.find` 或构造注入拿 Page Controller | 页面级 | `Lyrics`、`PlayerPage` |

### 重构后的骨架

```dart
// lib/core/playback/PlaybackController.dart  ← 新建
class PlaybackController extends GetxController {
  final AudioPlayerService _audio;      // 构造注入
  final PlayQueueService _queue;        // 构造注入
  final LikedSongsService _liked;       // 构造注入
  final NeteaseApi _api;                // 构造注入

  // 播放状态投影（UI 读这里）
  final Rx<Duration> position = ...;
  final Rx<Duration> duration = ...;
  final RxBool isPlaying = ...;
  final Rxn<Song> currentSong = ...;

  // 播放核心方法
  Future<void> loadSong(Song song);
  Future<void> next();
  Future<void> prev();
  Future<void> togglePlay();
  Future<void> seek(Duration p);

  // 自动切歌逻辑封装在私有方法
  void _onPlayerState(PlayerState state);
  void _onPositionChange(Duration p);
}
```

```dart
// lib/PlayPage/PlayPageController.dart  ← 页面级（新）
class PlayPageController extends GetxController {
  final center = CenterPage.cover.obs;   // 页面 UI 状态
  // 从 PlaybackController 读播放状态，不在本地重复存一份
}

// lib/PlayPage/LyricsWidget.dart 改名为 LyricsView
// 通过 Get.find<LyricsPageController>() 拿 View 专用的 LyricController
// LyricsPageController 是页面级，onClose 里正确 dispose
```

```dart
// lib/services/LyricsService.dart 保持，但依赖改为构造注入
class LyricsService extends GetxService {
  final NeteaseApi _api;
  LyricsService(this._api);  // 不再 Get.find
}
```

---

## 三、分阶段实施计划

### 阶段 1（低风险，现在就能做）

**目标**：在不改变外部行为的前提下消除最明显的架构异味

1. **Service 依赖改为构造注入**
   - `LyricsService`、`LikedSongsService` 等不再 `Get.find`，改为构造函数接收
   - `main.dart` 里 `Get.put<LyricsService>(LyricsService(api), permanent: true)`
   - 好处：依赖显式化，注册顺序错误会编译失败而不是运行时崩溃

2. **拆出 `PlaybackController`**
   - 把 `PlayerController` 里所有播放核心逻辑（loadSong、next/prev、自动切歌、进度投影）移到 `lib/core/playback/PlaybackController.dart`
   - `PlayerController` 只保留页面 UI 状态（center 切换），委托给 PlaybackController
   - 好处：其他页面（搜索、歌单）不再依赖页面目录下的 controller

3. **Liked 系列抽象基类**
   - 建 `lib/services/liked_collection_service.dart`，四个 service 继承它，只提供 endpoint 和实体类型
   - 好处：消除四份重复的 fetch/toggle/persist 代码

### 阶段 2（中等改动）

4. **`LyricsController` 拆分**
   - `LyricsPageController`（页面级，持有 `LyricController`，正确 dispose）
   - `LyricsService`（全局，纯取歌词，已有）
   - 页面级 controller 通过 `Get.put` 在进入 PlayPage 时注册，离开时销毁

5. **引入 Repository 层**（可选，如果 API 调用继续增多）
   - `SongRepository`、`LyricsRepository`、`LikedSongsRepository`
   - Service 不再直接调 `NeteaseApi`，而是通过 Repository
   - 方便 mock 和测试

### 阶段 3（完整重构，耗时较长）

6. **统一依赖注入**
   - 用 GetX 的 `Bindings` + `Get.put(..., permanent: true)` 显式注册所有 service 和 core controller
   - 消除所有字段初始化时的隐式 `Get.find`

7. **队列同步职责上移**
   - 把 `PlayerController` 里的 `_scheduleQueueSync` 移到 `PlaybackController`，或拆成独立的 `QueueSyncService`

---

## 四、我的建议

**先做阶段 1 的三件事**，它们风险最低、收益最大：

1. Service 构造注入（30 分钟）
2. 拆 `PlaybackController`（1-2 小时）
3. Liked 抽象基类（30 分钟）

这三个做完，项目会明显清爽：依赖链显式、播放核心和其他页面解耦、liked 代码从 4 份变 1 份。

要不要我现在开始动手？我建议从 **Liked 系列抽象基类** 开始，因为它最独立、最容易验证，然后再做 `PlaybackController` 拆分。你倾向哪个顺序？