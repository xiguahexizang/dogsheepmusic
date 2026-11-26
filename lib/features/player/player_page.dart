// BackdropFilter 由 flutter/material 导出，dart:ui 只有 ImageFilter
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:dog_sheep_player/app/theme.dart';
import 'package:dog_sheep_player/core/audio/audio_handler.dart';
import 'package:dog_sheep_player/core/providers.dart';
import 'package:dog_sheep_player/features/player/hi_res_toggle.dart';
import 'package:dog_sheep_player/features/player/lyric_widget.dart';
import 'package:dog_sheep_player/features/player/player_provider.dart';
import 'package:dog_sheep_player/shared/cover_image.dart';
import 'package:dog_sheep_player/shared/empty_state.dart';
import 'package:dog_sheep_player/shared/favorites.dart';
import 'package:dog_sheep_player/shared/responsive.dart';
import 'package:dog_sheep_player/shared/utils.dart';

/// 全屏播放器
class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({super.key});

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage>
    with TickerProviderStateMixin {
  /// 封面旋转
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );

  /// 下滑拖拽偏移
  double _dragY = 0.0;

  /// 本地 seek 值（秒）；null 表示跟随播放进度
  double? _seekValue;

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  void _syncSpin(bool playing) {
    if (playing && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!playing && _spin.isAnimating) {
      _spin.stop();
    }
  }

  IconData _modeIcon(PlayMode mode) {
    switch (mode) {
      case PlayMode.sequence:
        return Icons.repeat_rounded;
      case PlayMode.loopOne:
        return Icons.repeat_one_rounded;
      case PlayMode.shuffle:
        return Icons.shuffle_rounded;
    }
  }

  String _modeLabel(PlayMode mode) {
    switch (mode) {
      case PlayMode.sequence:
        return '顺序播放';
      case PlayMode.loopOne:
        return '单曲循环';
      case PlayMode.shuffle:
        return '随机播放';
    }
  }

  @override
  Widget build(BuildContext context) {
    final handler = ref.read(audioHandlerProvider);
    final itemAsync = ref.watch(currentItemProvider);
    final item = itemAsync.valueOrNull;
    final isPlaying = ref.watch(isPlayingProvider);
    _syncSpin(isPlaying);

    final position = ref.watch(positionProvider).valueOrNull ?? Duration.zero;
    final duration = ref.watch(durationProvider).valueOrNull ??
        (item != null && item.duration > 0
            ? Duration(seconds: item.duration)
            : Duration.zero);
    final mode = ref.watch(playModeProvider);
    final favorites = ref.watch(favoritesProvider);
    final lyricAsync = ref.watch(currentLyricProvider);

    if (item == null) {
      return Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: 8,
                left: 8,
                child: IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
                  onPressed: () => context.pop(),
                ),
              ),
              const EmptyState(
                icon: Icons.play_circle_outline_rounded,
                title: '还没有正在播放的内容',
                message: '回到列表挑一首歌吧',
              ),
            ],
          ),
        ),
      );
    }

    final sliderValue = _seekValue ?? position.inMilliseconds / 1000.0;

    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      body: Stack(
        children: [
          // ── 背景：封面高斯模糊 ──
          _BlurredCover(url: item.coverUrl, dim: 1.0 - (_dragY / 600)),

          // ── 前景内容（可下滑） ──
          Transform.translate(
            offset: Offset(0, _dragY),
            child: SafeArea(
              child: Builder(builder: (context) {
                // 宽屏（内屏展开）时封面与控制居左、歌词居右，横向并排；
                // 窄屏 / 悬停态（上半屏宽度 < 600dp）保持上下堆叠。
                final screenSize = MediaQuery.sizeOf(context);
                final isWide =
                    screenSize.width >= Responsive.foldableBreakpoint;
                // 直板机 / 小屏：封面同时受可用宽高约束，避免纵向溢出
                final coverSide = Responsive.playerCoverSize(
                  width: screenSize.width,
                  height: screenSize.height,
                );

                final coverBlock = GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (d) => setState(() {
                    _dragY = (_dragY + d.delta.dy).clamp(0.0, 400.0);
                  }),
                  onVerticalDragEnd: (_) => _onDragEnd(),
                  child: Column(
                    children: [
                      _buildGrabHandle(),
                      _buildRotatingCover(item.coverUrl, isPlaying,
                          'cover_${item.bvid}', coverSide),
                      SizedBox(height: coverSide >= 220 ? 22 : 14),
                      _buildMetadata(item),
                      const SizedBox(height: 14),
                      const HiResToggle(),
                    ],
                  ),
                );

                final lyricBlock = LyricWidget(
                  lyricText: lyricAsync.valueOrNull,
                  position: position,
                  autoScroll: isPlaying,
                  noLyricSource: !item.isMusicTrack,
                );

                final progressBlock = _buildProgress(
                  handler,
                  sliderValue: sliderValue,
                  position: position,
                  duration: duration,
                );
                final mainBlock = _buildMainControls(handler, isPlaying);
                final extraBlock = _buildExtraControls(
                  context,
                  item,
                  mode,
                  favorites.contains(item.bvid),
                );
                // 底部控制区：半透明白色卡片覆盖（QQ 音乐风格）
                final controlCard = _buildControlCard(
                  progress: progressBlock,
                  main: mainBlock,
                  extra: extraBlock,
                );

                if (isWide) {
                  return Column(
                    children: [
                      _buildTopBar(handler, item),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: Responsive.playerWideColumnWidth(
                                  screenSize.width),
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Column(
                                  children: [
                                    coverBlock,
                                    const SizedBox(height: 12),
                                    controlCard,
                                  ],
                                ),
                              ),
                            ),
                            const VerticalDivider(
                                width: 1,
                                thickness: 1,
                                color: AppTheme.divider),
                            Expanded(
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(8, 8, 20, 20),
                                child: lyricBlock,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }

                return Column(
                  children: [
                    _buildTopBar(handler, item),
                    coverBlock,
                    Expanded(child: lyricBlock),
                    controlCard,
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  /// 底部控制卡片：白色半透 + 轻微毛玻璃，进度 / 主控制 / 辅助控制同属一个卡片
  Widget _buildControlCard({
    required Widget progress,
    required Widget main,
    required Widget extra,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: ClipRRect(
        borderRadius: AppTheme.borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.76),
              borderRadius: AppTheme.borderRadius,
              border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                progress,
                main,
                const SizedBox(height: 2),
                extra,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(DogSheepAudioHandler handler, PlayQueueItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
            onPressed: () => context.pop(),
          ),
          Expanded(
            child: Text(
              item.isMusicTrack ? '正在播放' : '视频音频',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.queue_music_rounded, size: 24),
            onPressed: () => context.push('/queue?from=player'),
          ),
        ],
      ),
    );
  }

  Widget _buildGrabHandle() {
    return Container(
      width: 44,
      height: 5,
      margin: const EdgeInsets.only(top: 4, bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.textSub.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }

  Widget _buildRotatingCover(
      String? url, bool isPlaying, String heroTag, double side) {
    // 内圈唱片略小于外框（原 260 / 230 比例）
    final disc = (side - 30).clamp(110.0, 230.0);
    return RepaintBoundary(
      child: SizedBox(
        width: side,
        height: side,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 外圈光晕
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.accent.withValues(alpha: 0.22),
                    blurRadius: 40,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
            Hero(
              tag: heroTag,
              flightShuttleBuilder: (_, __, ___, ____, _____) {
                return ClipOval(
                  child: SizedBox(
                    width: 100,
                    height: 100,
                    child: CoverImage(url: url, size: 100, radius: 0),
                  ),
                );
              },
              child: RotationTransition(
                turns: _spin,
                child: Container(
                  width: disc,
                  height: disc,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 6),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.16),
                        blurRadius: 28,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    switchInCurve: Curves.easeInOut,
                    switchOutCurve: Curves.easeInOut,
                    child: url == null || url.isEmpty
                        ? const ColoredBox(
                            key: ValueKey('no-cover'),
                            color: AppTheme.bgCard,
                            child: Icon(Icons.music_note,
                                size: 72, color: AppTheme.textSub),
                          )
                        : CachedNetworkImage(
                            key: ValueKey(url),
                            imageUrl: CoverImage.normalize(url)!,
                            fit: BoxFit.cover,
                            width: disc,
                            height: disc,
                            errorWidget: (_, __, ___) => const ColoredBox(
                              color: AppTheme.bgCard,
                              child: Icon(Icons.music_note,
                                  size: 72, color: AppTheme.textSub),
                            ),
                          ),
                  ),
                ),
              ),
            ),
            // 中心唱针点
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.accent, width: 3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetadata(PlayQueueItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.15),
                  end: Offset.zero,
                ).animate(anim),
                child: child,
              ),
            ),
            child: Text(
              item.title,
              key: ValueKey('title_${item.bvid}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          const SizedBox(height: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            child: Text(
              item.artist,
              key: ValueKey('artist_${item.bvid}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppTheme.textSub),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgress(
    DogSheepAudioHandler handler, {
    required double sliderValue,
    required Duration position,
    required Duration duration,
  }) {
    final max = duration.inMilliseconds / 1000.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              activeTrackColor: AppTheme.accent,
              inactiveTrackColor: const Color(0xFFDFE1E8),
              thumbColor: AppTheme.accent,
              overlayColor: AppTheme.accent.withValues(alpha: 0.15),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 13),
            ),
            child: Slider(
              value: sliderValue.clamp(0.0, max > 0 ? max : 1.0),
              max: max > 0 ? max : 1.0,
              onChanged: max > 0 ? (v) => setState(() => _seekValue = v) : null,
              onChangeEnd: max > 0
                  ? (v) {
                      handler.seek(Duration(milliseconds: (v * 1000).round()));
                      setState(() => _seekValue = null);
                    }
                  : null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                    formatTime(_seekValue != null
                        ? Duration(milliseconds: (_seekValue! * 1000).round())
                        : position),
                    style:
                        const TextStyle(fontSize: 11, color: AppTheme.textSub)),
                Text(formatTime(duration),
                    style:
                        const TextStyle(fontSize: 11, color: AppTheme.textSub)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainControls(DogSheepAudioHandler handler, bool isPlaying) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          iconSize: 40,
          color: AppTheme.textMain,
          onPressed: handler.skipToPrevious,
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppTheme.accent,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppTheme.accent.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: IconButton(
            iconSize: 42,
            color: Colors.white,
            // 实时 playing 判定在 handler 内部，UI 不缓存状态
            onPressed: handler.togglePlayPause,
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, anim) => ScaleTransition(
                scale: Tween<double>(begin: 0.75, end: 1.0).animate(anim),
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                key: ValueKey(isPlaying),
              ),
            ),
          ),
        ),
        IconButton(
          iconSize: 40,
          color: AppTheme.textMain,
          onPressed: handler.skipToNext,
          icon: const Icon(Icons.skip_next_rounded),
        ),
      ],
    );
  }

  Widget _buildExtraControls(
    BuildContext context,
    PlayQueueItem item,
    PlayMode mode,
    bool isFav,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            tooltip: _modeLabel(mode),
            onPressed: () {
              ref.read(playModeProvider.notifier).cycle();
              final next = ref.read(playModeProvider);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_modeLabel(next)),
                  duration: const Duration(milliseconds: 1200),
                  behavior: SnackBarBehavior.floating,
                  margin: const EdgeInsets.all(16),
                ),
              );
            },
            icon: Icon(_modeIcon(mode),
                color: mode == PlayMode.sequence
                    ? AppTheme.textSub
                    : AppTheme.accent),
          ),
          IconButton(
            tooltip: isFav ? '取消收藏' : '收藏',
            onPressed: () async {
              final added =
                  await ref.read(favoritesProvider.notifier).toggle(item);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(added ? '已加入收藏' : '已取消收藏'),
                    duration: const Duration(milliseconds: 1100),
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.all(16),
                  ),
                );
              }
            },
            icon: Icon(
              isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: isFav ? AppTheme.accent : AppTheme.textSub,
            ),
          ),
          IconButton(
            tooltip: '播放列表',
            onPressed: () => context.push('/queue?from=player'),
            icon: const Icon(Icons.dehaze_rounded, color: AppTheme.textSub),
          ),
        ],
      ),
    );
  }

  void _onDragEnd() {
    if (_dragY > 120) {
      context.pop();
    } else {
      setState(() => _dragY = 0);
    }
  }
}

/// 封面高斯模糊背景层
class _BlurredCover extends StatelessWidget {
  final String? url;
  final double dim;

  const _BlurredCover({required this.url, required this.dim});

  @override
  Widget build(BuildContext context) {
    final normalized = CoverImage.normalize(url);
    Widget base;
    if (normalized == null) {
      base = const ColoredBox(color: AppTheme.bgPrimary);
    } else {
      base = CachedNetworkImage(
        imageUrl: normalized,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorWidget: (_, __, ___) =>
            const ColoredBox(color: AppTheme.bgPrimary),
      );
    }
    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 42, sigmaY: 42),
            child: Transform.scale(scale: 1.2, child: base),
          ),
          // 压暗，保证前景可读
          ColoredBox(
            color: AppTheme.bgPrimary
                .withValues(alpha: (0.72 + (1 - dim) * 0.25).clamp(0.0, 1.0)),
          ),
        ],
      ),
    );
  }
}
