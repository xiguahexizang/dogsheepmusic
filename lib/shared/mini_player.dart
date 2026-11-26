import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:dog_sheep_player/app/theme.dart';
import 'package:dog_sheep_player/core/providers.dart';
import 'package:dog_sheep_player/features/player/player_provider.dart';
import 'package:dog_sheep_player/shared/cover_image.dart';
import 'package:dog_sheep_player/shared/responsive.dart';

/// 底部迷你播放器
///
/// 固定于底部导航上方，展示当前曲目并提供播放/暂停快捷操作。
/// 无播放内容（[currentItemProvider] 为空）时整体隐藏（高度为 0）。
/// 点击整行打开全屏播放器。
///
/// 播放/暂停统一走 handler 的 togglePlayPause（以播放内核的
/// 实时 playing 为准），不在 UI 侧缓存任何状态。
///
/// 折叠屏展开态（>= 600dp）默认隐藏：此时 Shell 右侧已常驻完整
/// [PlayerPanel]，MiniPlayer 与之互斥。若某个全屏路由（如队列页）在展开态
/// 仍需播放条，可传入 [forceVisible] = true 覆盖该策略。
class MiniPlayer extends ConsumerWidget {
  final bool forceVisible;

  const MiniPlayer({super.key, this.forceVisible = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 展开态（有右侧播放器面板承载）隐藏，除非显式要求保留。
    if (!forceVisible && Responsive.isFoldable(context)) {
      return const SizedBox.shrink();
    }

    final item = ref.watch(currentItemProvider).valueOrNull;
    if (item == null) return const SizedBox.shrink();

    final isPlaying = ref.watch(isPlayingProvider);
    final handler = ref.read(audioHandlerProvider);

    return Material(
      color: AppTheme.bgCard,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          boxShadow: [
            // 顶部阴影线（向上投影）
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _ProgressBar(),
            SizedBox(
              height: 60,
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => context.push('/player'),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            Hero(
                              tag: 'cover_${item.bvid}',
                              flightShuttleBuilder: (_, __, ___, ____, _____) {
                                return CoverImage(
                                    url: item.coverUrl, size: 100, radius: 12);
                              },
                              child: CoverImage(
                                  url: item.coverUrl, size: 44, radius: 8),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textMain,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    item.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textSub,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    iconSize: 30,
                    onPressed: () => handler.togglePlayPause(),
                    icon: Icon(
                      isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: AppTheme.accent,
                    ),
                  ),
                  IconButton(
                    onPressed: () => context.push('/queue'),
                    icon: const Icon(Icons.queue_music_rounded,
                        color: AppTheme.textSub),
                  ),
                  const SizedBox(width: 6),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 极细播放进度线（暖金填充）
class _ProgressBar extends ConsumerWidget {
  const _ProgressBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(positionProvider).valueOrNull ?? Duration.zero;
    final duration = ref.watch(durationProvider).valueOrNull ?? Duration.zero;
    final ratio = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    return SizedBox(
      height: 2,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: AppTheme.divider),
          Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: ratio,
              child: const ColoredBox(color: AppTheme.accent),
            ),
          ),
        ],
      ),
    );
  }
}
