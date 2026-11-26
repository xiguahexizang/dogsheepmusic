import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:dog_sheep_player/app/theme.dart';
import 'package:dog_sheep_player/core/bili_api/music.dart';
import 'package:dog_sheep_player/core/bili_api/music_recommend.dart';
import 'package:dog_sheep_player/core/providers.dart';
import 'package:dog_sheep_player/features/home/home_provider.dart';
import 'package:dog_sheep_player/features/player/player_provider.dart';
import 'package:dog_sheep_player/shared/cover_image.dart';
import 'package:dog_sheep_player/shared/empty_state.dart';
import 'package:dog_sheep_player/shared/fade_in.dart';
import 'package:dog_sheep_player/shared/loading_shimmer.dart';
import 'package:dog_sheep_player/shared/responsive.dart';
import 'package:dog_sheep_player/shared/track_tile.dart';
import 'package:dog_sheep_player/shared/utils.dart';

/// 首页 —— 问候语、Hi-Res 精选与音乐排行
///
/// 内容源**全部为音乐**：全站视频推荐（`index/top/rcmd`）与全站热门
/// （`popular`）均已弃用。点击任意曲目即以 20-30 首随机队列起播，
/// 播完自动随机下一首（队列将走完时后台续源）。
///
/// 视觉：浅灰页面背景 + 白色圆角卡片（QQ 音乐风格）
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  @override
  void initState() {
    super.initState();
    // 首帧后拉候选池 + 后台扫描 Hi-Res（不 await，避免阻塞渲染）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) startHomeRecommend(ref);
    });
  }

  Future<void> _refresh() async {
    final rec = ref.read(musicRecommendProvider);
    await Future.wait([
      ref.refresh(hotSongsProvider.future),
      rec.ensurePool(force: true),
    ]);
    rec.startScan();
  }

  @override
  Widget build(BuildContext context) {
    final nickname = ref.watch(userNicknameProvider);
    final greeting = greetingForNow();
    final current = ref.watch(currentItemProvider).valueOrNull;
    final isPlaying = ref.watch(isPlayingProvider);
    // 直板机 / 外屏收紧左右内边距，卡片与列表能多出一档可用宽度
    final padX = Responsive.pageHorizontalPadding(
      Responsive.getScreenWidth(context),
    );

    final picksAsync = ref.watch(hiResPicksProvider);
    final statsAsync = ref.watch(musicPoolStatsProvider);
    final hotAsync = ref.watch(hotSongsProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppTheme.accent,
          backgroundColor: AppTheme.bgCard,
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(padX, 24, padX, 24),
            children: [
              // ── 问候语 + 用户名（直接置于浅灰背景之上）──
              FadeIn(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      greeting,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppTheme.textSub),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      nickname == null || nickname.isEmpty
                          ? '欢迎回来 🐕🐑'
                          : nickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // ── Hi-Res 精选（横向白色卡片，只列确认有 Hi-Res 的曲目）──
              _SectionHeader(
                title: 'Hi-Res 精选',
                actionLabel: '换一批',
                onAction: () => ref.read(musicRecommendProvider).rotatePicks(),
              ),
              const SizedBox(height: 12),
              _HiresPicksRow(
                asyncValue: picksAsync,
                statsAsync: statsAsync,
                currentBvid: current?.bvid,
                onTap: (track) => playRandomFrom(ref, track),
                onShuffleAll: () => playRandomMix(ref),
              ),
              const SizedBox(height: 28),

              // ── 音乐排行 Top 10（整体白色卡片）──
              _SectionHeader(
                title: '音乐排行',
                actionLabel: '更多',
                onAction: () => context.go('/music'),
              ),
              const SizedBox(height: 8),
              _HotSongsCard(
                asyncValue: hotAsync,
                currentBvid: current?.bvid,
                isPlaying: isPlaying,
                onTap: (tracks, index) => playTrackList(ref, tracks, index),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

/// 区块标题：深色粗体 + 右侧金色「更多」按钮
class _SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _SectionHeader({required this.title, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppTheme.textMain,
                fontWeight: FontWeight.w700,
              ),
        ),
        const Spacer(),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.accent,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              visualDensity: VisualDensity.compact,
            ),
            child: Text(actionLabel!),
          ),
      ],
    );
  }
}

/// Hi-Res 精选横向滚动卡片行（含扫描进度与「随机播放」入口）
class _HiresPicksRow extends StatelessWidget {
  final AsyncValue<List<MusicTrack>> asyncValue;
  final AsyncValue<MusicPoolStats> statsAsync;
  final String? currentBvid;
  final void Function(MusicTrack track) onTap;
  final VoidCallback onShuffleAll;

  const _HiresPicksRow({
    required this.asyncValue,
    required this.statsAsync,
    required this.currentBvid,
    required this.onTap,
    required this.onShuffleAll,
  });

