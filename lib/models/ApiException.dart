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

  const ApiException(this.code, this.message, {this.cause});

  /// 本地异常代号
  static const int localNetwork = -1;
  static const int localParse = -2;
  static const int localUnexpected = -99;

  @override
  String toString() => 'ApiException($code): $message';
}