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
import 'package:dog_sheep_player/shared/favorites.dart';
import 'package:dog_sheep_player/shared/responsive.dart';
import 'package:dog_sheep_player/shared/utils.dart';

/// 折叠屏展开态（>= 600dp）右侧常驻播放器面板。
///
/// 紧凑版播放 UI：封面 + 曲名/艺术家 + 进度 + 主控制 + Hi-Res 开关，
/// 空间足够时（面板高度充裕）附带滚动歌词。
/// 与 [MiniPlayer] 互斥：展开态由本面板常驻承载播放控制。
class PlayerPanel extends ConsumerStatefulWidget {
  const PlayerPanel({super.key});

  @override
  ConsumerState<PlayerPanel> createState() => _PlayerPanelState();
}

class _PlayerPanelState extends ConsumerState<PlayerPanel> {
  /// 本地 seek 值（秒）；null 表示跟随播放进度。
  double? _seekValue;

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

  @override
  Widget build(BuildContext context) {
    final handler = ref.read(audioHandlerProvider);
    final item = ref.watch(currentItemProvider).valueOrNull;
    final isPlaying = ref.watch(isPlayingProvider);
    final position = ref.watch(positionProvider).valueOrNull ?? Duration.zero;
    final duration = ref.watch(durationProvider).valueOrNull ??
        (item != null && item.duration > 0
            ? Duration(seconds: item.duration)
            : Duration.zero);
    final mode = ref.watch(playModeProvider);
    final favorites = ref.watch(favoritesProvider);
    final lyricAsync = ref.watch(currentLyricProvider);

    if (item == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.graphic_eq_rounded, size: 40, color: AppTheme.textSub),
              SizedBox(height: 12),
              Text('暂无播放内容',
                  style: TextStyle(color: AppTheme.textSub, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    final sliderValue = _seekValue ?? position.inMilliseconds / 1000.0;
    final max = duration.inMilliseconds / 1000.0;

    // 面板已从 300dp 收窄到 240~288dp：封面 / 内边距 / 控制按钮随实际宽度缩放，
    // 避免窄档下 5 个控制键横向溢出（RenderFlex overflow）。
    final panelWidth = Responsive.playerPanelWidthFor(
      Responsive.getScreenWidth(context),
    );
    final padX = panelWidth < 280 ? 12.0 : 16.0;
    final coverSize = (panelWidth - padX * 2 - 24).clamp(96.0, 160.0);
    final playSize = panelWidth < 280 ? 50.0 : 56.0;
    const ctlConstraints = BoxConstraints(minWidth: 40, minHeight: 40);

    return Container(
      // 右侧常驻面板：白底 + 左侧分割线
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(left: BorderSide(color: AppTheme.divider)),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(padX, 14, padX, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 封面 ──
              Center(
                child: CoverImage(
                  url: item.coverUrl,
                  size: coverSize,
                  radius: AppTheme.radius,
                ),
              ),
              const SizedBox(height: 14),

              // ── 曲名 / 艺术家 ──
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                item.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppTheme.textSub),
              ),
              const SizedBox(height: 12),

              // ── 进度条 ──
              SliderTheme(
                data: const SliderThemeData(
                  trackHeight: 3,
                  thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5),
                  overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
                ),
                child: Slider(
                  value: sliderValue.clamp(0.0, max > 0 ? max : 1.0),
                  max: max > 0 ? max : 1.0,
                  onChanged:
                      max > 0 ? (v) => setState(() => _seekValue = v) : null,
                  onChangeEnd: max > 0
                      ? (v) {
                          handler
                              .seek(Duration(milliseconds: (v * 1000).round()));
                          setState(() => _seekValue = null);
                        }
                      : null,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      formatTime(_seekValue != null
                          ? Duration(milliseconds: (_seekValue! * 1000).round())
                          : position),
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textSub),
                    ),
                    Text(formatTime(duration),
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.textSub)),
                  ],
                ),
              ),

              // ── 主控制 ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    tooltip: _modeLabel(mode),
                    constraints: ctlConstraints,
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        ref.read(playModeProvider.notifier).cycle(),
                    icon: Icon(_modeIcon(mode),
                        size: 22,
                        color: mode == PlayMode.sequence
                            ? AppTheme.textSub
                            : AppTheme.accent),
                  ),
                  IconButton(
                    iconSize: 28,
                    constraints: ctlConstraints,
                    visualDensity: VisualDensity.compact,
                    onPressed: handler.skipToPrevious,
                    icon: const Icon(Icons.skip_previous_rounded),
                  ),
                  Container(
                    width: playSize,
                    height: playSize,
                    decoration: const BoxDecoration(
                      color: AppTheme.accent,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: playSize * 0.58,
                      color: Colors.white,
                      // 播放/暂停交由 handler 以实时 playing 判定，UI 不缓存状态
                      onPressed: handler.togglePlayPause,
                      icon: Icon(isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded),
                    ),
                  ),
                  IconButton(
                    iconSize: 28,
                    constraints: ctlConstraints,
                    visualDensity: VisualDensity.compact,
                    onPressed: handler.skipToNext,
                    icon: const Icon(Icons.skip_next_rounded),
                  ),
                  IconButton(
                    tooltip: '播放列表',
                    constraints: ctlConstraints,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => context.push('/queue'),
                    icon: const Icon(Icons.queue_music_rounded,
                        size: 22, color: AppTheme.textSub),
                  ),
                ],
              ),

              // ── 收藏 ──
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: favorites.contains(item.bvid) ? '取消收藏' : '收藏',
                    constraints: ctlConstraints,
                    visualDensity: VisualDensity.compact,
                    onPressed: () async {
                      await ref.read(favoritesProvider.notifier).toggle(item);
                    },
                    icon: Icon(
                      favorites.contains(item.bvid)
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: favorites.contains(item.bvid)
                          ? AppTheme.accent
                          : AppTheme.textSub,
                    ),
                  ),
                  IconButton(
                    tooltip: '打开全屏播放器',
                    constraints: ctlConstraints,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => context.push('/player'),
                    icon: const Icon(Icons.fullscreen_rounded,
                        size: 22, color: AppTheme.textSub),
                  ),
                ],
              ),

              const SizedBox(height: 4),
              const Center(child: HiResToggle()),
              const SizedBox(height: 8),
              const Divider(height: 1),

              // ── 歌词（占剩余空间）──
              Expanded(
                child: LyricWidget(
                  lyricText: lyricAsync.valueOrNull,
                  position: position,
                  autoScroll: isPlaying,
                  noLyricSource: !item.isMusicTrack,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
}
