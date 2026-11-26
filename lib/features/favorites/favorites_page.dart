import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dog_sheep_player/app/theme.dart';
import 'package:dog_sheep_player/core/audio/audio_handler.dart';
import 'package:dog_sheep_player/features/player/player_provider.dart';
import 'package:dog_sheep_player/shared/empty_state.dart';
import 'package:dog_sheep_player/shared/favorites.dart';
import 'package:dog_sheep_player/shared/models.dart';
import 'package:dog_sheep_player/shared/track_tile.dart';

/// 收藏页 — 展示所有收藏曲目，支持播放全部、左滑取消收藏
class FavoritesPage extends ConsumerWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 依赖 favoritesProvider 触发重建
    final favSet = ref.watch(favoritesProvider);
    final favorites = ref.watch(_favoritesListProvider);

    final currentBvid = ref.watch(currentItemProvider).valueOrNull?.bvid;
    final isPlaying = ref.watch(isPlayingProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            const Text('我的收藏'),
            if (favorites.isNotEmpty)
              Text(
                '${favorites.length} 首收藏',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: AppTheme.textSub),
              ),
          ],
        ),
        centerTitle: false,
        actions: [
          if (favorites.isNotEmpty)
            IconButton(
              tooltip: '播放全部',
              icon: const Icon(Icons.playlist_play_rounded),
              onPressed: () => _playAll(ref, favorites),
            ),
        ],
      ),
      body: favSet.isEmpty
          ? const EmptyState(
              icon: Icons.favorite_border_rounded,
              title: '还没有收藏歌曲',
              message: '在播放器中点击心形按钮收藏喜欢的歌曲',
            )
          : RefreshIndicator(
              color: AppTheme.accent,
              backgroundColor: AppTheme.bgCard,
              onRefresh: () async => ref.invalidate(favoritesProvider),
              child: _FavoritesList(
                favorites: favorites,
                currentBvid: currentBvid,
                isPlaying: isPlaying,
              ),
            ),
    );
  }

  void _playAll(WidgetRef ref, List<FavoriteTrack> favorites) {
    if (favorites.isEmpty) return;
    final items = favorites
        .map((f) => PlayQueueItem(
              bvid: f.bvid,
              title: f.title,
              artist: f.artist,
              coverUrl: f.coverUrl,
              duration: f.duration,
              isMusicTrack: f.isMusicTrack,
            ))
        .toList();
    ref.read(playQueueProvider.notifier).play(items);
  }
}

/// 收藏列表 Provider：返回 FavoriteTrack 列表，跟随 favoritesProvider 重建
final _favoritesListProvider = Provider<List<FavoriteTrack>>((ref) {
  // 依赖 favoritesProvider 的 Set 状态来触发重建
  ref.watch(favoritesProvider);
  return ref.read(favoritesProvider.notifier).all;
});

// ─── 收藏列表（ConsumerWidget，可在 build 中安全使用 ref）──────────────────

class _FavoritesList extends ConsumerWidget {
  final List<FavoriteTrack> favorites;
  final String? currentBvid;
  final bool isPlaying;

  const _FavoritesList({
    required this.favorites,
    required this.currentBvid,
    required this.isPlaying,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 列表项以独立白色卡片展示
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: favorites.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        if (i == 0) return _buildHeader(context, ref);
        return _buildItem(context, ref, favorites[i - 1]);
      },
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: AppTheme.cardDecoration(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.accent, AppTheme.accentDim],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.favorite_rounded,
                color: Colors.white, size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('我的收藏', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 3),
                Text(
                  '${favorites.length} 首曲目',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppTheme.textSub),
                ),
              ],
            ),
          ),
          if (favorites.isNotEmpty)
            FilledButton.icon(
              onPressed: () {
                final items = favorites
                    .map((f) => PlayQueueItem(
                          bvid: f.bvid,
                          title: f.title,
                          artist: f.artist,
                          coverUrl: f.coverUrl,
                          duration: f.duration,
                          isMusicTrack: f.isMusicTrack,
                        ))
                    .toList();
                ref.read(playQueueProvider.notifier).play(items);
              },
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('播放全部'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, WidgetRef ref, FavoriteTrack fav) {
    final isCurrent = fav.bvid == currentBvid;
    final controller = ref.read(favoritesProvider.notifier);

    return Dismissible(
      key: ValueKey('fav_${fav.bvid}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) {
        controller.remove(fav.bvid);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已取消收藏「${fav.title}」'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(milliseconds: 1500),
          ),
        );
      },
      background: Container(
        alignment: Alignment.centerRight,
        decoration: AppTheme.cardDecoration(color: const Color(0xFFFDECEA)),
        padding: const EdgeInsets.only(right: 24),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite_border_rounded,
                color: AppTheme.danger, size: 20),
            SizedBox(width: 6),
            Text(
              '取消收藏',
              style: TextStyle(color: AppTheme.danger, fontSize: 13),
            ),
          ],
        ),
      ),
      child: Container(
        decoration: AppTheme.cardDecoration(),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        child: TrackTile(
          title: fav.title,
          artist: fav.artist,
          coverUrl: fav.coverUrl,
          duration: fav.duration,
          isCurrent: isCurrent,
          isPlaying: isCurrent && isPlaying,
          heroTag: 'cover_${fav.bvid}',
          onTap: () => _playFav(ref, fav),
          onLongPress: () => _confirmRemove(context, ref, fav),
        ),
      ),
    );
  }

  void _playFav(WidgetRef ref, FavoriteTrack fav) {
    final item = PlayQueueItem(
      bvid: fav.bvid,
      title: fav.title,
      artist: fav.artist,
      coverUrl: fav.coverUrl,
      duration: fav.duration,
      isMusicTrack: fav.isMusicTrack,
    );
    final notifier = ref.read(playQueueProvider.notifier);
    final queue = ref.read(playQueueProvider);
    final existing = queue.indexWhere((e) => e.bvid == item.bvid);
    if (existing >= 0) {
      notifier.playIndex(existing);
    } else {
      // addAll 返回新加入第一项的索引，直接播放该索引
      final newIdx = queue.length; // 新曲目在队尾
      notifier.addAll([item]);
      notifier.playIndex(newIdx);
    }
  }

  Future<void> _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    FavoriteTrack fav,
  ) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('取消收藏'),
        content: Text('要从收藏中移除「${fav.title}」吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('移除', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (yes == true) {
      await ref.read(favoritesProvider.notifier).remove(fav.bvid);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已取消收藏「${fav.title}」'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(milliseconds: 1500),
          ),
        );
      }
    }
  }
}
