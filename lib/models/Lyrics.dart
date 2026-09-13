class Lyrics {
  final String? lrc;
  final String? tlyric;
  final String? romalrc;

  //暂不提供 yrc, 因为 flutter_lyric 只支持标准 LRC 和 QRC,
  //final String? yrc;
  Lyrics({
    this.lrc,
    this.tlyric,
    this.romalrc,
    //this.yrc,
  });
}
