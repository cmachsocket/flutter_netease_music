import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../SongListPage/SongListCard.dart';
import '../widgets/aspect_driven_grid.dart';
import 'HomeController.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final home = Get.find<HomeController>();
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        // 推荐歌单标题 —— Align 让 Text 撑满宽度后靠左,不需要 padding
        Align(
          alignment: Alignment.centerLeft,
          child: Text('推荐歌单', style: textTheme.titleLarge),
        ),

        // 推荐歌单网格
        Expanded(child: _RecommendedGrid(home: home)),
      ],
    );
  }
}

/// 推荐歌单网格:loading / error / 数据三态
class _RecommendedGrid extends StatelessWidget {
  const _RecommendedGrid({required this.home});

  final HomeController home;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (home.isLoading.value) {
        return const Center(child: CircularProgressIndicator());
      }
      if (home.errorMessage.value != null) {
        return Center(
          child: Text(
            '加载失败:${home.errorMessage.value}',
            textAlign: TextAlign.center,
          ),
        );
      }
      if (home.recommended.isEmpty) {
        return const Center(child: Text('暂无推荐'));
      }
      return AspectDrivenGrid(
        childAspectRatio: 0.8,
        minColumns: 2,
        itemCount: home.recommended.length,
        itemBuilder: (context, index) {
          final card = home.recommended[index];
          return SongListCard(
            playlistId: card.id,
            title: card.name,
            subtitle: '',
            imageUrl: card.picUrl,
          );
        },
      );
    });
  }
}

class HomePageBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut(() => HomeController());
  }
}
