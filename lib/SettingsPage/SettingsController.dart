//掌管音质选择,跨路由 / 跨 app 启动持久化
//
//跟 [ThemeController] 同模式:
//  - GetxController + permanent (设置一次, 整个 app 生命周期有效)
//  - GetStorage.onInit 同步读 (GetStorage read 是同步 API, 不需要 await)
//  - onChanged 立刻写盘 (write 也是同步, 写盘失败不会让内存值回滚)
//
//为什么 controller 而不是 repo 内部读 GetStorage:
//  repo 是纯 API 调用层, 不应耦合"用户当前偏好", level 是用户偏好;
//  controller 持有 Rx<Quality> 作为唯一真相源, repo 只读不写.
//
//被 [AudioPlayerHandler] 读取 (在 _playAt 拉 URL 时拿到当前 level),
//被 [QualitySwitcher] 写入 (SettingsPage dropdown 切换).

import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

/// 播放音质等级。
///
/// 字段名 (`.name`) 对应网易云 `/song/url/v1` 接口 `level` 参数值,
/// 1:1 映射, 改顺序/改名字会破坏已持久化的用户设置 —— 慎改。
///
/// 取值范围跟文档一致: standard/higher/exhigh/lossless/hires/jyeffect/
/// dolby/vivid/jymaster/sky。其他 v1 参数 (unblock/immerseType) 本期不接入。
enum Quality { standard, higher, exhigh, lossless, hires }

class SettingsController extends GetxController {
  static const _key = 'quality_v1';
  static const _download_key = 'download_path_v1';
  final _box = GetStorage();

  late final Rx<Quality> currentQuality;
  late final Rx<String> DownloadPath;

  @override
  void onInit() {
    super.onInit();
    final saved = _box.read<String>(_key);
    currentQuality =
        (saved == null
                ? Quality.standard
                : Quality.values.firstWhere(
                    (e) => e.name == saved,
                    orElse: () => Quality.standard,
                  ))
            .obs;
    DownloadPath = _box.read<String>(_download_key)?.obs ?? ''.obs;
  }

  /// 切换音质。立刻写盘 (GetStorage write 同步), 后续 [_playAt] event loop
  /// 会自动用新 level 拉 URL —— 不需要主动触发"刷新队列"。
  ///
  /// 返回值给 UI 用 (snackbar "已切换到无损" 等), 失败也算"已切换" (内存值
  /// 已变, 下次写盘重试)。上层不需要 await 这个 future。
  Future<void> setQuality(Quality q) async {
    currentQuality.value = q;
    await _box.write(_key, q.name);
  }

  Future<void> setDownloadPath(String path) async {
    DownloadPath.value = path;
    await _box.write(_download_key, path);
  }
}
