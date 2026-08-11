import 'dart:convert';

class MusicResponse {
  MusicResponse({
    required this.headers,
    required this.body,
    required this.status,
  });

  factory MusicResponse.fromJsonString(String responseJson) {
    final dynamic decoded = jsonDecode(responseJson);
    if (decoded is! Map<String, dynamic>) {
      return MusicResponse.error('Response is not a JSON object');
    }

    final headers = decoded['headers'];
    final body = decoded['body'];
    final status = decoded['status'];

    return MusicResponse(
      headers: headers is Map ? Map<String, dynamic>.from(headers) : <String, dynamic>{},
      body: body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{},
      status: status is int ? status : 500,
    );
  }

  factory MusicResponse.error(String message) {
    return MusicResponse(
      headers: const <String, dynamic>{},
      body: <String, dynamic>{'error': message},
      status: 500,
    );
  }

  final Map<String, dynamic> headers;
  final Map<String, dynamic> body;
  final int status;

  Map<String, dynamic> get data => body;

  String get cookies {
    final cookie = headers['Set-Cookie'];
    return cookie?.toString() ?? '';
  }

  @override
  String toString() {
    final prettyHeaders = const JsonEncoder.withIndent('  ').convert(headers);
    final prettyBody = const JsonEncoder.withIndent('  ').convert(body);
    return 'MusicResponse(\n'
        '  status: $status\n'
        '  headers:\n$prettyHeaders\n'
        '  body:\n$prettyBody\n'
        ')';
  }
}
