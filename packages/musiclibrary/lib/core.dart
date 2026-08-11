import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'common.dart';

enum KugouPlatform {
  lite('lite'),
  defaultValue('');

  const KugouPlatform(this.value);
  final String value;
}

final class JSContext extends Opaque {
}

final class KugouProcessEnvNative extends Struct {
  external Pointer<Utf8> platform;
  external Pointer<Utf8> kugouApiGuid;
  external Pointer<Utf8> kugouApiDev;
  external Pointer<Utf8> kugouApiMac;
}

final class NcmProcessEnvNative extends Struct {
  external Pointer<Utf8> cnIp;
  external Pointer<Utf8> anonymousToken;
}

class KugouProcessEnv {
  KugouProcessEnv({
    this.platform = KugouPlatform.defaultValue,
    this.guid = '',
    this.dev = '',
    this.mac = '',
  });

  final KugouPlatform platform;
  final String guid;
  final String dev;
  final String mac;

  KugouEnvHandle toNative() => KugouEnvHandle.from(this);
}

class NcmProcessEnv {
  NcmProcessEnv({
    this.cnIp = '',
    this.anonymousToken = '',
  });

  final String cnIp;
  final String anonymousToken;

  NcmEnvHandle toNative() => NcmEnvHandle.from(this);
}

class KugouEnvHandle {
  KugouEnvHandle._(
    this.pointer,
    this._platform,
    this._guid,
    this._dev,
    this._mac,
  );

  factory KugouEnvHandle.from(KugouProcessEnv env) {
    final native = calloc<KugouProcessEnvNative>();
    final platform = env.platform.value.toNativeUtf8();
    final guid = env.guid.toNativeUtf8();
    final dev = env.dev.toNativeUtf8();
    final mac = env.mac.toNativeUtf8();

    native.ref
      ..platform = platform
      ..kugouApiGuid = guid
      ..kugouApiDev = dev
      ..kugouApiMac = mac;

    return KugouEnvHandle._(native, platform, guid, dev, mac);
  }

  final Pointer<KugouProcessEnvNative> pointer;
  final Pointer<Utf8> _platform;
  final Pointer<Utf8> _guid;
  final Pointer<Utf8> _dev;
  final Pointer<Utf8> _mac;

  void dispose() {
    calloc.free(_platform);
    calloc.free(_guid);
    calloc.free(_dev);
    calloc.free(_mac);
    calloc.free(pointer);
  }
}

class NcmEnvHandle {
  NcmEnvHandle._(this.pointer, this._cnIp, this._token);

  factory NcmEnvHandle.from(NcmProcessEnv env) {
    final native = calloc<NcmProcessEnvNative>();
    final cnIp = env.cnIp.toNativeUtf8();
    final token = env.anonymousToken.toNativeUtf8();

    native.ref
      ..cnIp = cnIp
      ..anonymousToken = token;

    return NcmEnvHandle._(native, cnIp, token);
  }

  final Pointer<NcmProcessEnvNative> pointer;
  final Pointer<Utf8> _cnIp;
  final Pointer<Utf8> _token;

  void dispose() {
    calloc.free(_cnIp);
    calloc.free(_token);
    calloc.free(pointer);
  }
}

String _resolveLibraryPath(String libraryFileName, {String? libraryDir}) {
  if (libraryDir == null || libraryDir.isEmpty) {
    return libraryFileName;
  }
  final normalized = libraryDir.endsWith(Platform.pathSeparator)
      ? libraryDir.substring(0, libraryDir.length - 1)
      : libraryDir;
  return '$normalized${Platform.pathSeparator}$libraryFileName';
}

String _binaryName(String baseName) {
  if (Platform.isWindows) {
    return '$baseName.dll';
  }
  if (Platform.isMacOS) {
    return 'lib$baseName.dylib';
  }
  if (Platform.isLinux) {
    return 'lib$baseName.so';
  }
  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}

typedef _InitEngineNative = Int32 Function();
typedef _InitEngineDart = int Function();

typedef _DestroyEngineNative = Int32 Function();
typedef _DestroyEngineDart = int Function();

typedef _ResponseFreeNative = Void Function(Pointer<Void> ptr);
typedef _ResponseFreeDart = void Function(Pointer<Void> ptr);

typedef _DestroyContextNative = Void Function(Pointer<JSContext> ctx);
typedef _DestroyContextDart = void Function(Pointer<JSContext> ctx);

class EngineBindings {
  EngineBindings._(DynamicLibrary library)
      : _initEngine = library.lookupFunction<_InitEngineNative, _InitEngineDart>('init_engine'),
        _destroyEngine = library.lookupFunction<_DestroyEngineNative, _DestroyEngineDart>('destroy_engine'),
        _responseFree = library.lookupFunction<_ResponseFreeNative, _ResponseFreeDart>('response_free'),
        _destroyContext = library.lookupFunction<_DestroyContextNative, _DestroyContextDart>('destroy_context');

