# SDK Worker Isolate 改造方案

**状态**: ✅ 已落地 (2026-09-10)。测试 `flutter test test/worker_smoke_test.dart` 通过,搜索 RPC 端到端跑通 (worker startup 130ms, search RPC 544ms)。

**Goal:** 把阻塞 FFI 的 `NeteaseCloudMusicApi` 挪到长生命周期 worker isolate,
主 isolate 通过 `SendPort`/`ReceivePort` RPC 调用 SDK,主线程不再卡。

**Architecture:**
- worker isolate 在 `main.dart` 启动时由 `Isolate.spawn` 拉起,持有 SDK 实例 + cookie state + GetStorage
- 主 isolate 只持有 worker 的 `SendPort`,任何 `apiCall` 走 RPC,worker 在内部跑阻塞 FFI 后把
  `MusicResponse` (JSON 序列化) 或 `ApiException` 回传
- `NeteaseApi` 的公开 API 签名不变,仓库层一行不动
- 所有 cookie 操作 (`set_cookie` / `applyLoginCookie` / `applyAnonymousCookie` / `logout`) 都
  走 worker,worker 是 cookie 唯一真相源
- 主 isolate 用一个轻量 `Completer` 模式做 request/reply 配对,支持并发多调用

**Tech Stack:** Flutter / Dart `Isolate.spawn` + `SendPort` RPC / GetX / FFI (`musiclibrary`)

---

## 0. 设计要点

### 0.1 跨 isolate 数据流

```
主 isolate                                   worker isolate
┌──────────────────────────────┐             ┌──────────────────────────────┐
│ NeteaseApi                   │             │ NeteaseCloudMusicApi (raw)   │
│   - workerPort: SendPort ────┼─request────►│   - cookie state             │
│   - pending: Map<int,Completer>             │   - GetStorage handle        │
│   - _nextReqId: int           ◄─response────│ worker loop                  │
│                              │             │   - 按 reqId 解码 → 调 SDK  │
│ 仓库层 / AuthController       │             │   - 回传 JSON 序列化结果      │
│   await apiCall(...)         │             └──────────────────────────────┘
└──────────────────────────────┘
```

### 0.2 Request / Reply 协议

主 isolate → worker:
```dart
{
  'id': int,          // request id,主 isolate 自增分配
  'op': String,       // 操作名: 'call' | 'setCookie' | 'getCookies' | 'logout' | 'shutdown'
  ...                  // 各 op 自带字段
}
```

worker → 主 isolate:
```dart
{ 'id': int, 'ok': bool, 'data': ..., 'error': ... }
```
- `ok: true` + `data` 是 JSON 序列化后的 `MusicResponse` 或 cookie map 等
- `ok: false` + `error` 是 `ApiException` 的 code/message/rawBody 三元组

### 0.3 ops 清单

| op | 入参 | 出参 | 谁发 |
|---|---|---|---|
| `call` | `{method, args}` (方法名 + 参数数组) | `MusicResponse` JSON | 仓库层 `apiCall` |
| `setCookie` | `Map<String,String>` | `void` | `applyLoginCookie` / `applyAnonymousCookie` / `logout` |
| `applyAnonymousCookie` | 无 (worker 自读 GetStorage) | `bool` 成功? | `NeteaseApi.init` / `AuthController.login` |
| `logout` | 无 | `void` (清 cookie + GetStorage) | `AuthController.logout` |
| `shutdown` | 无 | `void` | 仅测试 / onClose |

**注:** `applyLoginCookie` 需要原始 `MusicResponse` 才能解析 `Set-Cookie`。
把登录接口 (`login_cellphone`) 改成走 `call` 后,worker 端 SDK 已经能拿到响应。
把 `applyLoginCookie` 也下沉到 worker:worker 内部调完 `login_cellphone` 后,
直接解析 cookie + 调 `raw.set_cookie(...)` + 写 GetStorage,主 isolate 只收
"是否成功 + 拿到的 cookie map"。

