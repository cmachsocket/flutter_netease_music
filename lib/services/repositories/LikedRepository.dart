import 'dart:io';

import 'package:archive/archive.dart';
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

const _nodeVersion = '18.20.4';

const _nodeAndroidReleaseUrl =
    'https://github.com/nodejs-mobile/nodejs-mobile/releases/download/'
    'v18.20.4/nodejs-mobile-v18.20.4-android.zip';

const _bridgeAssetName = 'native/node_bridge.dart';

Future<void> main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }

    final config = input.config.code;

    if (config.targetOS != OS.android) {
      return;
    }

    final architecture = config.targetArchitecture;
    final abi = _androidAbi(architecture);

    if (abi == null) {
      throw UnsupportedError('Unsupported Android architecture: $architecture');
    }

    print(
      'ncm_api_enhanced: building Node.js Mobile $_nodeVersion '
      'for Android $abi',
    );

    // -----------------------------------------------------------------------
    // Shared output directory.
    // -----------------------------------------------------------------------

    final sharedDir = Directory.fromUri(input.outputDirectoryShared);

    await sharedDir.create(recursive: true);

    // -----------------------------------------------------------------------
    // Locate Dart SDK.
    //
    //   <dart-sdk>/bin/dart
    //          ^
    //          |
    //   Platform.resolvedExecutable
    //
    // Therefore:
    //
    //   parent        -> <dart-sdk>/bin
    //   parent.parent -> <dart-sdk>
    //
    // Dart API DL:
    //
    //   <dart-sdk>/include/dart_api_dl.h
    //   <dart-sdk>/include/dart_api_dl.c
    // -----------------------------------------------------------------------

    final dartExecutable = File(Platform.resolvedExecutable);

    final dartSdkDir = dartExecutable.parent.parent;

    final dartIncludeDir = Directory('${dartSdkDir.path}/include');

    final dartApiDlHeader = File('${dartIncludeDir.path}/dart_api_dl.h');

    final dartApiDlSource = File('${dartIncludeDir.path}/dart_api_dl.c');

    if (!await dartApiDlHeader.exists()) {
      throw StateError(
        'ncm_api_enhanced: dart_api_dl.h not found at '
        '${dartApiDlHeader.path}',
      );
    }

    if (!await dartApiDlSource.exists()) {
      throw StateError(
        'ncm_api_enhanced: dart_api_dl.c not found at '
        '${dartApiDlSource.path}',
      );
    }

    print(
      'ncm_api_enhanced: Dart SDK: '
      '${dartSdkDir.path}',
    );

    print(
      'ncm_api_enhanced: Dart include: '
      '${dartIncludeDir.path}',
    );

    print(
      'ncm_api_enhanced: Dart API DL source: '
      '${dartApiDlSource.path}',
    );

    output.dependencies.add(dartApiDlHeader.uri);

    output.dependencies.add(dartApiDlSource.uri);

    // -----------------------------------------------------------------------
    // Prepare dart_api_dl.c for the C++ CBuilder.
    //
    // native_toolchain_c's CBuilder is configured as Language.cpp, and
    // RunCBuilder passes:
    //
    //     -x c++
    //
    // for ALL source files.
    //
    // Therefore passing the original dart_api_dl.c directly causes the
    // official C source to be compiled as C++, which fails on Dart 3.10's
    // DartApiEntry_function conversion.
    //
    // We create a private build copy and make the one C -> C++ conversion
    // required by clang.
    // -----------------------------------------------------------------------

    final dartApiDlCpp = File('${sharedDir.path}/dart_api_dl_compat.cpp');

    await _prepareDartApiDlCpp(
      source: dartApiDlSource,
      destination: dartApiDlCpp,
    );

    output.dependencies.add(dartApiDlCpp.uri);

    print(
      'ncm_api_enhanced: prepared Dart API DL C++ source: '
      '${dartApiDlCpp.path}',
    );

    // -----------------------------------------------------------------------
    // Download + extract libnode.so.
    // -----------------------------------------------------------------------

    final nodeDir = Directory(
      '${sharedDir.path}/nodejs-mobile-$_nodeVersion/$abi',
    );

    await nodeDir.create(recursive: true);

    final nodeLibrary = File('${nodeDir.path}/libnode.so');

    if (!await nodeLibrary.exists()) {
      await _downloadNodeLibrary(
        outputDirectory: sharedDir,
        destination: nodeLibrary,
        abi: abi,
      );
    }

    if (!await nodeLibrary.exists()) {
      throw StateError(
        'ncm_api_enhanced: failed to obtain libnode.so for $abi',
      );
    }

    print(
      'ncm_api_enhanced: libnode.so: '
      '${nodeLibrary.path}',
    );

    // -----------------------------------------------------------------------
    // node_bridge.cpp
    // -----------------------------------------------------------------------

    final bridgeSource = File.fromUri(
      input.packageRoot.resolve('native/android/node_bridge.cpp'),
    );

    if (!await bridgeSource.exists()) {
      throw StateError(
        'ncm_api_enhanced: missing '
        'native/android/node_bridge.cpp',
      );
    }

    // -----------------------------------------------------------------------
    // CBuilder
    //
    // The resulting shared library contains:
    //
    //     node_bridge.cpp
    //     dart_api_dl_compat.cpp
    //
    // and links:
    //
    //     libnode.so
    //     liblog.so
    //
    // dart_api_dl_compat.cpp provides:
    //
    //     Dart_InitializeApiDL
    //     Dart_PostCObject_DL
    //     ...
    //
    // so libncm_node_bridge.so no longer leaves
    // Dart_PostCObject_DL as an unresolved ELF symbol.
    // -----------------------------------------------------------------------

    final builder = CBuilder.library(
      name: 'ncm_node_bridge',
      assetName: _bridgeAssetName,

      sources: <String>[bridgeSource.path, dartApiDlCpp.path],

      // dart_api_dl.h lives here.
      includes: <String>[dartIncludeDir.path],

      libraries: <String>['node', 'log'],

      libraryDirectories: <String>[nodeDir.path],

      language: Language.cpp,

      cppLinkStdLib: 'c++_shared',

      linkModePreference: LinkModePreference.dynamic,

      pic: true,

      std: 'c++17',

      optimizationLevel: OptimizationLevel.o3,
    );

    await builder.run(input: input, output: output);

    // -----------------------------------------------------------------------
    // Register libnode.so.
    // -----------------------------------------------------------------------

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'native/libnode.dart',
        linkMode: DynamicLoadingBundled(),
        file: nodeLibrary.uri,
      ),
    );

    print('ncm_api_enhanced: registered libnode.so for $abi');
  });
}