  factory EngineBindings({String? libraryDir}) {
    final lib = DynamicLibrary.open(_resolveLibraryPath(_binaryName('engine'), libraryDir: libraryDir));
    return EngineBindings._(lib);
  }

  final _InitEngineDart _initEngine;
  final _DestroyEngineDart _destroyEngine;
  final _ResponseFreeDart _responseFree;
  final _DestroyContextDart _destroyContext;

  bool _initialized = false;

  void ensureInitialized() {
    if (_initialized) {
      return;
    }
    final result = _initEngine();
    if (result != 0) {
      throw StateError('Failed to initialize engine, code: $result');
    }
    _initialized = true;
  }

  void responseFree(Pointer<Void> ptr) => _responseFree(ptr);

  void destroyContext(Pointer<JSContext> ctx) {
    if (ctx.address == 0) {
      return;
    }
    _destroyContext(ctx);
  }

  void dispose() {
    if (!_initialized) {
      return;
    }
    _destroyEngine();
    _initialized = false;
  }
}

typedef _KugouInitNative = Pointer<JSContext> Function(Pointer<KugouProcessEnvNative> env);
typedef _KugouInitDart = Pointer<JSContext> Function(Pointer<KugouProcessEnvNative> env);

typedef _KugouDestroyNative = Int32 Function();
typedef _KugouDestroyDart = int Function();

typedef _GetKugouContextNative = Pointer<JSContext> Function();
typedef _GetKugouContextDart = Pointer<JSContext> Function();

typedef _KugouRequestNative = Pointer<Void> Function(
  Pointer<JSContext> ctx,
  Pointer<Utf8> route,
  Pointer<Utf8> cookie,
  Pointer<Utf8> params,
  Pointer<KugouProcessEnvNative> env,
);
typedef _KugouRequestDart = Pointer<Void> Function(
  Pointer<JSContext> ctx,
  Pointer<Utf8> route,
  Pointer<Utf8> cookie,
  Pointer<Utf8> params,
  Pointer<KugouProcessEnvNative> env,
);

class KugouBindings {
  KugouBindings._(DynamicLibrary library)
      : _kugouInit = library.lookupFunction<_KugouInitNative, _KugouInitDart>('kugou_init'),
        _kugouDestroy = library.lookupFunction<_KugouDestroyNative, _KugouDestroyDart>('kugou_destroy'),
        _getKugouContext = library.lookupFunction<_GetKugouContextNative, _GetKugouContextDart>('get_kugou_context'),
        _kugouRequest = library.lookupFunction<_KugouRequestNative, _KugouRequestDart>('kugou_request');

  factory KugouBindings({String? libraryDir}) {
    final lib = DynamicLibrary.open(_resolveLibraryPath(_binaryName('kugou_music_api'), libraryDir: libraryDir));
    return KugouBindings._(lib);
  }

  final _KugouInitDart _kugouInit;
  final _KugouDestroyDart _kugouDestroy;
  final _GetKugouContextDart _getKugouContext;
  final _KugouRequestDart _kugouRequest;

  Pointer<JSContext> init(Pointer<KugouProcessEnvNative> env) => _kugouInit(env);
  int destroy() => _kugouDestroy();
  Pointer<JSContext> getContext() => _getKugouContext();

  Pointer<Void> request(
    Pointer<JSContext> ctx,
    Pointer<Utf8> route,
    Pointer<Utf8> cookie,
    Pointer<Utf8> params,
    Pointer<KugouProcessEnvNative> env,
  ) {
    return _kugouRequest(ctx, route, cookie, params, env);
  }
}

typedef _NcmInitNative = Pointer<JSContext> Function(Pointer<NcmProcessEnvNative> env);
typedef _NcmInitDart = Pointer<JSContext> Function(Pointer<NcmProcessEnvNative> env);

typedef _NcmDestroyNative = Int32 Function();
typedef _NcmDestroyDart = int Function();

typedef _GetNcmContextNative = Pointer<JSContext> Function();
typedef _GetNcmContextDart = Pointer<JSContext> Function();

typedef _NcmRequestNative = Pointer<Void> Function(
  Pointer<JSContext> ctx,
  Pointer<Utf8> route,
  Pointer<Utf8> cookie,
  Pointer<Utf8> params,
  Pointer<NcmProcessEnvNative> env,
);
typedef _NcmRequestDart = Pointer<Void> Function(
  Pointer<JSContext> ctx,
  Pointer<Utf8> route,
  Pointer<Utf8> cookie,
  Pointer<Utf8> params,
  Pointer<NcmProcessEnvNative> env,
);

typedef _GenerateRandomCnIpNative = Pointer<Void> Function(Pointer<JSContext> ctx);
typedef _GenerateRandomCnIpDart = Pointer<Void> Function(Pointer<JSContext> ctx);

typedef _GenerateAnonymousTokenNative = Pointer<Void> Function(Pointer<JSContext> ctx);
typedef _GenerateAnonymousTokenDart = Pointer<Void> Function(Pointer<JSContext> ctx);