### 0.4 公开 API 影响

仓库层 (`PlaylistRepository` 等) 完全不变,因为它们只 `await apiCall(() => _api.raw.xxx(...))`。

需要修改的 `NeteaseApi` 公开 API:
- `init()`: 内部走 worker(`applyAnonymousCookie` 经 RPC)
- `applyLoginCookie(MusicResponse response)` → **`applyLoginCookie(MusicResponse response)`**
  仍接 `MusicResponse`(已经是 data class,跨 isolate OK),但内部走 worker
- `applyAnonymousCookie()`: 内部走 worker
- `logout()`: 内部走 worker
- `fetchCurrentUid()`: 内部走 worker(走 `call` op 调 `user_account`)
- `getCookiesByCheckLogin()`: 走 worker
- `getSavedAuthCookie()`: 走 worker 读(GetStorage 在 worker 端)
- `isLoggedIn()`: 走 worker 读 loggedInKey

唯一主 isolate 自己能读的是 `loggedInKey` 这种纯 flag——但保持单一真相源原则,
干脆也走 worker。

### 0.5 命名

- 内部 worker 文件:`lib/sdk/ApiWorker.dart`
- RPC 协议:用 `Map<String, Object?>` (兼容 `SendPort.send` 的限制)
- 错误编码:`ApiException.code` / `.message` / `.rawBody`(只这三项跨 isolate)
- `applyLoginCookie` / `applyAnonymousCookie` 签名保留,因为仓库层 / AuthController
  都依赖

---

## 1. 文件清单

### 新增

- `lib/sdk/ApiWorker.dart` — worker isolate 的主循环 + RPC 消息处理
- `lib/sdk/ApiClient.dart` — 主 isolate 侧的 RPC 客户端(管理 `SendPort` + pending Completer)

### 修改

- `lib/sdk/ApiCall.dart` — `apiCall` 签名从 `MusicResponse Function()` → `Future<MusicResponse> Function()`,
  内部 `final r = await fn(); checkResponse(r, hint: what);`,逻辑不变;`checkResponse` 留主 isolate
- `lib/sdk/NeteaseApi.dart` — 删 `final raw`,改持 `final ApiClient _client = ApiClient.instance`;
  所有 SDK 操作经 RPC;`init()` 先发 `applyAnonymousCookie`;`applyLoginCookie` 整段下沉到 worker
- `lib/sdk/AuthController.dart` — 几乎零改动(`_auth.applyLoginCookie(r)` 仍接 `MusicResponse`
  返回 `Map<String, String>`,实现换实现)
- `lib/main.dart` — `ApiClient.instance.start()` (worker 启动) 在 `initNeteaseApi` 之前

### 仓库层(9 个文件,只换闭包内部一行)

- `lib/services/repositories/LibraryRepository.dart` — 4 处
- `lib/services/repositories/LyricsRepository.dart` — 1 处
- `lib/services/repositories/SongRepository.dart` — 2 处
- `lib/services/repositories/SearchRepository.dart` — 1 处
- `lib/services/repositories/ArtistRepository.dart` — 3 处
- `lib/services/repositories/PlaylistRepository.dart` — 6 处
- `lib/services/repositories/LikedRepository.dart` — 10 处
- `lib/services/repositories/AlbumRepository.dart` — 1 处

合计 28 处 `apiCall(() => _api.raw.xxx(...))` → `apiCall(() => _api.callApi('xxx', [...]))`

---

## 2. 任务分解

### Task 1: 设计 RPC 协议 + ApiClient + ApiWorker 骨架

**Files:**
- Create: `lib/sdk/ApiClient.dart`
- Create: `lib/sdk/ApiWorker.dart`

**目标:**
- `ApiClient` 是主 isolate 单例,持 `SendPort` + `Map<int, Completer<Object?>>`
- `ApiClient.start()`: spawn worker(传自己 `ReceivePort` 给 worker),worker 收到后回 `ready`
- worker 主循环:`ReceivePort.listen((msg) => handle(msg))`,按 `op` 分发
- 实现最小可工作:`Future<Object?> call(String op, Map<String, Object?> args)` + 协议

