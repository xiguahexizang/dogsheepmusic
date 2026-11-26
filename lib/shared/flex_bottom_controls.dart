import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dog_sheep_player/app/theme.dart';
import 'package:dog_sheep_player/core/providers.dart';
import 'package:dog_sheep_player/features/player/hi_res_toggle.dart';
import 'package:dog_sheep_player/features/player/player_provider.dart';
import 'package:dog_sheep_player/shared/cover_image.dart';
import 'package:dog_sheep_player/shared/utils.dart';

/// 悬停（半折）态下半屏的播放控制区。
///
/// 简化版播放器：曲名 + 进度 + 主控制 + Hi-Res 开关，
/// 高度约 200–250dp，恰好落在 Z Fold 悬停时下半屏。
/// 无播放内容时收缩为 0 高度。
class FlexBottomControls extends ConsumerStatefulWidget {
  const FlexBottomControls({super.key});

  @override
  ConsumerState<FlexBottomControls> createState() => _FlexBottomControlsState();
}

class _FlexBottomControlsState extends ConsumerState<FlexBottomControls> {
  double? _seekValue;

  @override
  Widget build(BuildContext context) {
    final handler = ref.read(audioHandlerProvider);
    final item = ref.watch(currentItemProvider).valueOrNull;
    if (item == null) return const SizedBox.shrink();

    final isPlaying = ref.watch(isPlayingProvider);
    final position = ref.watch(positionProvider).valueOrNull ?? Duration.zero;
    final duration = ref.watch(durationProvider).valueOrNull ??
        (item.duration > 0 ? Duration(seconds: item.duration) : Duration.zero);

    final sliderValue = _seekValue ?? position.inMilliseconds / 1000.0;
    final max = duration.inMilliseconds / 1000.0;

    return Material(
      // 悬停态下半屏：白底，顶部一条浅灰分隔线
      color: AppTheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Divider(height: 13, thickness: 1),

              // ── 曲目信息 ──
              Row(
                children: [
                  CoverImage(url: item.coverUrl, size: 40, radius: 8),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textMain,
                            )),
                        const SizedBox(height: 2),
                        Text(item.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, color: AppTheme.textSub)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const HiResToggle(),
                ],
              ),
              const SizedBox(height: 8),

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
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 34,
                    onPressed: handler.skipToPrevious,
                    icon: const Icon(Icons.skip_previous_rounded),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      color: AppTheme.accent,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      iconSize: 36,
                      color: Colors.white,
                      // 播放/暂停交由 handler 以实时 playing 判定，UI 不缓存状态
                      onPressed: handler.togglePlayPause,
                      icon: Icon(isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    iconSize: 34,
                    onPressed: handler.skipToNext,
                    icon: const Icon(Icons.skip_next_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
