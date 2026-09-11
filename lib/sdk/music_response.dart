// SPDX-License-Identifier: MIT
//
// Adapter from `NcmApi`'s response shape (the upstream NCM API
// Enhanced) to the `MusicResponse` interface the rest of the app
// already speaks. The upstream returns
//   `{ status: int, body: Map, cookie: List<String> }`
// and the app expects `MusicResponse { status, body, headers }` with
// a `Set-Cookie` header string. We keep `MusicResponse` as a value
// type (not a global singleton) so it's trivial to serialize across
// the isolate boundary should we ever re-introduce a worker.
//
// The original `MusicResponse` class came from the `musiclibrary`
// FFI package (now removed); we re-declare the same shape here so
// callers in lib/services/... can keep using `r.body`, `r.status`,
// `r.cookies` etc.

import 'dart:convert';

class MusicResponse {
  MusicResponse({
    required this.status,
    required this.body,
    required this.headers,
  });

  /// HTTP status from upstream (always 200 in normal operation; the
  /// upstream returns code 4xx/5xx for transport failures).
  final int status;

  /// Parsed business JSON.
  final Map<String, dynamic> body;

  /// Raw HTTP-style headers. We only ever populate `Set-Cookie` since
  /// that's all the upstream pipeline gives us.
  final Map<String, String> headers;

  /// Convenience: `headers['Set-Cookie'] ?? ''`.
  String get cookies => headers['Set-Cookie'] ?? '';

  /// Convenience: `body`. (Some repos call `r.data` instead of
  /// `r.body`.)
  Map<String, dynamic> get data => body;

  /// Build a MusicResponse from a raw NCM API Enhanced response map.
  ///
  /// NCM API Enhanced returns:
  ///   { status: int, body: Map<String, dynamic>, cookie: List<String> }
  ///
  /// `cookie` is a list because the upstream may emit multiple
  /// Set-Cookie headers; we join them with `, ` (the format
  /// [ApiCall]/_parseCookieString expects).
  factory MusicResponse.fromNcm(Map<String, dynamic> raw) {
    final rawStatus = raw['status'];
    final status = rawStatus is int ? rawStatus : 200;
    final body = (raw['body'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final cookieList = raw['cookie'];
    String joined = '';
    if (cookieList is List) {
      joined = cookieList
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .join(', ');
    } else if (cookieList is String) {
      joined = cookieList;
    }
    return MusicResponse(
      status: status,
      body: body,
      headers: joined.isEmpty ? <String, String>{} : <String, String>{
          'Set-Cookie': joined,
        },
    );
  }

  /// JSON serialization — round-trip form, used by tests and by any
  /// caller that needs to log the response shape.
  Map<String, dynamic> toJson() => {
        'status': status,
        'body': body,
        'headers': headers,
      };

  String toJsonString() => jsonEncode(toJson());

  factory MusicResponse.fromJsonString(String s) {
    final m = jsonDecode(s) as Map<String, dynamic>;
    return MusicResponse(
      status: m['status'] as int? ?? 200,
      body: (m['body'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{},
      headers: ((m['headers'] as Map?) ?? {})
          .cast<String, dynamic>()
          .map((k, v) => MapEntry(k, v?.toString() ?? '')),
    );
  }

  @override
  String toString() => 'MusicResponse(status=$status, body=${body.length} keys)';
}