**Step 1:** 写 `ApiClient` 骨架: `start()` / `call()` / `close()`,留 RPC handler 表

**Step 2:** 写 `ApiWorker.entryPoint`: `Isolate.spawn(entryPoint, ...)`,内部
收 `ready` → 回 ack,主 isolate 端 listen 到 ack 才 resolve `start()`

**Step 3:** 跑通"无操作"调用测试 — `ApiClient.instance.start()` 不抛错就 OK

### Task 2: 实现 `call` op (核心 SDK 调用)

**Files:**
- Modify: `lib/sdk/ApiWorker.dart` — 实现 `_handleCall(Map args)`
- Modify: `lib/sdk/ApiClient.dart` — 加 `Future<MusicResponse> callApi(...)` 便利方法

**实现要点:**
- `args`: `{method: String, params: List<Object?>}` (Dart 反射不到, 用 dispatcher 表)
- dispatcher 表:`Map<String, MusicResponse Function(List<Object?> args)>`
  - 注册: `captcha_sent`, `login_cellphone`, `register_anonimous`, `user_account`,
    `login_status`, `playlist_detail`, `playlist_track_all`, `playlist_create`,
    `playlist_tracks`, `playlist_delete`, `playlist_subscribe`, `album`, `album_sublist`,
    `album_sub`, `artist_sublist`, `artist_sub`, `artists`, `artist_album`, `artist_songs`,
    `likelist`, `like`, `lyric_new`, `search`, `song_url`, `song_detail`, `personalized`,
    `user_playlist`, `user_follow_mixed`
- 各 dispatcher 把 `List<Object?>` 解构成强类型参数 (e.g. `captcha_sent` 接
  `(String phone, {String ctcode})`),注意 SDK 方法签名 (从 netease_cloud_music_api.dart 读)
- `MusicResponse` 走 JSON 序列化:`MusicResponse.fromJsonString(jsonEncode(r))`,
  主 isolate 端 `MusicResponse.fromJsonString` 还原

**Step 1:** 在 worker 端建 `_dispatchCall` 大表,把 22 个方法映射好
**Step 2:** 主 isolate `await callApi('captcha_sent', ['138...', '86'])` 跑通端到端

### Task 3: 实现 cookie ops (`setCookie` / `applyLoginCookie` / `applyAnonymousCookie` / `logout` / `getSavedAuthCookie` / `isLoggedIn`)

**Files:**
- Modify: `lib/sdk/ApiWorker.dart` — 实现 `_handleSetCookie` / `_handleApplyLoginCookie` /
  `_handleApplyAnonymousCookie` / `_handleLogout` / `_handleGetSavedAuthCookie` /
  `_handleIsLoggedIn` / `_handleGetCookiesByCheckLogin`
- Modify: `lib/sdk/ApiClient.dart` — 对应便利方法

**实现要点:**
- worker 内仍调 `raw.set_cookie(...)` (worker 拥有 SDK)
- GetStorage 在 worker 端 `GetStorage()` 同样可用(GetStorage 是基于 path 的本地存储,
  跨 isolate 安全)
- `applyLoginCookie(MusicResponse response)`:主 isolate 把 MusicResponse JSON 序列化
  发过来,worker 还原 + 解析 cookie + 写 SDK + 写 GetStorage + 回 cookie map
- `applyAnonymousCookie`:worker 内部 `await apiCall(() => raw.register_anonimous())`
  + 解析 + 写 SDK + 写 GetStorage,失败 try/catch
- `logout`:worker 清 SDK cookie + GetStorage
- `getSavedAuthCookie` / `isLoggedIn`:worker 读 GetStorage 回 map / bool

### Task 4: 改造 `apiCall` / `checkResponse` 走 RPC(仓库层形态不变)

**Files:**
- Modify: `lib/sdk/ApiCall.dart`

