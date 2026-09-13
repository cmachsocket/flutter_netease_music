import 'Song.dart';

/// 一首歌的下载状态 UI 模型。
///
/// [DownloadService] 持有 `RxMap<String songId, DownloadTaskView>` 作为
/// UI 的真相源。状态变化 (enqueued / running / complete / failed / paused)
/// 来自 background_downloader 的 callback 推送,进度 (0..1) 来自 progress callback。
///
/// 不存 [Song] 引用——只存 songId + 反序列化的 Song (toJson)。理由:
/// - 启动恢复时 background_downloader database 只有 taskId + metaData,
///   反序列化 Song 元数据才能在 DownloadPage 显示标题/艺人;
/// - Song 的 immutable 字段少,序列化代价小。
class DownloadTaskView {
  /// background_downloader 的 taskId (业务无关,只是底层句柄)。
  /// UI / 业务层不应该依赖这个字段,仅 DownloadService 内部用于 cancel。
  final String taskId;

  /// 网易云歌曲 id,跨重启稳定,UI 用这个做 key。
  final String songId;

  /// 用来在 DownloadPage 显示 (title/artist/coverUrl/duration)。
  /// 持久化时只存 JSON 字符串,启动后从 metaData 反序列化。
  final Song song;

  /// 当前状态。映射自 background_downloader 的 [TaskStatus]。
  /// 不直接复用对方的 enum 是因为:
  /// 1. 业务侧不依赖具体 SDK enum;
  /// 2. 自家 enum 方便未来加 "已过期待重下" 等新状态。
  final DownloadStatus status;

  /// 进度 0..1,失败/取消/未开始时为 0。
  final double progress;

  /// 失败时的错误描述。其他状态下为 null。
  final String? errorMessage;

  /// 完成后的本地文件路径 (绝对路径)。用于 UI "打开文件夹" / 播放。
  /// background_downloader 在 TaskStatus.complete 时通过 TaskRecord 提供。
  final String? savedPath;

  const DownloadTaskView({
    required this.taskId,
    required this.songId,
    required this.song,
    required this.status,
    this.progress = 0,
    this.errorMessage,
    this.savedPath,
  });

  DownloadTaskView copyWith({
    String? taskId,
    DownloadStatus? status,
    double? progress,
    String? errorMessage,
    String? savedPath,
    bool clearError = false,
    bool clearSavedPath = false,
  }) {
    return DownloadTaskView(
      taskId: taskId ?? this.taskId,
      songId: songId,
      song: song,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      savedPath: clearSavedPath ? null : (savedPath ?? this.savedPath),
    );
  }
}

/// UI 层使用的简化状态枚举。
///
/// 跟 background_downloader 的 [TaskStatus] 一一对应 (不含 paused 因为
/// 业务上不主动暂停,失败/取消/完成都是终态)。
enum DownloadStatus {
  /// 等待 native 调度 (排队 / 等待网络)。
  enqueued,

  /// 正在下载。
  running,

  /// 下载成功。
  complete,

  /// 服务器 404 / 文件不存在。
  notFound,

  /// 异常失败。
  failed,

  /// 用户取消。
  canceled,

  /// 失败后等待重试 (background_downloader 内置退避)。
  waitingToRetry,
}
