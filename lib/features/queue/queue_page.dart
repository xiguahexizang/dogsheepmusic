import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dog_sheep_player/app/theme.dart';
import 'package:dog_sheep_player/core/audio/audio_handler.dart';
import 'package:dog_sheep_player/core/providers.dart';
import 'package:dog_sheep_player/features/player/player_provider.dart';
import 'package:dog_sheep_player/shared/cover_image.dart';
import 'package:dog_sheep_player/shared/empty_state.dart';
import 'package:dog_sheep_player/shared/mini_player.dart';

/// 播放队列页
///
/// 支持拖拽排序（手柄）、左滑删除、点击切换播放、清空。
/// [showMiniPlayer] 为 false 时（从播放器页进入）底部不重复显示 MiniPlayer。
class QueuePage extends ConsumerWidget {
  final bool showMiniPlayer;
  const QueuePage({super.key, this.showMiniPlayer = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(playQueueProvider);
    final current = ref.watch(currentItemProvider).valueOrNull;
    final isPlaying = ref.watch(isPlayingProvider);
    final notifier = ref.read(playQueueProvider.notifier);
    final handler = ref.read(audioHandlerProvider);

    final currentIndex = current == null
        ? handler.currentIndex
        : queue
            .indexWhere((e) => e.bvid == current.bvid && e.cid == current.cid);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Column(
          children: [
            const Text('播放列表'),
            Text('${queue.length} 首歌曲',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: AppTheme.textSub)),
          ],
        ),
        centerTitle: false,
        actions: [
          if (queue.isNotEmpty)
            IconButton(
              tooltip: '清空列表',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () => _confirmClear(context, notifier),
            ),
        ],
      ),
      body: queue.isEmpty
          ? const EmptyState(
              icon: Icons.playlist_play_rounded,
              title: '播放列表为空',
              message: '去挑几首歌加入队列吧',
            )
          : ReorderableListView.builder(
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: queue.length,
              onReorder: (oldIndex, newIndex) {
                // Flutter 语义：newIndex 在移除后计算，需回退一位
                final target = newIndex > oldIndex ? newIndex - 1 : newIndex;
                notifier.reorder(oldIndex, target);
              },
              itemBuilder: (context, i) {
                final item = queue[i];
                final isCurrent = i == currentIndex;
                return Dismissible(
                  key: ValueKey('${item.bvid}_${item.cid}_${item.title}'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    color: const Color(0xFFFDECEA),
                    padding: const EdgeInsets.only(right: 24),
                    child: const Icon(Icons.delete_outline_rounded,
                        color: AppTheme.danger),
                  ),
                  onDismissed: (_) => notifier.removeAt(i),
                  child: _QueueTile(
                    item: item,
                    index: i,
                    isCurrent: isCurrent,
                    isPlaying: isCurrent && isPlaying,
                    onTap: () => notifier.playIndex(i),
                    reorderIndex: i,
                  ),
                );
              },
            ),
      bottomNavigationBar:
          // 队列页为全屏路由（无右侧常驻面板），展开态仍保留 MiniPlayer。
          showMiniPlayer
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [MiniPlayer(forceVisible: true)],
                )
              : null,
    );
  }

  Future<void> _confirmClear(
      BuildContext context, PlayQueueNotifier notifier) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空播放列表'),
        content: const Text('确定要移除全部曲目并停止播放吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  const Text('清空', style: TextStyle(color: AppTheme.danger))),
        ],
      ),
    );
    if (yes == true) await notifier.clear();
  }
}

/// 队列单项：序号 + 封面 + 曲名/艺术家 + 拖拽手柄
class _QueueTile extends StatelessWidget {
  final PlayQueueItem item;
  final int index;
  final bool isCurrent;
  final bool isPlaying;
  final VoidCallback onTap;
  final int reorderIndex;

  const _QueueTile({
    required this.item,
    required this.index,
    required this.isCurrent,
    required this.isPlaying,
    required this.onTap,
    required this.reorderIndex,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          // 当前播放标记：左侧金色竖线
          Container(
            width: 3,
            height: 26,
            decoration: BoxDecoration(
              color: isCurrent ? AppTheme.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 4),
          // 拖拽手柄
          ReorderableDragStartListener(
            index: reorderIndex,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Icon(Icons.drag_handle_rounded,
                  color: AppTheme.textSub, size: 22),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 22,
            child: Text(
              '${index + 1}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isCurrent ? AppTheme.accent : AppTheme.textSub,
              ),
            ),
          ),
          const SizedBox(width: 10),
          CoverImage(url: item.coverUrl, size: 44, radius: 8),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (isPlaying)
                        const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: Icon(Icons.equalizer_rounded,
                              size: 15, color: AppTheme.accent),
                        ),
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: AppTheme.textMain,
                            fontWeight:
                                isCurrent ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}