class NcmBindings {
  NcmBindings._(DynamicLibrary library)
      : _ncmInit = library.lookupFunction<_NcmInitNative, _NcmInitDart>('ncm_init'),
        _ncmDestroy = library.lookupFunction<_NcmDestroyNative, _NcmDestroyDart>('ncm_destroy'),
        _getNcmContext = library.lookupFunction<_GetNcmContextNative, _GetNcmContextDart>('get_ncm_context'),
        _ncmRequest = library.lookupFunction<_NcmRequestNative, _NcmRequestDart>('ncm_request'),
        _generateRandomCnIp = library.lookupFunction<_GenerateRandomCnIpNative, _GenerateRandomCnIpDart>('generate_random_cnIp'),
        _generateAnonymousToken = library.lookupFunction<_GenerateAnonymousTokenNative, _GenerateAnonymousTokenDart>('generate_anonimous_token');

  factory NcmBindings({String? libraryDir}) {
    final lib = DynamicLibrary.open(_resolveLibraryPath(_binaryName('ncm_music_api'), libraryDir: libraryDir));
    return NcmBindings._(lib);
  }

  final _NcmInitDart _ncmInit;
  final _NcmDestroyDart _ncmDestroy;
  final _GetNcmContextDart _getNcmContext;
  final _NcmRequestDart _ncmRequest;
  final _GenerateRandomCnIpDart _generateRandomCnIp;
  final _GenerateAnonymousTokenDart _generateAnonymousToken;

  Pointer<JSContext> init(Pointer<NcmProcessEnvNative> env) => _ncmInit(env);
  int destroy() => _ncmDestroy();
  Pointer<JSContext> getContext() => _getNcmContext();

  Pointer<Void> request(
    Pointer<JSContext> ctx,
    Pointer<Utf8> route,
    Pointer<Utf8> cookie,
    Pointer<Utf8> params,
    Pointer<NcmProcessEnvNative> env,
  ) {
    return _ncmRequest(ctx, route, cookie, params, env);
  }

  String generateRandomCnIp(Pointer<JSContext> ctx, EngineBindings engine) {
    final ptr = _generateRandomCnIp(ctx);
    if (ptr.address == 0) {
      return '';
    }
    final value = ptr.cast<Utf8>().toDartString();
    engine.responseFree(ptr);
    return value;
  }

  String generateAnonymousToken(Pointer<JSContext> ctx, EngineBindings engine) {
    final ptr = _generateAnonymousToken(ctx);
    if (ptr.address == 0) {
      return '';
    }
    final value = ptr.cast<Utf8>().toDartString();
    engine.responseFree(ptr);
    return value;
  }
}

class KugouContextManager {
  KugouContextManager({required this.bindings});

  final KugouBindings bindings;

  Pointer<JSContext> _ctx = Pointer<JSContext>.fromAddress(0);

  void init(Pointer<KugouProcessEnvNative> env) {
    if (_ctx.address != 0) {
      return;
    }
    _ctx = bindings.init(env);
  }

  Pointer<JSContext> takeContext() {
    if (_ctx.address != 0) {
      final current = _ctx;
      _ctx = Pointer<JSContext>.fromAddress(0);
      return current;
    }
    return bindings.getContext();
  }

  void destroy() {
    if (_ctx.address == 0) {
      return;
    }
    bindings.destroy();
    _ctx = Pointer<JSContext>.fromAddress(0);
  }
}

class NcmContextManager {
  NcmContextManager({required this.bindings});

  final NcmBindings bindings;

  Pointer<JSContext> _ctx = Pointer<JSContext>.fromAddress(0);

  void init(Pointer<NcmProcessEnvNative> env) {
    if (_ctx.address != 0) {
      return;
    }
    _ctx = bindings.init(env);
  }

  Pointer<JSContext> takeContext() {
    if (_ctx.address != 0) {
      final current = _ctx;
      _ctx = Pointer<JSContext>.fromAddress(0);
      return current;
    }
    return bindings.getContext();
  }

  void destroy() {
    if (_ctx.address == 0) {
      return;
    }
    bindings.destroy();
    _ctx = Pointer<JSContext>.fromAddress(0);
  }
}

MusicResponse parseFfiResponse(Pointer<Void> ptr, EngineBindings engine) {
  if (ptr.address == 0) {
    return MusicResponse.error('Failed to get response');
  }

  final text = ptr.cast<Utf8>().toDartString();
  engine.responseFree(ptr);

  try {
    return MusicResponse.fromJsonString(text);
  } catch (e) {
    return MusicResponse.error('Failed to parse response JSON: $e');
  }
}

String encodeQuery(Map<String, dynamic> query) {
  final filtered = <String, dynamic>{};
  query.forEach((key, value) {
    if (value != null) {
      filtered[key] = value;
    }
  });
  if (filtered.isEmpty) {
    return '';
  }
  return jsonEncode(filtered);
}