**核心问题:** 仓库层原写法是 `apiCall(() => _api.raw.xxx(...))`,`_api.raw` 是
`NeteaseCloudMusicApi` 实例,worker isolate 持有后主 isolate 拿不到。直接搬
闭包不行,需要重新设计。

**目标签名:**
```dart
// 新 apiCall 签名: 闭包返回 Future 而非 MusicResponse
Future<MusicResponse> apiCall(
  Future<MusicResponse> Function() fn, {
  String? what,
});
```

**仓库层调用形态(几乎不变):**
```dart
// 老:
final r = await apiCall(() => _api.raw.personalized(limit: '30'), what: '...');

// 新(闭包内部从 SDK 直调改为走 RPC,形态不变):
final r = await apiCall(
  () => _api.callApi('personalized', ['30']),  // _api.callApi 返回 Future<MusicResponse>
  what: '...',
);
```

这样:
- `apiCall` 签名只从 `MusicResponse Function()` → `Future<MusicResponse> Function()`
  (因为 RPC 必然是 async)
- 仓库层 `await apiCall(...)` 形态不变,只换闭包内部一行
- `checkResponse` 仍在主 isolate 跑(从 worker 回传的 response 已经是 raw 响应,
  主 isolate 端按业务码检查 + 抛 `ApiException`,逻辑跟现在完全一样)

**Step 1:** 改 `apiCall` 签名 + 实现,内部 `final r = await fn(); checkResponse(r, hint: what);`
**Step 2:** `NeteaseApi` 加 `callApi(String method, List<Object?> params) → Future<MusicResponse>`
  内部走 RPC

### Task 5: 仓库层闭包内一行替换

**Files:**
- Modify: 9 个 `lib/services/repositories/*.dart`

**改动模式**(机械替换):
```dart
// 老:
final r = await apiCall(() => _api.raw.personalized(limit: '30'), what: '...');

// 新:
final r = await apiCall(
  () => _api.callApi('personalized', ['30']),
  what: '...',
);
```

keyword args 全部转 positional(SDK 方法本身的参数顺序从源码读,常见模式:必填在前,
optional 在后,如 `search(keywords, type, limit)` → `['周杰伦', '1', '30']`)。
命名参数保持原值: e.g. `song_url(songId, br: br)` → `['$songId', br]`。

涉及 22 处调用,逐文件替换;每文件改完后跑 `flutter analyze` 看该文件 0 error 再继续。

### Task 6: `NeteaseApi` 改造 — 持有 `ApiClient` 而非 `raw`

**Files:**
- Modify: `lib/sdk/NeteaseApi.dart`

**目标:**
- `final NeteaseCloudMusicApi raw` 删掉
- `final ApiClient _client = ApiClient.instance`
- `sendCaptcha` / `loginCellphone` 改为 `await _client.callApi('captcha_sent', [...])`
- `applyLoginCookie(MusicResponse response)` 改为
  `await _client.applyLoginCookie(response)`
- `applyAnonymousCookie` 改为 `await _client.applyAnonymousCookie()`
- `fetchCurrentUid` 改为 `await _client.callApi('user_account', [])`
- `getCookiesByCheckLogin` 改为 `await _client.callApi('login_status', [])`
- `logout` 改为 `await _client.logout()`
- `getSavedAuthCookie` 改为 `_client.getSavedAuthCookie()`
- `isLoggedIn` 改为 `_client.isLoggedIn()`
- `onClose`: `_client.close()` (worker 收到 `shutdown` 后 `Isolate.exit`)
- `init()`: 在 worker 已启动的前提下,经 RPC 走 cookie 灌回 + 触发匿名 cookie 拉取

### Task 7: `AuthController` 微调

**Files:**
- Modify: `lib/sdk/AuthController.dart`

**改动:** 几乎为零。`_auth.applyLoginCookie(r)` 仍然接 `MusicResponse` 返回
`Map<String, String>`(只是实现改走 RPC)。

