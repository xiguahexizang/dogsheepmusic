import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:dog_sheep_player/app/theme.dart';
import 'package:dog_sheep_player/core/bili_api/music.dart';
import 'package:dog_sheep_player/features/music/music_provider.dart';
import 'package:dog_sheep_player/features/player/player_provider.dart';
import 'package:dog_sheep_player/shared/cover_image.dart';
import 'package:dog_sheep_player/shared/empty_state.dart';
import 'package:dog_sheep_player/shared/loading_shimmer.dart';
import 'package:dog_sheep_player/shared/models.dart';
import 'package:dog_sheep_player/shared/track_tile.dart';
import 'package:dog_sheep_player/shared/utils.dart';

/// 歌单详情页：封面 + 标题 + 曲目列表 + 播放全部
class PlaylistDetailPage extends ConsumerWidget {
  final PlaylistInfo playlist;

  const PlaylistDetailPage({super.key, required this.playlist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = ref.watch(playlistTracksProvider(playlist.id));
    final current = ref.watch(currentItemProvider).valueOrNull;
    final isPlaying = ref.watch(isPlayingProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 240,
            backgroundColor: AppTheme.bgPrimary,
            title: tracksAsync.hasValue ? Text(playlist.name) : null,
            leading: IconButton(
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
              onPressed: () {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                } else {
                  context.go('/music');
                }
              },
            ),
            flexibleSpace: FlexibleSpaceBar(
              background:
                  _PlaylistHeader(playlist: playlist, async: tracksAsync),
            ),
          ),
          tracksAsync.when(
            loading: () => const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: LoadingShimmer.trackList(count: 8),
              ),
            ),
            error: (e, _) => SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.cloud_off,
                title: '歌单加载失败',
                message: '$e',
                actionLabel: '重试',
                onAction: () =>
                    ref.refresh(playlistTracksProvider(playlist.id)),
              ),
            ),
            data: (tracks) {
              if (tracks.isEmpty) {
                return const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(title: '该歌单暂无曲目'),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final t = tracks[i];
                      // 每首曲目一张白色卡片
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          decoration: AppTheme.cardDecoration(),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          child: TrackTile(
                            index: i,
                            title: t.title,
                            artist: t.artist,
                            coverUrl: t.cover,
                            duration: t.duration,
                            isCurrent: current?.bvid == t.bvid,
                            isPlaying: isPlaying,
                            heroTag: 'cover_${t.bvid}',
                            onTap: () => playTrackList(ref, tracks, i),
                          ),
                        ),
                      );
                    },
                    childCount: tracks.length,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      bottomNavigationBar: _buildPlayBar(context, ref, tracksAsync),
    );
  }

  Widget? _buildPlayBar(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<MusicTrack>> tracksAsync,
  ) {
    final tracks = tracksAsync.valueOrNull;
    if (tracks == null || tracks.isEmpty) return null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: ElevatedButton.icon(
          onPressed: () => playTrackList(ref, tracks, 0),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text('播放全部 (${tracks.length})'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ),
    );
  }
}

/// SliverAppBar 头部：模糊封面背景 + 前景封面/标题/歌曲数
class _PlaylistHeader extends StatelessWidget {
  final PlaylistInfo playlist;
  final AsyncValue<List<MusicTrack>> async;

  const _PlaylistHeader({required this.playlist, required this.async});

  @override
  Widget build(BuildContext context) {
    // 注意：这里必须保持静态类型。release Web（dart2js）下对 `dynamic`
    // 接收者调用 `valueOrNull` 会抛 NoSuchMethodError（方法名未被保留）。
    final count = async.valueOrNull?.length ?? playlist.trackCount;
    return Stack(
      fit: StackFit.expand,
      children: [
        // 模糊背景
        if (playlist.cover.isNotEmpty)
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Image.network(
              CoverImage.normalize(playlist.cover) ?? '',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x8CF5F6FA), AppTheme.bgPrimary],
            ),
          ),
          child: SizedBox.expand(),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 44, 20, 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (playlist.cover.isNotEmpty)
                  CoverImage(
                    url: playlist.cover,
                    size: 96,
                    radius: AppTheme.radius,
                  ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        playlist.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      if (playlist.description.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          playlist.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        count != null ? '$count 首歌曲' : '歌单',
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(color: AppTheme.accent),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
