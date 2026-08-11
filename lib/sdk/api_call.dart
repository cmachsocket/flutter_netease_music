import 'package:musiclibrary/music_library.dart';
import 'api_exception.dart';

/// 调用一次后端接口 + 业务检查
///
/// - 包 try/catch,把 FFI/解析异常转成 [ApiException]
/// - 包 [checkResponse],检查 HTTP status + 业务 code
///
/// **阻塞说明**:SDK 是同步阻塞 FFI(JSContext 跑 JS),调用期间主 isolate
/// 会卡住几百 ms。SDK 实例持有 native handle,不能跨 isolate 传递,所以暂时
/// 不能用 compute() / Isolate.run —— 这是上游 SDK 设计限制,后续若性能不够
/// 再考虑 per-call isolate + 临时 SDK 实例方案。
Future<MusicResponse> apiCall(
  MusicResponse Function() fn, {
  String? what,
}) async {
  try {
    final r = fn();
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
/// 不是所有响应都有 body.code(如部分 banner / settings),允许 body.code 缺失
/// 此时只看 HTTP status。
void checkResponse(MusicResponse r, {String? hint}) {
  if (r.status != 200) {
    throw ApiException(r.status, '${hint ?? "请求"} 失败 (HTTP ${r.status})');
  }
  final bodyCode = r.body['code'];
  if (bodyCode is int && bodyCode != 200) {
    final msg = r.body['message'] ?? r.body['msg'] ?? '未知业务错误';
    throw ApiException(bodyCode, '${hint ?? "请求"} 失败: $msg');
  }
}
