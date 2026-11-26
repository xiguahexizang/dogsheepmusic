import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:dog_sheep_player/app/theme.dart';
import 'package:dog_sheep_player/features/music/music_provider.dart';
import 'package:dog_sheep_player/features/player/player_provider.dart';
import 'package:dog_sheep_player/shared/empty_state.dart';
import 'package:dog_sheep_player/shared/fade_in.dart';
import 'package:dog_sheep_player/shared/loading_shimmer.dart';
import 'package:dog_sheep_player/shared/track_tile.dart';
import 'package:dog_sheep_player/shared/utils.dart';

/// 音乐区 —— 排行榜 / 搜索入口（推荐歌单展示已移除）
class MusicPage extends ConsumerStatefulWidget {
  const MusicPage({super.key});

  @override
  ConsumerState<MusicPage> createState() => _MusicPageState();
}

class _MusicPageState extends ConsumerState<MusicPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab =
      TabController(length: 2, vsync: this, initialIndex: 0);

  @override
  void initState() {
    super.initState();
    // 「搜索」为入口 Tab：选中即跳转搜索页并回退到首个 Tab
    _tab.addListener(() {
      if (_tab.index == 1) {
        _tab.animateTo(0, duration: const Duration(milliseconds: 200));
        context.push('/search');
      }
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 顶部白色卡片式头部（含 TabBar）
      appBar: AppBar(
        backgroundColor: AppTheme.bgCard,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('音乐区'),
        bottom: TabBar(
          controller: _tab,
          dividerColor: AppTheme.divider,
          tabs: const [
            Tab(text: '排行榜'),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search, size: 18),
                  SizedBox(width: 4),
                  Text('搜索'),
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _RankingTab(),
          SizedBox.shrink(), // 搜索入口占位（选中即跳转）
        ],
      ),
    );
  }
}

/// 排行榜 Tab
class _RankingTab extends ConsumerWidget {
  const _RankingTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(rankingProvider);
    final current = ref.watch(currentItemProvider).valueOrNull;
    final isPlaying = ref.watch(isPlayingProvider);

    return RefreshIndicator(
      color: AppTheme.accent,
      backgroundColor: AppTheme.bgCard,
      onRefresh: () async => ref.refresh(rankingProvider.future),
      child: async.when(
        loading: () => const _RankingLoading(),
        error: (e, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            EmptyState(
              icon: Icons.cloud_off,
              title: '排行榜加载失败',
              message: '点击下拉刷新重试',
            ),
          ],
        ),
        data: (tracks) {
          if (tracks.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                EmptyState(title: '暂无排行数据'),
              ],
            );
          }
          // 整个排行榜放入一个白色圆角卡片
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Container(
                decoration: AppTheme.cardDecoration(),
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                child: Column(
                  children: [
                    _RankingHeader(
                      total: tracks.length,
                      onPlayAll: () => playTrackList(ref, tracks, 0),
                    ),
                    const Divider(height: 1),
                    for (var idx = 0; idx < tracks.length; idx++) ...[
                      FadeIn(
                        delay: Duration(milliseconds: 25 * idx.clamp(0, 10)),
                        child: TrackTile(
                          rank: idx + 1,
                          title: tracks[idx].title,
                          artist: tracks[idx].artist,
                          coverUrl: tracks[idx].cover,
                          duration: tracks[idx].duration,
                          isCurrent: current?.bvid == tracks[idx].bvid,
                          isPlaying: isPlaying,
                          heroTag: 'cover_${tracks[idx].bvid}',
                          onTap: () => playTrackList(ref, tracks, idx),
                        ),
                      ),
                      if (idx != tracks.length - 1)
                        const Divider(height: 1, indent: 46),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 排行榜顶部「播放全部」
class _RankingHeader extends StatelessWidget {
  final int total;
  final VoidCallback onPlayAll;
  const _RankingHeader({required this.total, required this.onPlayAll});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.leaderboard_rounded, color: AppTheme.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '共 $total 首在榜',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          OutlinedButton.icon(
            onPressed: onPlayAll,
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('播放全部'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.accent,
              side: const BorderSide(color: AppTheme.accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _RankingLoading extends StatelessWidget {
  const _RankingLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: const [
        LoadingShimmer(height: 32, itemCount: 1),
        SizedBox(height: 16),
        LoadingShimmer.trackList(count: 10),
      ],
    );
  }
}