  @override
  Widget build(BuildContext context) {
    final tracks = asyncValue.valueOrNull ?? const <MusicTrack>[];
    final stats = statsAsync.valueOrNull;

    // 尚无确认曲目：给进度提示（候选池 / 已探测数），失败那么空态提示
    if (tracks.isEmpty) {
      final failed = (stats?.error != null) || asyncValue.hasError;
      return SizedBox(
        height: 190,
        child: failed
            ? const EmptyState(
                icon: Icons.cloud_off,
                title: 'Hi-Res 推荐加载失败',
                message: '下拉重试',
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const LoadingShimmer(width: 120, height: 120, square: true),
                  const SizedBox(height: 10),
                  Text(
                    stats == null
                        ? '正在准备音乐候选池…'
                        : '正在扫描 Hi-Res 音轨… 已探测 ${stats.probed} / '
                            '${stats.poolSize} 首',
                    style:
                        const TextStyle(fontSize: 12, color: AppTheme.textSub),
                  ),
                ],
              ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 进度 / 随机播放入口 ──
        Row(
          children: [
            Expanded(
              child: Text(
                '已确认 ${tracks.length} 首含 Hi-Res'
                '${stats == null ? '' : ' · 候选 ${stats.poolSize} 首'}'
                '${stats != null && stats.scanning ? ' · 扫描中…' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppTheme.textSub),
              ),
            ),
            FilledButton.icon(
              onPressed: onShuffleAll,
              icon: const Icon(Icons.shuffle_rounded, size: 16),
              label: const Text('随机播放'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 按内容区实际宽度分档放大 / 缩小横向卡片（窄屏不拥挤、宽屏更大气）。
        LayoutBuilder(
          builder: (context, c) {
            final cover = Responsive.pickCoverWidth(c.maxWidth);
            return SizedBox(
              // 卡片内容高度 = 上下 padding(20) + 封面 + 8 + 标题行 + 2 + 艺人行。
              // CanvasKit 下 13/12px 中文行高约 18.5/17，留足余量避免
              // “BOTTOM OVERFLOWED BY 1.00 PIXELS”（实测 68 会溢出 1px）。
              height: cover + 82,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                padding: EdgeInsets.zero,
                itemCount: tracks.length,
                separatorBuilder: (_, __) =>
                    SizedBox(width: cover >= 150 ? 14 : 10),
                itemBuilder: (context, i) {
                  final t = tracks[i];
                  return FadeIn(
                    delay: Duration(milliseconds: 40 * i.clamp(0, 6)),
                    child: _PicksCard(
                      track: t,
                      isCurrent: t.bvid == currentBvid,
                      coverSize: cover,
                      onTap: () => onTap(t),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }
}

/// 单张 Hi-Res 精选卡片（白色底 + 圆角封面 + 徽标 + 阴影）
class _PicksCard extends StatelessWidget {
  final MusicTrack track;
  final bool isCurrent;
  final VoidCallback onTap;
  final double coverSize;
  const _PicksCard({
    required this.track,
    required this.isCurrent,
    required this.onTap,
    this.coverSize = 132,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.bgCard,
      borderRadius: AppTheme.borderRadius,
      elevation: 2,
      shadowColor: AppTheme.cardShadow,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppTheme.borderRadius,
        child: SizedBox(
          width: coverSize + 20,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    CoverImage(url: track.cover, size: coverSize, radius: 12),
                    // Hi-Res 徽标（本区块只列已确认 30251/fLaC 的曲目）
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.accent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Hi-Res',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? AppTheme.accent
                              : Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                          boxShadow: const [
                            BoxShadow(
                              color: AppTheme.cardShadow,
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          isCurrent
                              ? Icons.equalizer_rounded
                              : Icons.play_arrow_rounded,
                          size: 20,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isCurrent ? AppTheme.accent : AppTheme.textMain,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSub),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 音乐排行 —— 整体放在一个白色圆角卡片容器内
class _HotSongsCard extends StatelessWidget {
  final AsyncValue<List<MusicTrack>> asyncValue;
  // 只传 bvid 字符串：避开 `dynamic` 字段在 release Web（dart2js）下的
  // 动态成员查找风险（方法 / 字段名可能未被保留）。
  final String? currentBvid;
  final bool isPlaying;
  final void Function(List<MusicTrack> tracks, int index) onTap;

  const _HotSongsCard({
    required this.asyncValue,
    required this.currentBvid,
    required this.isPlaying,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.cardDecoration(),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: asyncValue.when(
        loading: () => const SizedBox(
          height: 260,
          child: LoadingShimmer.trackList(count: 5),
        ),
        error: (e, _) => const SizedBox(
          height: 176,
          child: EmptyState(
            icon: Icons.cloud_off,
            title: '音乐排行加载失败',
            message: '下拉重试',
          ),
        ),
        data: (tracks) {
          if (tracks.isEmpty) {
            return const SizedBox(
              height: 140,
              child: EmptyState(title: '暂无排行榜内容'),
            );
          }
          return Column(
            children: [
              for (var i = 0; i < tracks.length; i++)
                FadeIn(
                  delay: Duration(milliseconds: 30 * i),
                  child: TrackTile(
                    rank: i + 1,
                    title: tracks[i].title,
                    artist: tracks[i].artist,
                    coverUrl: tracks[i].cover,
                    duration: tracks[i].duration,
                    isCurrent: tracks[i].bvid == currentBvid,
                    isPlaying: isPlaying,
                    heroTag: 'cover_${tracks[i].bvid}',
                    onTap: () => onTap(tracks, i),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
