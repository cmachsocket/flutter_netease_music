// Worker isolate RPC smoke test
//
// 用法(从项目根):
//   flutter test test/worker_smoke_test.dart
//
// flutter test 环境下 `Platform.resolvedExecutable` 指向 test runner 而非
// 真实 app bundle,SDK 找不到 native library。所以这里手动指定 libraryDirOverride。

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_netease_music/sdk/ApiClient.dart';
import 'package:musiclibrary/music_library.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ApiClient.libraryDirOverride =
        '/home/cmach_socket/projects/flutter_netease_music/build/linux/x64/debug/bundle/lib';
  });

  tearDown(() async {
    if (ApiClient.instance.isStarted) {
      await ApiClient.instance.close();
    }
  });

  test('worker RPC search round-trip', () async {
    final sw = Stopwatch()..start();
    await ApiClient.instance.start();
    sw.stop();
    print('worker started in ${sw.elapsedMilliseconds}ms');
    expect(ApiClient.instance.isStarted, true);

    sw.reset();
    sw.start();
    final MusicResponse r = await ApiClient.instance.callApi(
      'search',
      <Object?>['周杰伦', '1', '3'],
    );
    sw.stop();
    print('search RPC returned in ${sw.elapsedMilliseconds}ms');
    print('status=${r.status} body.code=${r.body['code']}');
    final songs = (r.body['result']?['songs'] as List?) ?? [];
    print('found ${songs.length} songs');
    for (final s in songs.take(3)) {
      print('  - ${s['name']} - ${(s['ar'] as List?)?.first?['name']}');
    }

    expect(r.status, 200);
    expect(songs, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));
}