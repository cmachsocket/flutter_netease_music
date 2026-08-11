import 'package:musiclibrary/music_library.dart';

void main() {
  final api = NeteaseCloudMusicApi(
    libraryDir:
        '/home/cmach_socket/projects/flutter_netease_music/build/linux/x64/debug/bundle/lib',
  );
  final r = api.search('周杰伦', type: '1', limit: '3');
  print('status=${r.status} body.code=${r.body['code']}');
  final songs = (r.body['result']?['songs'] as List?) ?? [];
  print('找到 ${songs.length} 首歌:');
  for (final s in songs.take(3)) {
    print('  - ${s['name']} - ${(s['ar'] as List?)?.first?['name']}');
  }
  api.dispose();
}
