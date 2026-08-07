import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../ArtistPage/ArtistDetail.dart';
import '../SongListPage/SongListDetail.dart';
import '../AppShell.dart';
import '../models/Song.dart';

class LinkedDetailText extends StatelessWidget {
  final Song song;
  final VoidCallback? onTap;
  final TextStyle? textStyle;
  final MainAxisAlignment? mainAxisAlignment;
  const LinkedDetailText({
    super.key,
    required this.song,
    this.onTap,
    this.textStyle,
    this.mainAxisAlignment,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      mainAxisAlignment: mainAxisAlignment ?? MainAxisAlignment.start,
      children: [
        TextButton(
          onPressed: () {
            Get.to(
              () => ArtistDetail(artistId: "111"),
              id: AppShell.shellNavigatorId,
              binding: ArtistDetailBinding(artistId: "111"),
            );
          },
          child: Text(
            'Artist Name',
            maxLines: 1,
            style: textStyle ?? textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          '-',
          textAlign: TextAlign.center,
          style: textStyle ?? textTheme.bodySmall,
        ),
        TextButton(
          onPressed: () {
            Get.to(
              () => SongListDetail(playlistId: "111"),
              id: AppShell.shellNavigatorId,
              binding: SongListDetailBinding(playlistId: "111"),
            );
          },
          child: Text(
            'Album Name',
            maxLines: 1,
            style: textStyle ?? textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
