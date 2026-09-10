import 'package:musiclibrary/music_library.dart';

import '../models/ApiException.dart';

/// 调用一次后端接口 + 业务检查
///
/// - 包 try/catch,把 RPC / 解析 / 网络异常转成 [ApiException]
/// - 包 [checkResponse],检查 HTTP status + 业务 code
///
/// **阻塞说明**:SDK 是同步阻塞 FFI(JSContext 跑 JS),已挪到 worker isolate
/// 跑 ([ApiClient]),主 isolate 调此函数只 await RPC,不再卡。
///
/// **签名变化**(2026-09 改造):闭包从 `MusicResponse Function()` 改成
/// `Future<MusicResponse> Function()`,因为 RPC 必然是 async。仓库层调用形态
/// 不变,只是闭包内部从 `_api.raw.xxx(...)` 改成 `_api.callApi('xxx', [...])`。
Future<MusicResponse> apiCall(
  Future<MusicResponse> Function() fn, {
  String? what,
}) async {
  try {
    final r = await fn();
    checkResponse(r, hint: what);
    return r;
  } on ApiException {
    rethrow;
  } catch (e) {
    throw ApiException(
      ApiException.localUnexpected,
      '${what ?? "API"} 调用失败: $e',
      cause: e,
    );
  }
}

/// 业务成功判定:HTTP 200 + body.code 200(网易云惯例)
///
/// 不是所有返回都有 body.code(如部分 banner / settings),允许 body.code 缺失
/// 此时只看 HTTP status。
///
/// **校准辅助**:业务 code != 200 抛异常时把 raw body 装进 [ApiException.rawBody],
/// 让上层 repository 能 debugPrint 整段 body 校准成功判定。
///
/// **双层 body 兼容**:真机发现 `/playlist/tracks` 等端点的 code 不在
/// 顶层 `r.body['code']`,而在嵌套 `r.body['body']['code']`。这里两层都查。
/// (其它端点如 `/playlist/create` 的 code 在顶层,不影响。)
void checkResponse(MusicResponse r, {String? hint}) {
  if (r.status != 200) {
    throw ApiException(r.status, '${hint ?? "请求"} 失败 (HTTP ${r.status})');
  }
  // 先查顶层,再查嵌套 body.body.code
  final bodyCode = r.body['code'] ?? r.body['body']?['code'];
  if (bodyCode is int && bodyCode != 200) {
    final msg = r.body['message'] ?? r.body['msg']
        ?? r.body['body']?['message'] ?? r.body['body']?['msg']
        ?? '未知业务错误';
    throw ApiException(
      bodyCode,
      '${hint ?? "请求"} 失败: $msg',
      rawBody: r.body, // ← 携带 raw body 给上层校准用
    );
  }
}