### Task 8: `main.dart` 启动顺序

**Files:**
- Modify: `lib/main.dart`

**改动:**
```dart
// 老:
await initNeteaseApi();  // 创建 NeteaseApi + init

// 新:
await ApiClient.instance.start();  // spawn worker,等 ready
await initNeteaseApi();            // 创建 NeteaseApi (此时 raw 已在 worker) + init
```

`_resolveLibraryDir()` 在 worker 端跑(用 `Platform.resolvedExecutable`),主 isolate
不需要这个值。

### Task 9: 错误处理 + 日志

**Files:**
- Modify: `lib/sdk/ApiWorker.dart`
- Modify: `lib/sdk/ApiClient.dart`

**目标:**
- worker 端捕获所有 SDK 异常 / `ApiException`, 转成 `{ok:false, error:{code, message, rawBody}}`
- 主 isolate 端还原成 `ApiException` 重抛
- worker 端 `kDebugMode` 日志保留(worker 也能用 `kDebugMode`,因为它是 flutter/foundation 的
  const,不依赖 isolate)
- worker 端 RPC 处理异常隔离:一个请求的异常不能中断 worker 主循环

### Task 10: 编译 + 跑通

**Files:**
- Run: `flutter analyze`
- Run: `flutter test`(无单测则跳过)
- Run: `flutter run -d linux`(本地验证启动 + 一次登录 + 一次列表拉取)

**验证:**
- 启动期不卡几百 ms
- 登录流程不卡
- 拉歌单 / 拉歌词 / 拉歌曲详情不卡(用 stopwatch 量一下,期望 < 50ms 主 isolate 占用)

---

## 3. 关键风险 / 决策

1. **`SendPort.send` 限制:** 只能传 `null` / `num` / `String` / `bool` / `List` / `Map`,
   且 `List`/`Map` 元素要可传递。`MusicResponse` 用 `fromJsonString` 序列化后是
   `Map<String, dynamic>`,JSON safe,OK。`ApiException` 同理(只带 code/message/rawBody,
   rawBody 已经是 `Map<String, dynamic>`,OK)。

2. **GetStorage 跨 isolate:** GetStorage 用文件路径,worker 用 `GetStorage()` 初始化
   时**会重新读盘**。worker 必须先 await `GetStorage.init()` 才能读 cookie。
   `ApiClient.start()` 第一步就是 worker 内 `await GetStorage.init()`,
   完事才回 `ready`。

3. **`kDebugMode` / `print`:** `kDebugMode` 是 `const`,可用;`print` 在 worker 也行。

4. **错误时 worker 不退出:** RPC handler 用 try/catch 包裹,异常只回主 isolate,
   worker 继续监听下一个请求。

5. **worker 启动开销:** spawn + native library dlopen + JSContext init 跟主 isolate
   启动一样慢,但发生在 worker isolate,主 isolate UI 不卡。这是预期行为。

6. **测试 `shutdown`:** `ApiClient.close()` 发 `shutdown` op,worker 收到后
   `Isolate.exit()`,主 isolate 端把 `SendPort` 置空。`NeteaseApi.onClose` 调
   `_client.close()`。

7. **方法签名 dispatcher 表维护成本:** 22 个方法每个都要手写一个 `Function(List)`
   适配。如果 SDK 加方法,这里要加。可以接受(SDK 升级频率低)。

---

## 4. 验证清单

- [ ] `flutter analyze` 0 error
- [ ] 启动期主 isolate 不阻塞 (logcat / DevTools timeline 看)
- [ ] `applyAnonymousCookie` 启动期能拉到 NMTID/NMSCVT(看 logcat)
- [ ] 登录流程正常,cookie 写入 GetStorage
- [ ] 重启后 cookie 恢复
- [ ] 歌单 / 歌词 / 搜索接口返回数据正确
- [ ] `logout` 清空 SDK + GetStorage
- [ ] 退出 app 时 worker 收到 shutdown,不泄漏