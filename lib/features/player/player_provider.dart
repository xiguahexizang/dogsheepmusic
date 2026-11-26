/// 播放器状态管理 Provider
///
/// 将 [DogSheepAudioHandler] 的事件流与队列操作暴露为 Riverpod Provider，
/// 供播放页、迷你播放条、队列页等 UI 消费。
library;

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dog_sheep_player/core/audio/audio_handler.dart';
import 'package:dog_sheep_player/core/providers.dart';

// ─── 队列 ───────────────────────────────────────────────────────────────────

/// 播放队列 Notifier
///
/// 作为队列的 UI 侧数据源，所有变更同步委托给 [DogSheepAudioHandler]，
/// 保持播放器内部队列与 UI 展示一致。
class PlayQueueNotifier extends StateNotifier<List<PlayQueueItem>> {
  PlayQueueNotifier(this._handler) : super(List.of(_handler.queueSnapshot));

  final DogSheepAudioHandler _handler;

  /// 设置队列并从 [startIndex] 开始播放
  Future<void> play(List<PlayQueueItem> items, {int startIndex = 0}) async {
    await _handler.playQueue(items, startIndex: startIndex);
    state = List.of(items);
  }

  /// 仅设置队列，不自动播放
  Future<void> setQueue(List<PlayQueueItem> items) async {
    await _handler.updatePlayQueue(items);
    state = List.of(items);
  }

  /// 追加多个曲目到队列末尾
  Future<void> addAll(List<PlayQueueItem> items) async {
    await _handler.addAll(items);
    state = [...state, ...items];
  }

  /// 在当前曲目之后插入下一首
  Future<void> addNext(PlayQueueItem item) async {
    await _handler.addNext(item);
    final insertAt = (_handler.currentIndex + 1).clamp(0, state.length);
    state = [...state]..insert(insertAt, item);
  }

  /// 移除指定索引曲目
  Future<void> removeAt(int index) async {
    if (index < 0 || index >= state.length) return;
    await _handler.removeFromQueue(index);
    state = [...state]..removeAt(index);
  }

  /// 队列重排
  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < 0 ||
        oldIndex >= state.length ||
        newIndex < 0 ||
        newIndex >= state.length) {
      return;
    }
    await _handler.reorderQueue(oldIndex, newIndex);
    final copy = [...state];
    final item = copy.removeAt(oldIndex);
    copy.insert(newIndex, item);
    state = copy;
  }

  /// 清空队列并停止播放
  Future<void> clear() async {
    await _handler.clearQueue();
    state = const <PlayQueueItem>[];
  }

  /// 播放队列中指定索引
  Future<void> playIndex(int index) => _handler.playIndex(index);

  /// 下一首
  Future<void> next() => _handler.skipToNext();

  /// 上一首
  Future<void> previous() => _handler.skipToPrevious();
}

/// 播放队列 Provider
final playQueueProvider =
    StateNotifierProvider<PlayQueueNotifier, List<PlayQueueItem>>((ref) {
  return PlayQueueNotifier(ref.watch(audioHandlerProvider));
});

// ─── 播放模式 ───────────────────────────────────────────────────────────────

/// 播放模式 Notifier
///
/// 写入时同步更新 [DogSheepAudioHandler.playMode]，保证播放器行为与 UI 一致。
class PlayModeNotifier extends StateNotifier<PlayMode> {
  PlayModeNotifier(this._handler) : super(_handler.playMode);

  final DogSheepAudioHandler _handler;

  set mode(PlayMode value) {
    _handler.playMode = value;
    state = value;
  }

  /// 切换到下一个模式（顺序 → 单曲循环 → 随机 → 顺序）
  void cycle() {
    final PlayMode next;
    switch (state) {
      case PlayMode.sequence:
        next = PlayMode.loopOne;
        break;
      case PlayMode.loopOne:
        next = PlayMode.shuffle;
        break;
      case PlayMode.shuffle:
        next = PlayMode.sequence;
        break;
    }
    mode = next;
  }
}

/// 播放模式 Provider
final playModeProvider =
    StateNotifierProvider<PlayModeNotifier, PlayMode>((ref) {
  return PlayModeNotifier(ref.watch(audioHandlerProvider));
});

// ─── 当前播放项 ─────────────────────────────────────────────────────────────

/// 当前正在播放的队列条目
///
/// 随通知栏 MediaItem 更新而重新求值（MediaItem 触发时 handler 已更新索引）。
final currentItemProvider = StreamProvider<PlayQueueItem?>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return handler.currentItemStream.map((_) => handler.currentItem);
});

/// 当前播放条目的歌词
///
/// 依据当前条目索引异步加载（命中缓存优先）。
final currentLyricProvider = FutureProvider<String?>((ref) async {
  final handler = ref.watch(audioHandlerProvider);
  final item = ref.watch(currentItemProvider).valueOrNull;
  if (item == null) return null;
  if (item.lyric != null && item.lyric!.isNotEmpty) return item.lyric;
  return handler.loadLyric(handler.currentIndex);
});

// ─── 播放状态 ───────────────────────────────────────────────────────────────

/// 播放状态流（playing / paused / completed / idle ...）
final playbackStateProvider = StreamProvider<PlaybackState>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return handler.playbackState;
});

/// just_audio 的实时 playing 流
///
/// 与 [playbackStateProvider] 分开：`playingStream` 直接来自播放内核的
/// 状态源，不依赖事件广播链路，任一环出错（如播放器异常终止了事件
/// 订阅）时它仍然准确。
final playingStateProvider = StreamProvider<bool>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return handler.playingStream;
});

/// 是否正在播放（以播放内核实时值为准，PlaybackState 广播仅作兼底）
final isPlayingProvider = Provider<bool>((ref) {
  final live = ref.watch(playingStateProvider).valueOrNull;
  if (live != null) return live;
  return ref.watch(playbackStateProvider).valueOrNull?.playing ?? false;
});

/// 播放进度流
final positionProvider = StreamProvider<Duration>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return handler.positionStream;
});

/// 总时长流
final durationProvider = StreamProvider<Duration?>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return handler.durationStream;
});

/// 缓冲进度流
final bufferedPositionProvider = StreamProvider<Duration>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  return handler.bufferedPositionStream;
});
