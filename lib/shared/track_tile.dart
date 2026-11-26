import 'package:flutter/material.dart';

import 'package:dog_sheep_player/app/theme.dart';
import 'package:dog_sheep_player/shared/cover_image.dart';
import 'package:dog_sheep_player/shared/utils.dart';

/// 歌曲列表项：序号/封面 + 曲名 + 艺术家 + 时长
///
/// [rank] 非空时左侧显示排名序号（排行榜风格），否则显示封面。
/// [isCurrent] 为真时，左侧以**金色竖线**标记（替代整行高亮），并显示播放动画图标。
class TrackTile extends StatelessWidget {
  final String title;
  final String artist;
  final String? coverUrl;
  final int duration;
  final int? rank;

  /// 序号（从 1 开始）；为 null 时不显示序号列
  final int? index;
  final bool isCurrent;
  final bool isPlaying;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Hero 动画标签（通常为 `cover_{bvid}`）；为 null 时不启用 Hero
  final String? heroTag;

  const TrackTile({
    super.key,
    required this.title,
    required this.artist,
    this.coverUrl,
    this.duration = 0,
    this.rank,
    this.index,
    this.isCurrent = false,
    this.isPlaying = false,
    this.onTap,
    this.onLongPress,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: AppTheme.borderRadius,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            // 当前播放标记：左侧金色竖线
            Container(
              width: 3,
              height: 26,
              margin: const EdgeInsets.only(right: 9),
              decoration: BoxDecoration(
                color: isCurrent ? AppTheme.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _leading(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: AppTheme.textMain,
                      fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (isCurrent && isPlaying)
              const _PlayingIndicator()
            else if (duration > 0)
              Text(
                formatDuration(duration),
                style: theme.textTheme.bodySmall,
              )
            else
              const Icon(Icons.play_arrow_rounded, size: 20, color: AppTheme.textSub),
          ],
        ),
      ),
    );
  }

  Widget _leading() {
    if (rank != null) {
      final top = rank! <= 3;
      return SizedBox(
        width: 28,
        child: Text(
          '$rank',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            fontStyle: FontStyle.italic,
            color: top ? AppTheme.accent : AppTheme.textSub,
          ),
        ),
      );
    }
    if (index != null) {
      return SizedBox(
        width: 24,
        child: Text(
          '${index! + 1}',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13,
              fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
              color: isCurrent ? AppTheme.accent : AppTheme.textSub),
        ),
      );
    }
    return heroCover(
      heroTag: heroTag,
      coverUrl: coverUrl,
      size: 44,
      radius: 8,
    );
  }
}

/// 包含 Hero 的封面缩略图
/// 用于列表页和播放器页之间平滑过渡
Widget heroCover({
  required String? heroTag,
  required String? coverUrl,
  required double size,
  double radius = 8,
}) {
  final image = CoverImage(url: coverUrl, size: size, radius: radius);
  if (heroTag == null) return image;
  return Hero(
    tag: heroTag,
    flightShuttleBuilder: (_, anim, __, fromCtx, toCtx) {
      // 飞行过程中统一使用方形封面
      return CoverImage(url: coverUrl, size: 100, radius: 12);
    },
    child: image,
  );
}

/// 三根跳动的均衡器条，表示当前正在播放
class _PlayingIndicator extends StatefulWidget {
  const _PlayingIndicator();

  @override
  State<_PlayingIndicator> createState() => _PlayingIndicatorState();
}

class _PlayingIndicatorState extends State<_PlayingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = (_c.value * 2 * 3.14159 + i * 1.1) % 3.14159;
            final h = 5 + 13 * (0.5 + 0.5 * phase / 3.14159);
            return Container(
              width: 3,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              height: h,
              decoration: BoxDecoration(
                color: AppTheme.accent,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }
}
