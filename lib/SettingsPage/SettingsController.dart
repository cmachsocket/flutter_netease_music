import 'package:get/get.dart';

/// 设置 tab controller
///
/// - 当前是个空壳, 跟其他 tab (Home/Search/Library) 保持 controller + binding
///   一致模式: AppShell._bindingForTab 触发 lazyPut, 路由 pop 时随 binding 自动销毁
/// - 之前 Settings 是 StatelessWidget 直接 Get.find<NeteaseApi>(), 跟其他 tab 结构
///   不一致 (其他 tab 都有自己 controller)。Android 上点击设置 tab 后渲染卡到
///   fps=0.44 (logcat: "didn't commit buffer within 3000ms"), 推测跟 Get.to 推到
///   shell navigator 时的 binding lifecycle 异常有关 —— 没有 Settings binding 时
///   AppShell._bindingForTab(3) fallthrough 到 default 的 HomePageBinding, 切到
///   设置 tab 实际是用 Home 的 binding, lifecycle 不一致可能导致渲染层 stall。
/// - 加这个 controller 占位让 _bindingForTab(3) 有自己的 binding, 跟其他 tab 行为统一。
class SettingsController extends GetxController {
  // 占位: 当前没有 controller-local 状态需要管理。
  // 后续如果设置页加本地状态 (比如版本号显示 / 缓存大小计算), 在这里加 Rx 字段。
}