// ===========================================================================
// Prepare Dart API DL C++ compatibility source
// ===========================================================================

Future<void> _prepareDartApiDlCpp({
  required File source,
  required File destination,
}) async {
  var content = await source.readAsString();

  // Dart SDK's dart_api_dl.c contains a C-compatible conversion:
  //
  //     return entries->function;
  //
  // When the file is compiled as C++, the type is:
  //
  //     DartApiEntry_function == void*
  //
  // while entries->function is a function pointer.
  //
  // C accepts this conversion, but C++ does not.
  //
  // Explicitly cast it to the API's declared return type.
  const original =
      'if (strcmp(entries->name, name) == 0) return entries->function;';

  const replacement =
      'if (strcmp(entries->name, name) == 0) '
      'return reinterpret_cast<DartApiEntry_function>('
      'entries->function);';

  if (!content.contains(original)) {
    throw StateError(
      'ncm_api_enhanced: unexpected dart_api_dl.c layout. '
      'Could not find the expected DartApiEntry lookup expression.',
    );
  }

  content = content.replaceFirst(original, replacement);

  await destination.parent.create(recursive: true);

  await destination.writeAsString(content, flush: true);
}

// ===========================================================================
// Android ABI
// ===========================================================================

String? _androidAbi(Architecture architecture) {
  switch (architecture) {
    case Architecture.arm64:
      return 'arm64-v8a';

    case Architecture.arm:
      return 'armeabi-v7a';

    case Architecture.x64:
      return 'x86_64';

    default:
      return null;
  }
}

// ===========================================================================
// Download + extract libnode.so
// ===========================================================================

Future<void> _downloadNodeLibrary({
  required Directory outputDirectory,
  required File destination,
  required String abi,
}) async {
  final archiveDir = Directory(
    '${outputDirectory.path}/nodejs-mobile-$_nodeVersion',
  );

  await archiveDir.create(recursive: true);

  final zipFile = File(
    '${archiveDir.path}/'
    'nodejs-mobile-v$_nodeVersion-android.zip',
  );

  // -------------------------------------------------------------------------
  // Download ZIP if necessary.
  // -------------------------------------------------------------------------

  if (!await zipFile.exists()) {
    print(
      'ncm_api_enhanced: downloading '
      '$_nodeAndroidReleaseUrl',
    );

    await _downloadFile(Uri.parse(_nodeAndroidReleaseUrl), zipFile);
  }

  // -------------------------------------------------------------------------
  // Read ZIP.
  // -------------------------------------------------------------------------

  print(
    'ncm_api_enhanced: extracting '
    '$abi/libnode.so',
  );

  final bytes = await zipFile.readAsBytes();

  final archive = ZipDecoder().decodeBytes(bytes, verify: true);

  final expectedPath = 'bin/$abi/libnode.so';

  ArchiveFile? nodeFile;

  for (final file in archive.files) {
    final normalized = file.name.replaceAll('\\', '/');

    if (normalized == expectedPath) {
      nodeFile = file;
      break;
    }
  }

  if (nodeFile == null) {
    throw StateError(
      'ncm_api_enhanced: $expectedPath was not found in '
      '$_nodeAndroidReleaseUrl',
    );
  }

  final content = nodeFile.content;

  await destination.parent.create(recursive: true);

  await destination.writeAsBytes(content, flush: true);

  print(
    'ncm_api_enhanced: extracted '
    '${destination.path}',
  );
}

// ===========================================================================
// HTTP download
// ===========================================================================

Future<void> _downloadFile(Uri url, File destination) async {
  final temp = File('${destination.path}.download');

  if (await temp.exists()) {
    await temp.delete();
  }

  final client = HttpClient();

  try {
    client.userAgent =
        'ncm_api_enhanced/$_nodeVersion '
        '(Dart build hook)';

    final request = await client.getUrl(url);

    request.followRedirects = true;
    request.maxRedirects = 8;

    final response = await request.close();

    if (response.statusCode != HttpStatus.ok) {
      await response.drain();

      throw HttpException('HTTP ${response.statusCode} while downloading $url');
    }

    final sink = temp.openWrite();

    try {
      await response.pipe(sink);
    } catch (_) {
      await sink.close();
      rethrow;
    }

    await temp.rename(destination.path);
  } finally {
    client.close(force: true);
  }
}
