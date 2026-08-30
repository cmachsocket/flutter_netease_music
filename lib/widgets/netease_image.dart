import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/Headers.dart';

/// NetEase 图片 CDN(`*.music.126.net`)专用请求头
///
/// 关键:**`p1.music.126.net` 等子域把 Dart 默认 `User-Agent`(`Dart/x.x (dart:io)`)
/// 拉黑 → 403 Forbidden**。伪装成 Chrome 即可。Referer / HTTPS 都不是关键。

/// 工厂:把字符串 URL 包成带 [neteaseImageHeaders] 的 `NetworkImage`。
/// 给 `CircleAvatar.backgroundImage` / `Image(image: ...)` 这类需要
/// `ImageProvider` 的地方用。
CachedNetworkImageProvider neteaseNetworkImage(String url) =>
    CachedNetworkImageProvider(
      url,
      headers: NeteaseImageHeaders.neteaseImageHeaders,
    );

/// **全局** UA override —— `Image.network` 的 `headers` 参数在 Android 上
/// 不稳定(底层 `image resource service` 可能忽略)。在 [main] 里装上
/// `HttpOverrides.global = NeteaseHttpOverrides()`,所有 `HttpClient` 实例
/// 创建时都会拿到这个 UA,绕开 `Image.network` 的 headers 黑箱。
///
/// 注:不影响 audio / SDK 那边的 native FFI 请求(走 .so 不走 dart:io HttpClient)。
class NeteaseHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    // userAgent 会被 dart:io 自动塞进每个请求的 User-Agent 头
    client.userAgent = NeteaseImageHeaders.neteaseImageHeaders['User-Agent']!;
    return client;
  }
}
