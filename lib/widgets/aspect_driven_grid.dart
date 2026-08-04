// lib/widgets/aspect_driven_grid.dart
//
// 一张"纯比例驱动"的网格。零硬编码像素。
//   - 列数 = 容器宽高比决定
//   - 间距 = 列宽 × gapRatio
//   - item 宽高比 = 调用方直接传 childAspectRatio
//
// 所有数值参数（baseColumns / baseRatio / gapRatio / childAspectRatio）都是相对量，不是像素。

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

/// 1. 标准版（等高 item，列数 / 间距 / item 比例全部派生）
class AspectDrivenGrid extends StatelessWidget {
  const AspectDrivenGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.baseColumns = 2,
    this.baseRatio = 1.0,
    this.gapRatio = 0.04,
    this.childAspectRatio = 1.0,
    this.minColumns = 1,
    this.maxColumns = 6,
    this.padding = EdgeInsets.zero,
    this.scrollPhysics,
    this.shrinkWrap = false,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  /// 基准宽高比下的列数（默认 2）
  final int baseColumns;

  /// 基准宽高比（默认 1.0 = 1:1）
  final double baseRatio;

  /// 间距 = 列宽 × 此比例（0.02~0.06 区间）
  final double gapRatio;

  /// item 自身的宽/高比（直接传给 SliverGridDelegate.childAspectRatio）。
  /// 默认 1.0 = 永远方。
  final double childAspectRatio;

  /// 列数限位
  final int minColumns;
  final int maxColumns;

  final EdgeInsetsGeometry padding;
  final ScrollPhysics? scrollPhysics;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        assert(
          c.hasBoundedWidth && c.hasBoundedHeight,
          'AspectDrivenGrid 需要父容器在两个轴上都有界 '
          '(例如 Scaffold body / Column + Expanded)，'
          '不要直接放进 SingleChildScrollView 或 ListView。',
        );
        final ratio = c.maxWidth / c.maxHeight;
        final cols = (baseColumns * (ratio / baseRatio))
            .clamp(minColumns, maxColumns)
            .round();
        final gap = (c.maxWidth / cols) * gapRatio;

        return GridView.builder(
          padding: padding,
          physics: scrollPhysics,
          shrinkWrap: shrinkWrap,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: gap,
            crossAxisSpacing: gap,
            childAspectRatio: childAspectRatio,
          ),
          itemCount: itemCount,
          itemBuilder: itemBuilder,
        );
      },
    );
  }
}

/// 2. Sliver 版 —— 嵌进 CustomScrollView 用
/// 用 viewport 的宽高算 ratio（不是 sliver 自身的内容高度）
class SliverAspectDrivenGrid extends StatelessWidget {
  const SliverAspectDrivenGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.baseColumns = 2,
    this.baseRatio = 1.0,
    this.gapRatio = 0.04,
    this.childAspectRatio = 1.0,
    this.minColumns = 1,
    this.maxColumns = 6,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  /// 基准宽高比下的列数（默认 2）
  final int baseColumns;

  /// 基准宽高比（默认 1.0 = 1:1）
  final double baseRatio;

  /// 间距 = 列宽 × 此比例
  final double gapRatio;

  /// item 自身的宽/高比。
  final double childAspectRatio;

  final int minColumns;
  final int maxColumns;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, c) {
        // 可视宽高 = viewport 宽 × viewport 高（始终有界）
        final ratio = c.crossAxisExtent / c.viewportMainAxisExtent;
        final cols = (baseColumns * (ratio / baseRatio))
            .clamp(minColumns, maxColumns)
            .round();
        final gap = (c.crossAxisExtent / cols) * gapRatio;

        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: gap,
            crossAxisSpacing: gap,
            childAspectRatio: childAspectRatio,
          ),
          delegate: SliverChildBuilderDelegate(
            itemBuilder,
            childCount: itemCount,
          ),
        );
      },
    );
  }
}

/// 3. Pinterest 瀑布流版 —— item 高度不一时使用
/// 需要 pubspec.yaml: flutter_staggered_grid_view
class MasonryAspectDrivenGrid extends StatelessWidget {
  const MasonryAspectDrivenGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.baseColumns = 2,
    this.baseRatio = 1.0,
    this.gapRatio = 0.04,
    this.minColumns = 1,
    this.maxColumns = 6,
    this.padding = EdgeInsets.zero,
    this.scrollPhysics,
    this.shrinkWrap = false,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final int baseColumns;
  final double baseRatio;
  final double gapRatio;
  final int minColumns;
  final int maxColumns;
  final EdgeInsetsGeometry padding;
  final ScrollPhysics? scrollPhysics;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        assert(
          c.hasBoundedWidth && c.hasBoundedHeight,
          'MasonryAspectDrivenGrid 需要父容器在两个轴上都有界',
        );
        final ratio = c.maxWidth / c.maxHeight;
        final cols = (baseColumns * (ratio / baseRatio))
            .clamp(minColumns, maxColumns)
            .round();
        final gap = (c.maxWidth / cols) * gapRatio;

        return MasonryGridView.count(
          padding: padding,
          physics: scrollPhysics,
          shrinkWrap: shrinkWrap,
          crossAxisCount: cols,
          mainAxisSpacing: gap,
          crossAxisSpacing: gap,
          itemCount: itemCount,
          itemBuilder: itemBuilder,
        );
      },
    );
  }
}
