import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

/// 主题只走 flex_color_scheme 内置方案,所有 component 样式都用默认。
class AppTheme {
  static ThemeData light() => FlexThemeData.light(scheme: FlexScheme.mandyRed);
  static ThemeData dark() => FlexThemeData.dark(scheme: FlexScheme.mandyRed);
}
