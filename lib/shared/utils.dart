/// 通用工具函数与播放快捷方法
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dog_sheep_player/core/audio/audio_handler.dart';
import 'package:dog_sheep_player/core/bili_api/music.dart';
import 'package:dog_sheep_player/features/player/player_provider.dart';

/// 将秒数格式化为 `mm:ss`（超过一小时则 `h:mm:ss`）
String formatDuration(int seconds) {
  if (seconds <= 0) return '00:00';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  if (h > 0) return '$h:${two(m)}:${two(s)}';
  return '${two(m)}:${two(s)}';
}

/// 将 [Duration] 格式化为 `mm:ss`
String formatTime(Duration d) => formatDuration(d.inSeconds);

/// 把一组 [MusicTrack] 转换为播放队列条目
List<PlayQueueItem> tracksToQueue(
  List<MusicTrack> tracks, {
  bool isMusic = true,
}) {
  return tracks
      .map((t) => PlayQueueItem.fromMusicTrack(t, isMusicTrack: isMusic))
      .toList();
}

/// 以 [tracks] 作为整个播放列表，从 [startIndex] 开始播放。
///
/// 内部委托给 [PlayQueueNotifier.play]，播放器会自动提取音频直链。
Future<void> playTrackList(
  WidgetRef ref,
  List<MusicTrack> tracks,
  int startIndex, {
  bool isMusic = true,
}) async {
  if (tracks.isEmpty) return;
  final items = tracksToQueue(tracks, isMusic: isMusic);
  final idx = startIndex.clamp(0, items.length - 1);
  await ref.read(playQueueProvider.notifier).play(items, startIndex: idx);
}

/// 将单个曲目追加到当前队列并立即播放。
///
/// 队列为空时直接作为唯一起点播放。
Future<void> playSingleTrack(
  WidgetRef ref,
  MusicTrack track, {
  bool isMusic = true,
}) async {
  final notifier = ref.read(playQueueProvider.notifier);
  final queue = ref.read(playQueueProvider);
  final item = PlayQueueItem.fromMusicTrack(track, isMusicTrack: isMusic);
  final existing =
      queue.indexWhere((e) => e.bvid == item.bvid && e.cid == item.cid);
  if (existing >= 0) {
    await notifier.playIndex(existing);
    return;
  }
  if (queue.isEmpty) {
    await notifier.play([item]);
  } else {
    await notifier.addAll([item]);
    // 新条目追加在队尾，其索引即追加前的队列长度
    await notifier.playIndex(queue.length);
  }
}
