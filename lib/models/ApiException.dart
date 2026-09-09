/// 网易云 API 业务异常
///
/// - [code] < 0 表示本地异常(网络错误 / 解析失败),见 [localCode]
/// - [code] >= 0 表示后端业务码(/login 等接口 body['code'])
class ApiException implements Exception {
  /// 异常码
  /// - < 0: 本地异常,见 [localCode]
  /// - >= 0: 后端 body.code 或 status
  final int code;

  /// 人类可读的错误描述
  final String message;

  /// 原始错误(如果有)
  final Object? cause;

  /// 校准用:异常抛出前的 raw body。
  ///
  /// 当 [checkResponse] 因为 body.code != 200 抛异常时,把整个 body 字段
  /// 携带出来。repository 层失败时打 log,方便贴回来校准成功判定。
  ///
  /// **不是所有异常都有 raw body**:
  /// - 网络/HTTP status 异常 → null
  /// - 解析失败 → null
  /// - 业务 code 错误 → 完整 body
  final Map<String, dynamic>? rawBody;

  const ApiException(this.code, this.message, {this.cause, this.rawBody});

  /// 本地异常代号
  static const int localNetwork = -1;
  static const int localParse = -2;
  static const int localUnexpected = -99;

  @override
  String toString() => 'ApiException($code): $message';
}