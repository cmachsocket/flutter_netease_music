import 'dart:async';

import '../models/ApiException.dart';
import 'music_response.dart';

/// 调用一次后端接口 + 业务检查
///
/// - 包 try/catch,把 RPC / 解析 / 网络异常转成 [ApiException]
/// - 包 [checkResponse],检查 HTTP status + 业务 code
///
/// **签名**(2026-09 改造):闭包内部 `() => _ncm.call(method, query)` 直接 await,
/// 返回 [MusicResponse]。仓库层调用形态不变。
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
/// **双层 body 兼容**:真机发现 `/playlist/tracks` 等端点的 code 不在
/// 顶层 `r.body['code']`,而在嵌套 `r.body['body']['code']`。这里两层都查。
void checkResponse(MusicResponse r, {String? hint}) {
  if (r.status != 200) {
    throw ApiException(r.status, '${hint ?? "请求"} 失败 (HTTP ${r.status})');
  }
  final bodyCode = r.body['code'] ?? r.body['body']?['code'];
  if (bodyCode is int && bodyCode != 200) {
    final msg = r.body['message'] ?? r.body['msg']
        ?? r.body['body']?['message'] ?? r.body['body']?['msg']
        ?? '未知业务错误';
    throw ApiException(
      bodyCode,
      '${hint ?? "请求"} 失败: $msg',
      rawBody: r.body,
    );
  }
}