import 'package:flutter/material.dart';

import 'package:dog_sheep_player/app/theme.dart';
import 'package:dog_sheep_player/shared/cover_image.dart';

/// 歌单卡片：白色圆角卡片（16px）+ 封面 + 名称 + 描述/歌曲数
class PlaylistCard extends StatelessWidget {
  final String title;
  final String? description;
  final String? coverUrl;
  final int? trackCount;
  final VoidCallback? onTap;

  /// 卡片宽度（网格布局由父级约束时可忽略）
  final double? width;

  const PlaylistCard({
    super.key,
    required this.title,
    this.description,
    this.coverUrl,
    this.trackCount,
    this.onTap,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    const pad = 10.0;
    final cardWidth = width ?? 160.0;
    final coverSize = (cardWidth - pad * 2).clamp(48.0, 480.0);

    return Material(
      color: AppTheme.bgCard,
      borderRadius: AppTheme.borderRadius,
      elevation: 3,
      shadowColor: AppTheme.cardShadow,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppTheme.borderRadius,
        child: SizedBox(
          width: cardWidth,
          child: Padding(
            padding: const EdgeInsets.all(pad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: coverSize,
                  height: coverSize,
                  child: _cover(coverSize),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppTheme.textMain,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                if (description != null || trackCount != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    trackCount != null ? '${trackCount!} 首' : description!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cover(double size) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        // 精选歌单目录是本地描述符（无真实封面），用稳定配色渐变代替灰色占位，
        // 避免首页歌单区块出现成片空白；网络歌单仍走 CoverImage。
        coverUrl == null || coverUrl!.isEmpty
            ? _GradientCover(title: title, size: size)
            : CoverImage(
                url: coverUrl,
                size: size,
                radius: 12,
                fallbackIcon: Icons.playlist_play,
              ),
        Positioned(
          right: 6,
          top: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.play_arrow_rounded, size: 12, color: Colors.white),
                SizedBox(width: 3),
                Icon(Icons.play_arrow_rounded, size: 12, color: Colors.white),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 无封面歌单的渐变占位图：按标题取稳定配色，中间显示歌单首字
/// （同一标题在任何一次构建中颜色一致，避免闪烁）
class _GradientCover extends StatelessWidget {
  final String title;
  final double size;
  const _GradientCover({required this.title, required this.size});

  static const List<List<Color>> _palettes = [
    [Color(0xFFFFE3B0), Color(0xFFFFB37B)],
    [Color(0xFFB8E1FF), Color(0xFF6FA8FF)],
    [Color(0xFFD7BFFF), Color(0xFF9F7BE8)],
    [Color(0xFFB6F2D9), Color(0xFF5FCFA4)],
    [Color(0xFFFFC4D8), Color(0xFFFF8FA8)],
    [Color(0xFFC9D6F5), Color(0xFF8AA0D8)],
  ];

  @override
  Widget build(BuildContext context) {
    final colors = _palettes[title.hashCode.abs() % _palettes.length];
    final initial = title.isEmpty ? '♪' : title.substring(0, 1);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: size * 0.34,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.92),
          ),
        ),
      ),
    );
  }
}
