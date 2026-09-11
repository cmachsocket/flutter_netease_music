// SPDX-License-Identifier: MIT
//
// SDK method → query dict field mapping.
//
// Each entry says: when the repo layer calls
// `NeteaseApi.callApi('<method>', {...positional args})`, how to translate
// the positional args into a query dict for the upstream NCM API.
//
// The upstream NCM API (`@neteasecloudmusicapienhanced/api`) expects a
// single `Map<String, dynamic>` per call — keys are the HTTP query
// field names. We map positional args to that dict here, removing
// the need for a worker isolate (the original MusicLibrary/Python
// design required positional arg dispatch in ApiWorker).
//
// `positional` is the index in the original positional arg list.
// Multiple `positional` entries are joined as `[arg0, arg1, ...]`.
//
// `defaults` (optional): when an arg is null and we still want a
// sensible default (e.g. `limit = '30'`), fill it in.
//
// All field names match the upstream NCM API's `interface.d.ts`
// signatures (snake_case). Keep this file in sync with the upstream
// whenever a method signature changes.

import 'package:ncm_api_enhanced/ncm_api_enhanced.dart';

/// One positional arg slot. `field` is the query dict key in upstream
/// NCM; `defaultIfMissing` (optional) is filled when the positional
/// slot is absent. `dropIfNull` (default false) controls whether a
/// null positional arg becomes `null` in the query dict (false) or is
/// omitted entirely (true) — some endpoints reject explicit nulls.
class ParamSlot {
  const ParamSlot(
    this.field, {
    this.defaultIfMissing,
    this.dropIfNull = false,
  });
  final String field;
  final String? defaultIfMissing;
  final bool dropIfNull;
}

class MethodSpec {
  const MethodSpec({
    required this.method,
    required this.params,
    this.requiresAuth = false,
  });

  final String method;
  final List<ParamSlot> params;
  final bool requiresAuth;
}

/// Dispatch table. One entry per SDK method the app currently calls.
///
/// To add a new method, append an entry here; no other glue needed —
/// [NeteaseApi.callApi] looks it up by name.
const List<MethodSpec> methodSpecs = [
  MethodSpec(method: 'captcha_sent', params: [
    ParamSlot('phone'),
    ParamSlot('ctcode', defaultIfMissing: '86'),
  ]),
  MethodSpec(method: 'login_cellphone', params: [
    ParamSlot('phone'),
    ParamSlot('captcha'),
    ParamSlot('countrycode', defaultIfMissing: '86'),
  ]),
  MethodSpec(method: 'register_anonimous', params: []),
  MethodSpec(method: 'user_account', params: []),
  MethodSpec(method: 'login_status', params: []),
  MethodSpec(method: 'playlist_detail', params: [
    ParamSlot('id'),
  ]),
  MethodSpec(method: 'playlist_track_all', params: [
    ParamSlot('id'),
    ParamSlot('limit'),
    ParamSlot('offset'),
  ]),
  MethodSpec(method: 'playlist_create', params: [
    ParamSlot('name'),
    ParamSlot('privacy'),
    ParamSlot('type'),
  ]),
  // playlist_tracks(op, pid, tracks) — upstream takes the same names;
  // the SDK had them positional but they're already the upstream fields.
  MethodSpec(method: 'playlist_tracks', params: [
    ParamSlot('op'),
    ParamSlot('pid'),
    ParamSlot('tracks'),
  ]),
  MethodSpec(method: 'playlist_delete', params: [
    ParamSlot('id'),
  ]),
  MethodSpec(method: 'playlist_subscribe', params: [
    ParamSlot('t'),
    ParamSlot('id'),
  ]),
  MethodSpec(method: 'album', params: [
    ParamSlot('id'),
  ]),
  MethodSpec(method: 'album_sublist', params: [
    ParamSlot('limit', defaultIfMissing: '50'),
  ]),
  MethodSpec(method: 'album_sub', params: [
    ParamSlot('id'),
    ParamSlot('t'),
  ]),
  MethodSpec(method: 'artists', params: [
    ParamSlot('id'),
  ]),
  MethodSpec(method: 'artist_sublist', params: []),
  MethodSpec(method: 'artist_sub', params: [
    ParamSlot('id'),
    ParamSlot('t'),
  ]),
  MethodSpec(method: 'artist_album', params: [
    ParamSlot('id'),
  ]),
  MethodSpec(method: 'artist_songs', params: [
    ParamSlot('id'),
    ParamSlot('limit', defaultIfMissing: '50'),
  ]),
  MethodSpec(method: 'likelist', params: [
    ParamSlot('uid'),
  ]),
  MethodSpec(method: 'like', params: [
    ParamSlot('id'),
    ParamSlot('like'),
  ]),
  MethodSpec(method: 'lyric_new', params: [
    ParamSlot('id'),
  ]),
  MethodSpec(method: 'search', params: [
    ParamSlot('keywords'),
    ParamSlot('type', defaultIfMissing: '1'),
    ParamSlot('limit', defaultIfMissing: '30'),
  ]),
  MethodSpec(method: 'song_url', params: [
    ParamSlot('id'),
    ParamSlot('br', defaultIfMissing: '999000'),
  ]),
  MethodSpec(method: 'song_detail', params: [
    ParamSlot('ids'),
  ]),
  MethodSpec(method: 'personalized', params: [
    ParamSlot('limit', defaultIfMissing: '30'),
  ]),
  MethodSpec(method: 'user_playlist', params: [
    ParamSlot('uid'),
    ParamSlot('limit', defaultIfMissing: '50'),
  ]),
  MethodSpec(method: 'user_follow_mixed', params: [
    ParamSlot('size', defaultIfMissing: '50'),
    ParamSlot('cursor', defaultIfMissing: '0'),
    ParamSlot('scene', defaultIfMissing: '1'),
  ]),
];

final Map<String, MethodSpec> _byMethod = {
  for (final s in methodSpecs) s.method: s,
};

/// Look up a method spec by name. Throws if the app is calling a
/// method that has no entry — that almost always means a new SDK
/// method was added without updating [methodSpecs].
MethodSpec specFor(String method) {
  final s = _byMethod[method];
  if (s == null) {
    throw ArgumentError(
      'NcmApi spec: no entry for "$method". Add it to methodSpecs '
      'in lib/sdk/MethodSpec.dart (28 entries currently).',
    );
  }
  return s;
}

/// Translate a positional arg list into a query dict for upstream
/// NCM API Enhanced.
///
/// Equivalent to ApiWorker's old switch statement, but:
/// - No worker isolate (NCM API Enhanced is async IPC).
/// - Field names match the upstream `interface.d.ts` exactly.
/// - Defaults from [ParamSlot.defaultIfMissing] fill gaps so callers
///   can omit common parameters.
Map<String, dynamic> positionalToQuery(
  String method,
  List<Object?> args,
) {
  final spec = specFor(method);
  final out = <String, dynamic>{};
  for (var i = 0; i < spec.params.length; i++) {
    final slot = spec.params[i];
    final value = i < args.length ? args[i] : null;
    if (value == null) {
      if (slot.defaultIfMissing != null) {
        out[slot.field] = slot.defaultIfMissing;
      } else if (!slot.dropIfNull) {
        out[slot.field] = null;
      }
    } else {
      out[slot.field] = value;
    }
  }
  return out;
}

/// A convenience for callers that already have a query dict and
/// don't need positional translation. Used by tests and by any new
/// caller that prefers named args from the start.
Future<Map<String, dynamic>> callRaw(
  NcmApi api,
  String method,
  Map<String, dynamic>? query,
) =>
    api.call(method, query);