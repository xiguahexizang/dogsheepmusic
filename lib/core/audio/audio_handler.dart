/// 音频播放处理器（基于 just_audio + audio_service）
///
/// 职责：
/// - 从 Bilibili 音频流接口提取直链，注入 Referer / Cookie 请求头后播放
/// - 维护播放队列，支持顺序 / 单曲循环 / 随机播放
/// - 将 just_audio 事件流映射到 audio_service 的 PlaybackState / MediaItem
/// - Hi-Res 开关变更时无缝切换音质（保留播放进度）
library;

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart' show PlatformException;
import 'package:just_audio/just_audio.dart' as ja;

import 'package:dog_sheep_player/core/bili_api/music.dart';
import 'package:dog_sheep_player/core/bili_api/video.dart';
import 'package:dog_sheep_player/core/web_proxy.dart';

// ─── 播放模式 ───────────────────────────────────────────────────────────────

/// 播放模式
enum PlayMode {
  /// 列表顺序播放（播完停止或到下一首）
  sequence,

  /// 单曲循环
  loopOne,

  /// 随机播放
  shuffle,
}

// ─── 队列条目 ───────────────────────────────────────────────────────────────

/// 播放队列条目
///
/// 统一封装视频区与音乐区条目，[isMusicTrack] 标识来源，
/// [cid] 为 0 时由 [BiliVideo.getAudioStream] 自动解析首个分 P。
class PlayQueueItem {
  /// BV 号
  final String bvid;

  /// 分 P cid（0 表示自动取首 P）
  final int cid;

  /// 标题
  final String title;

  /// 艺术家 / UP 主
  final String artist;

  /// 封面 URL
  final String? coverUrl;

  /// 歌词（LRC，可能为空）
  final String? lyric;

  /// 时长（秒，0 表示未知）
  final int duration;

  /// true=音乐区条目，false=视频区条目
  final bool isMusicTrack;

  const PlayQueueItem({
    required this.bvid,
    this.cid = 0,
    required this.title,
    required this.artist,
    this.coverUrl,
    this.lyric,
    this.duration = 0,
    this.isMusicTrack = false,
  });

  /// 从 [MusicTrack] 构造队列条目
  factory PlayQueueItem.fromMusicTrack(
    MusicTrack track, {
    int cid = 0,
    bool isMusicTrack = true,
  }) {
    return PlayQueueItem(
      bvid: track.bvid,
      cid: cid,
      title: track.title,
      artist: track.artist,
      coverUrl: track.cover.isNotEmpty ? track.cover : null,
      lyric: track.lyric,
      duration: track.duration,
      isMusicTrack: isMusicTrack,
    );
  }

  /// 从 [VideoMeta] 构造队列条目
  factory PlayQueueItem.fromVideoMeta(
    VideoMeta meta, {
    int cid = 0,
  }) {
    return PlayQueueItem(
      bvid: meta.bvid,
      cid: cid != 0 ? cid : (meta.pages.isNotEmpty ? meta.pages.first.cid : 0),
      title: meta.title,
      artist: meta.uploaderName,
      coverUrl: meta.thumbnailUrl.isNotEmpty ? meta.thumbnailUrl : null,
      lyric: meta.lyric,
      duration: meta.duration,
      isMusicTrack: false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PlayQueueItem && other.bvid == bvid && other.cid == cid;

  @override
  int get hashCode => Object.hash(bvid, cid);
}

// ─── 音频处理器 ─────────────────────────────────────────────────────────────

/// DogSheep 音频播放处理器
///
/// 绑定 just_audio 播放器与 Bilibili 音频流接口，向 audio_service 暴露标准
/// 播放控制接口，并支持队列管理、音质无缝切换与预加载。
class DogSheepAudioHandler extends BaseAudioHandler
    with SeekHandler, QueueHandler {
  /// 底层 just_audio 播放器
  final ja.AudioPlayer _player = ja.AudioPlayer();

  final BiliVideo _biliVideo;
  final BiliMusic _biliMusic;

  /// Cookie 提供者（返回当前 Bilibili Cookie Map，用于音频请求头）
  final Map<String, String>? Function() _cookiesProvider;

  DogSheepAudioHandler({
    required BiliVideo biliVideo,
    required BiliMusic biliMusic,
    required Map<String, String>? Function() cookiesProvider,
  })  : _biliVideo = biliVideo,
        _biliMusic = biliMusic,
        _cookiesProvider = cookiesProvider;

  // ─── 内部状态 ──────────────────────────────────────────────────────────

  /// 当前播放队列
  final List<PlayQueueItem> _queue = <PlayQueueItem>[];

  /// 当前播放索引（-1 表示无）
  int _currentIndex = -1;

  /// 播放模式
  ///
  /// 默认**随机**：首页为“Hi-Res 音乐随机推荐”，播完自动随机下一首
  /// （用户诉求：“播放完自动下一首，就随机推荐就行”）。
  PlayMode _playMode = PlayMode.shuffle;

  /// Hi-Res 开关（由外部 provider 同步）
  bool _hiResEnabled = true;

  /// 当前曲目实际可用的最高音质 id（0 表示未知 / 无）
  int _currentTrackMaxQualityId = 0;

  /// 音质可用性变更广播（供 UI 响应式判断 Hi-Res 是否可用）
  final StreamController<int> _qualityResolved =
      StreamController<int>.broadcast();

  /// 当前正在播放条目的 bvid / cid（用于音质切换）
  String? _currentBvid;
  int _currentCid = 0;

  /// 随机播放顺序（洗牌后的索引序列）
  List<int> _shuffleOrder = const [];

  /// 随机序列中的游标
  int _shuffleCursor = -1;

  /// 流订阅集合
  final List<StreamSubscription<dynamic>> _subs = [];

  /// 事件流订阅（出错后需要重建，单独持有）
  StreamSubscription<ja.PlaybackEvent>? _eventSub;

  /// 事件流重建定时器与连续失败计数
  Timer? _eventResubTimer;
  int _eventResubAttempts = 0;

  /// 是否已释放
  bool _disposed = false;

  /// 音质切换并发保护
  bool _switching = false;

  /// 播放/暂停切换重入保护（防快速连点把指令打乱）
  bool _toggling = false;

  /// play 指令看门狗。
  ///
  /// just_audio 的 `play()` 会先乐观地把 `playing` 置 true，若随后
  /// audio session 激活失败（`audioSession.setActive(true)` 返回 false）
  /// 又**静默复位**为 false，平台侧从未收到 play 请求。表现为「点播放
  /// 没声音、图标也不变」，故需要一个主动校验与重试。
  Timer? _playWatchdog;

  /// 上一次广播的 playing / processingState（仅在跃迁时打诊断日志）
  bool? _lastPubPlaying;
  AudioProcessingState? _lastPubState;

  /// 最近一次播放器异常（映射到 PlaybackState.error）
  PlatformException? _lastError;

  /// 正在重试的 bvid（防止无限重试）
  final Set<String> _retryingBvids = {};

  /// 随机播放队列自动续源回调（由首页随机推荐接线）
  ///
  /// 洗牌走完一轮时被调用，返回的曲目会去重后追加到队尾，
  /// 使「随机推荐」不会在队列尽头断掉。返回空列表即不追加。
  Future<List<PlayQueueItem>> Function()? queueRefill;

  /// 续源防重入标志
  bool _refilling = false;

  /// 自动续源后的队列长度上限（避免长时间播放后队列无限膨胀）
  static const int _maxAutoQueueLength = 120;

  // ─── 对外只读流（供 provider 监听）─────────────────────────────────────

  /// 播放进度流
  Stream<Duration> get positionStream => _player.positionStream;

  /// 总时长流
  Stream<Duration?> get durationStream => _player.durationStream;

  /// 缓冲进度流
  Stream<Duration> get bufferedPositionStream => _player.bufferedPositionStream;

  /// 当前队列快照
  ///
  /// 注意：不能命名为 `queue`，会与 [BaseAudioHandler.queue]
  /// （BehaviorSubject<List<MediaItem>>）冲突。
  List<PlayQueueItem> get queueSnapshot => List.unmodifiable(_queue);

  /// 当前播放索引
  int get currentIndex => _currentIndex;

  /// 当前播放条目
  PlayQueueItem? get currentItem =>
      (_currentIndex >= 0 && _currentIndex < _queue.length)
          ? _queue[_currentIndex]
          : null;

  /// 当前播放模式
  PlayMode get playMode => _playMode;

  /// 当前是否播放中（just_audio 实时值，优先于任何缓存快照）
  bool get isPlaying => _player.playing;

  /// playing 变化流（独立于事件流，不会被播放器异常污染）
  Stream<bool> get playingStream => _player.playingStream;

  /// 当前 MediaItem 流
  Stream<MediaItem?> get currentItemStream => mediaItem;

  // ─── 初始化 ─────────────────────────────────────────────────────────────

  /// 绑定 just_audio 事件流到 audio_service，并注册完成回调
  Future<void> init() async {
    // 1. 播放事件 → PlaybackState（含进度 / 缓冲 / 播放状态变化）
    _listenPlaybackEvents();

    // 2. playing 单独补一路广播。
    //    just_audio 的 `playerState` 是由 `playingStream` 与
    //    `playbackEventStream` 经 combineLatest **异步**合成的，而
    //    `playbackEventStream` 是 sync 的 BehaviorSubject：在它的回调里
    //    读 `playerState.playing` 拿到的一定是上一帧的旧值（暂停后按钮
    //    仍显示「播放中」、再点又发一次 pause 的根因）。事件流此后不再
    //    产生新事件，UI 便永久停在错误状态，故必须监听 playingStream。
    _subs.add(
      _player.playingStream.listen(
        (_) => _publishState(),
        onError: (Object e, StackTrace s) =>
            debugPrint('[audio] playingStream error: $e'),
      ),
    );

    // 3. 播放状态 → 队列自动前进 / 单曲循环
    _subs.add(
      _player.playerStateStream.listen((state) {
        if (state.processingState == ja.ProcessingState.completed) {
          _onTrackCompleted();
        }
      }),
    );

    // 4. 播放器异常的处理已并入 playbackEventStream 的 onError 通道
    //（just_audio 未提供 errorStream，异常经事件流传播）

    // 5. 立即推送一次初始状态
    _publishState();

    // 初始化时按当前模式设置 loopMode
    _applyLoopMode();
  }

  /// 订阅 just_audio 事件流；出错后自动重建订阅
  ///
  /// just_audio 会把播放器异常投递到内部事件 subject（addError），错误一旦
  /// 送达，当前订阅即终止。若不重建，之后所有状态变化（含暂停/恢复）都不
  /// 再进入 [_publishState]，UI 表现为「按钮再也不更新」。
  void _listenPlaybackEvents() {
    unawaited(_eventSub?.cancel());
    _eventSub = _player.playbackEventStream.listen(
      (_) {
        _eventResubAttempts = 0;
        _publishState();
      },
      onError: (Object e, StackTrace s) {
        // 不中断流程，转入错误处理
        if (e is ja.PlayerException) {
          _handlePlayerError(e);
        } else {
          debugPrint('[audio] playbackEvent error: $e');
        }
        _publishState();
        _scheduleEventResubscribe();
      },
    );
  }

  /// 延迟重建事件订阅（错误状态会被后续正常事件覆盖，重试几次即可自愈）
  void _scheduleEventResubscribe() {
    if (_disposed || _eventResubTimer != null || _eventResubAttempts >= 5) {
      return;
    }
    _eventResubAttempts++;
    _eventResubTimer = Timer(const Duration(milliseconds: 500), () {
      _eventResubTimer = null;
      if (_disposed) return;
      _listenPlaybackEvents();
      _publishState();
    });
  }

  /// 处理 just_audio 播放器异常：记录错误、自动重试或跳曲
  void _handlePlayerError(ja.PlayerException e) {
    _lastError = PlatformException(
      code: e.code.toString(),
      message: e.message,
      details: e.details.isNotEmpty ? e.details : null,
    );
    _publishState();

    // 自动重试逻辑：403 / 网络错误 → 刷新 Cookie 后重试当前曲目
    final errStr = '${e.code} ${e.message}';
    final isRetryable = errStr.contains('403') ||
        errStr.contains('401') ||
        errStr.contains('Network') ||
        errStr.contains('network');
    if (isRetryable &&
        _currentBvid != null &&
        !_retryingBvids.contains(_currentBvid)) {
      _retryingBvids.add(_currentBvid!);
      // 等待一小段，让 AuthInterceptor 完成重登，然后重试
      unawaited(
        Future.delayed(const Duration(milliseconds: 1200), () async {
          if (_currentBvid != null) {
            await _playIndex(_currentIndex, allowRetry: false);
            _retryingBvids.remove(_currentBvid);
          }
        }),
      );
    } else if (!isRetryable && _currentBvid != null) {
      // 不可重试（404等）：跳过该曲目
      _retryingBvids.remove(_currentBvid);
      final next = _nextIndex();
      if (next != null) unawaited(_playIndex(next));
    }
  }

  // ─── Hi-Res 开关 ───────────────────────────────────────────────────────

  /// Hi-Res 开关设置器
  ///
  /// 若当前正在播放，则无缝切换音质并保持当前进度。
  set hiResEnabled(bool value) {
    if (_hiResEnabled == value) return;
    _hiResEnabled = value;
    if (_player.playing && _currentBvid != null) {
      // fire-and-forget，异常在内部处理
      unawaited(_switchQuality());
    }
  }

  bool get hiResEnabled => _hiResEnabled;

  /// 当前曲目实际可用的最高音质 id（>= 30251 表示存在 Hi-Res 轨）
  int get currentTrackMaxQualityId => _currentTrackMaxQualityId;

  /// 音质可用性变更流（广播），当前曲目解析完成后推送最高可用 qualityId
  Stream<int> get qualityResolvedStream => _qualityResolved.stream;

  /// 更新并广播当前曲目的最高可用音质
  void _updateMaxQuality(int maxQualityId) {
    if (_currentTrackMaxQualityId == maxQualityId) return;
    _currentTrackMaxQualityId = maxQualityId;
    if (!_qualityResolved.isClosed) _qualityResolved.add(maxQualityId);
  }

  /// 播放模式设置器
  set playMode(PlayMode mode) {
    if (_playMode == mode) return;
    _playMode = mode;
    if (mode == PlayMode.shuffle) {
      _buildShuffleOrder();
    }
    _applyLoopMode();
  }

  // ─── 队列管理 ───────────────────────────────────────────────────────────

  /// 设置播放队列（不自动播放），并同步到系统队列
  ///
  /// 注意：不能命名为 `updateQueue`，会与 [QueueHandler.updateQueue]
  /// （List<MediaItem> 参数）签名冲突。
  Future<void> updatePlayQueue(List<PlayQueueItem> items) async {
    _queue
      ..clear()
      ..addAll(items);
    _currentIndex = items.isEmpty ? -1 : 0;
    if (_playMode == PlayMode.shuffle) {
      _buildShuffleOrder();
    }
    queue.add(_queue.map(_toMediaItem).toList());
  }

  /// 追加曲目到队列末尾，返回第一个新增条目的索引
  Future<int> addAll(List<PlayQueueItem> items) async {
    final startIndex = _queue.length;
    _queue.addAll(items);
    queue.add(_queue.map(_toMediaItem).toList());
    return startIndex;
  }

  /// 在当前曲目之后插入下一首
  Future<void> addNext(PlayQueueItem item) async {
    final insertAt =
        _currentIndex < 0 ? 0 : (_currentIndex + 1).clamp(0, _queue.length);
    _queue.insert(insertAt, item);
    queue.add(_queue.map(_toMediaItem).toList());
  }

  /// 从队列移除指定索引曲目
  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= _queue.length) return;
    final wasCurrent = index == _currentIndex;
    _queue.removeAt(index);
    if (index < _currentIndex) {
      _currentIndex--;
    }
    queue.add(_queue.map(_toMediaItem).toList());
    // 移除的是当前播放项：自动播放下一首
    if (wasCurrent) {
      if (_queue.isEmpty) {
        await stop();
      } else {
        await _playIndex(_currentIndex.clamp(0, _queue.length - 1));
      }
    }
  }

  /// 队列重排
  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex < 0 ||
        oldIndex >= _queue.length ||
        newIndex < 0 ||
        newIndex >= _queue.length) {
      return;
    }
    final playing = _currentIndex >= 0 ? _queue[_currentIndex] : null;
    final item = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, item);
    // 重算当前播放项索引
    _currentIndex = playing != null ? _queue.indexOf(playing) : -1;
    queue.add(_queue.map(_toMediaItem).toList());
  }

  /// 清空队列并停止
  Future<void> clearQueue() async {
    await stop();
    _queue.clear();
    _currentIndex = -1;
    queue.add(const <MediaItem>[]);
  }

  /// 停止播放
  @override
  Future<void> stop() async {
    _currentIndex = -1;
    _playWatchdog?.cancel();
    _playWatchdog = null;
    await _player.stop();
  }

  // ─── 播放控制 ───────────────────────────────────────────────────────────

  /// 恢复播放当前曲目
  ///
  /// 注意：just_audio 的 `play()` 返回的 Future 要等到「播完 / 被暂停 /
  /// 被停止」才完成，直接把这种 Future 交给上层 await 会把调用方（包括
  /// audio_service 的平台回调与队列通知器）挂起整首歌，因此这里发出
  /// 播放指令后即返回；错误经事件流投递到 [_handlePlayerError]。
  ///
  /// 无音频源（idle / 已播完 / stop 后）时自动重走提取流程，
  /// 保证通知栏与锁屏的播放键在冷启动后也能生效。
  @override
  Future<void> play() async {
    final processing = _player.processingState;
    final needsReload = _currentBvid == null ||
        processing == ja.ProcessingState.idle ||
        processing == ja.ProcessingState.completed;
    if (needsReload) {
      if (_queue.isEmpty) return;
      await _playIndex(_currentIndex >= 0 ? _currentIndex : 0);
      return;
    }
    _kickPlay();
  }

  /// 暂停
  @override
  Future<void> pause() async {
    _playWatchdog?.cancel();
    _playWatchdog = null;
    await _player.pause();
    // pause() 已同步更新 `_player.playing`，这里立即广播，
    // 不等事件流，避免按钮响应延迟
    _publishState();
    // playingSubject 是异步 BehaviorSubject，紧随其后的平台事件可能再补
    // 一帧；用微任务再对齐一次，杜绝「按钮停在旧态」。
    scheduleMicrotask(_publishState);
  }

  /// 播放/暂停切换（UI 唯一入口）
  ///
  /// 判定使用 just_audio 的**实时** `playing`，而不是任何缓存的
  /// PlaybackState 快照，避免状态广播链任一环节出错时按钮与音频错位。
  /// 带重入保护，快速连点不会把 play/pause 序列打乱。
  Future<void> togglePlayPause() async {
    if (_toggling) {
      debugPrint('[audio] toggle ignored (重入保护)，当前 playing=${_player.playing}');
      return;
    }
    final live = _player.playing;
    // 诊断日志：同时打印三个状态源，便于定位「UI / 广播 / 内核」不一致
    debugPrint('[audio] toggle: kernel.playing=$live '
        'broadcast.playing=${playbackState.valueOrNull?.playing} '
        'kernel.processing=${_player.processingState} idx=$_currentIndex');
    _toggling = true;
    try {
      if (live) {
        await pause();
      } else {
        await play();
      }
    } finally {
      _toggling = false;
      debugPrint('[audio] toggle done: kernel.playing=${_player.playing} '
          'broadcast.playing=${playbackState.valueOrNull?.playing}');
    }
  }

  /// 发起播放且不阻塞（错误同时会经 playbackEventStream 进入重试/跳曲）
  void _kickPlay() {
    unawaited(
      _player.play().catchError((Object e, StackTrace st) {
        debugPrint('[audio] play() failed: $e');
      }),
    );
    // 下发指令后补一次广播，使 UI 无需等待平台事件即可翻转图标
    _publishState();
    _armPlayWatchdog();
  }

  /// 校验 play 指令真的落地；被静默作废时重试
  ///
  /// 只看 `playing` 是否还在（缓冲中的曲目 position 不动属正常，
  /// 不能据此误判），避免打断正常 buffering。
  void _armPlayWatchdog() {
    _playWatchdog?.cancel();
    _playWatchdog = Timer(const Duration(milliseconds: 1200), () {
      _playWatchdog = null;
      if (_disposed || _player.playing) return;
      debugPrint('[audio] watchdog: play 指令被静默作废，重试一次');
      unawaited(_player.play().catchError((Object e, StackTrace st) {
        debugPrint('[audio] watchdog retry play failed: $e');
      }));
      _publishState();
    });
  }

  /// 跳转到指定进度（SeekHandler 提供接口，此处绑定 just_audio）
  @override
  Future<void> seek(Duration position) => _player.seek(position);

  /// 直接播放给定音频直链（跳过提取）
  Future<void> playUrl(String url, MediaItem item) async {
    final source = _buildAudioSource(url);
    await _player.setAudioSource(source);
    mediaItem.add(item);
    _kickPlay();
  }

  /// 播放队列中指定索引的条目
  Future<void> playIndex(int index) async {
    await _playIndex(index);
  }

  /// 设置队列并从指定索引开始播放
  Future<void> playQueue(List<PlayQueueItem> items,
      {int startIndex = 0}) async {
    await updatePlayQueue(items);
    if (items.isEmpty) return;
    final idx = startIndex.clamp(0, items.length - 1);
    await _playIndex(idx);
  }

  Future<void> _playIndex(int index, {bool allowRetry = true}) async {
    if (index < 0 || index >= _queue.length) return;
    final item = _queue[index];
    _currentIndex = index;
    _currentBvid = item.bvid;
    _currentCid = item.cid;

    // 更新通知栏 MediaItem
    mediaItem.add(_toMediaItem(item));

    // 新曲目开始提取：清除上一曲遗留的错误并广播 loading 状态
    _lastError = null;
    _publishState(announcingNewTrack: true);

    // 切歌时先重置可用音质，避免沿用上一曲目状态
    _updateMaxQuality(0);

    // 优先使用预加载结果，否则重新提取
    final preloaded = _preloaded.remove(index);
    final preloadedMax = _preloadedMaxQuality.remove(index);
    AudioStreamInfo? stream;
    try {
      if (preloaded != null) {
        stream = preloaded;
        _updateMaxQuality(preloadedMax ?? 0);
      } else {
        stream = await _biliVideo.getAudioStream(
          item.bvid,
          cid: item.cid,
          hiResEnabled: _hiResEnabled,
          onAvailable: _updateMaxQuality,
        );
      }
    } catch (e) {
      // 提取音频流时网络错误：若允许重试，则等待后重试一次
      if (allowRetry && !_retryingBvids.contains(item.bvid)) {
        _retryingBvids.add(item.bvid);
        await Future.delayed(const Duration(milliseconds: 1500));
        _retryingBvids.remove(item.bvid);
        return _playIndex(index, allowRetry: false);
      }
      stream = null;
    }

    if (stream == null) {
      // 无法获取音频流：若允许重试且尚未重试，则等待 AuthInterceptor 重登后重试
      if (allowRetry && !_retryingBvids.contains(item.bvid)) {
        _retryingBvids.add(item.bvid);
        await Future.delayed(const Duration(milliseconds: 2000));
        _retryingBvids.remove(item.bvid);
        return _playIndex(index, allowRetry: false);
      }
      // 重试仍失败：跳过该曲目
      final next = _nextIndex();
      if (next != null && next != index) {
        unawaited(_playIndex(next, allowRetry: false));
      } else {
        _publishState();
      }
      return;
    }

    final source = _buildAudioSource(stream.url);

    try {
      await _player.setAudioSource(source);
    } on ja.PlayerException catch (_) {
      // setAudioSource 失败：403 类错误 → 允许重试一次
      if (allowRetry && !_retryingBvids.contains(item.bvid)) {
        _retryingBvids.add(item.bvid);
        await Future.delayed(const Duration(milliseconds: 1500));
        _retryingBvids.remove(item.bvid);
        return _playIndex(index, allowRetry: false);
      }
      // 重试仍失败：跳过
      final next = _nextIndex();
      if (next != null && next != index) {
        unawaited(_playIndex(next, allowRetry: false));
      }
      return;
    }

    // 不等 play() 完成（它要等到本曲结束/暂停），否则本方法会挂起到
    // 歌曲结束，队列通知器 state 与预加载全部延迟
    _kickPlay();

    // 预加载下一首，降低切歌卡顿
    unawaited(_preloadNext());
  }

  // ─── 切歌 ──────────────────────────────────────────────────────────────

  /// 下一首
  @override
  Future<void> skipToNext({Duration? offset}) async {
    final next = _nextIndex();
    if (next != null) await _playIndex(next);
  }

  /// 上一首
  @override
  Future<void> skipToPrevious({Duration? offset}) async {
    final prev = _previousIndex();
    if (prev != null) await _playIndex(prev);
  }

  /// 跳到队列中指定 MediaItem
  @override
  Future<void> skipToQueueItem(int id) async {
    // 队列 MediaItem 的 id 使用 bvid，这里以索引作为 id 更便于系统调用
    await _playIndex(id);
  }

  int? _nextIndex() {
    if (_queue.isEmpty) return null;
    switch (_playMode) {
      case PlayMode.loopOne:
        // 单曲循环由 loopMode 处理，此分支通常不触发
        return _currentIndex;
      case PlayMode.shuffle:
        return _shuffleNext();
      case PlayMode.sequence:
        if (_currentIndex < _queue.length - 1) return _currentIndex + 1;
        return 0; // 循环到列表头
    }
  }

  int? _previousIndex() {
    if (_queue.isEmpty) return null;
    switch (_playMode) {
      case PlayMode.loopOne:
        return _currentIndex;
      case PlayMode.shuffle:
        return _shufflePrevious();
      case PlayMode.sequence:
        if (_currentIndex > 0) return _currentIndex - 1;
        return _queue.length - 1;
    }
  }

  /// 预览下一首索引（**不**推进随机游标）
  ///
  /// 仅供预加载使用：[_nextIndex] 在随机模式下会移动 `_shuffleCursor`，
  /// 预加载若复用它，真正切歌时会再推进一次而跳过一首。
  int? _peekNextIndex() {
    if (_queue.isEmpty) return null;
    switch (_playMode) {
      case PlayMode.loopOne:
        return _currentIndex;
      case PlayMode.shuffle:
        if (_shuffleOrder.isEmpty) _buildShuffleOrder();
        if (_shuffleCursor < _shuffleOrder.length - 1) {
          return _shuffleOrder[_shuffleCursor + 1];
        }
        return null;
      case PlayMode.sequence:
        return _currentIndex < _queue.length - 1 ? _currentIndex + 1 : 0;
    }
  }

  void _buildShuffleOrder() {
    final indices = List<int>.generate(_queue.length, (i) => i)..shuffle();
    _shuffleOrder = indices;
    // 将当前曲目置于随机序列首位
    if (_currentIndex >= 0) {
      _shuffleOrder.remove(_currentIndex);
      _shuffleOrder.insert(0, _currentIndex);
      _shuffleCursor = 0;
    } else {
      _shuffleCursor = -1;
    }
  }

  int? _shuffleNext() {
    if (_shuffleOrder.isEmpty) {
      _buildShuffleOrder();
    }
    if (_shuffleCursor < _shuffleOrder.length - 1) {
      _shuffleCursor++;
      return _shuffleOrder[_shuffleCursor];
    }
    // 重新洗牌
    _buildShuffleOrder();
    _shuffleCursor = 0;
    // 一轮走完 → 后台补充随机曲目，下一轮即可用到（不阻塞当前切歌）
    _maybeRefillQueue();
    return _shuffleOrder.isNotEmpty ? _shuffleOrder.first : null;
  }

  /// 触发队列续源（fire-and-forget，失败静默：仍有整轮可播）
  void _maybeRefillQueue() {
    final cb = queueRefill;
    if (cb == null || _refilling) return;
    if (_playMode != PlayMode.shuffle) return;
    if (_queue.length >= _maxAutoQueueLength) return;
    _refilling = true;
    unawaited(() async {
      try {
        final items = await cb();
        if (items.isEmpty) return;
        final existing = _queue.map((e) => e.bvid).toSet();
        final fresh = items.where((e) => !existing.contains(e.bvid)).toList();
        if (fresh.isEmpty) return;
        final room = _maxAutoQueueLength - _queue.length;
        await addAll(room < fresh.length ? fresh.sublist(0, room) : fresh);
      } catch (e) {
        debugPrint('[audio] queueRefill failed: $e');
      } finally {
        _refilling = false;
      }
    }());
  }

  int? _shufflePrevious() {
    if (_shuffleOrder.isEmpty) {
      _buildShuffleOrder();
    }
    if (_shuffleCursor > 0) {
      _shuffleCursor--;
      return _shuffleOrder[_shuffleCursor];
    }
    return _currentIndex;
  }

  void _onTrackCompleted() {
    if (_playMode == PlayMode.loopOne) {
      // loopMode 会自动处理，这里无需操作
      return;
    }
    final next = _nextIndex();
    if (next != null) {
      unawaited(_playIndex(next));
    }
  }

  void _applyLoopMode() {
    _player.setLoopMode(
      _playMode == PlayMode.loopOne ? ja.LoopMode.one : ja.LoopMode.off,
    );
  }

  // ─── 歌词 ──────────────────────────────────────────────────────────────

  /// 异步获取指定条目的歌词（LRC），并回写到队列条目
  ///
  /// 使用 [BiliMusic] 接口，供歌词面板按需加载。
  Future<String?> loadLyric(int index) async {
    if (index < 0 || index >= _queue.length) return null;
    final item = _queue[index];
    if (item.lyric != null && item.lyric!.isNotEmpty) return item.lyric;
    final lyric = await _biliMusic.getLyric(item.bvid, cid: item.cid);
    return lyric;
  }

  // ─── 音质切换 ──────────────────────────────────────────────────────────

  /// 无缝切换音质：记录进度 → 重新提取直链 → seek 回原进度 → 恢复播放
  Future<void> _switchQuality() async {
    if (_switching || _currentBvid == null) return;
    _switching = true;
    final position = _player.position;
    final wasPlaying = _player.playing;
    try {
      final stream = await _biliVideo.getAudioStream(
        _currentBvid!,
        cid: _currentCid,
        hiResEnabled: _hiResEnabled,
        onAvailable: _updateMaxQuality,
      );
      if (stream == null) return;

      final source = _buildAudioSource(stream.url);
      await _player.setAudioSource(source);
      await _player.seek(position);
      if (wasPlaying) {
        _kickPlay();
      } else {
        _publishState();
      }
    } on ja.PlayerException catch (_) {
      // 切换失败保持原有播放，不中断
    } finally {
      _switching = false;
    }
  }

  // ─── 预加载 ────────────────────────────────────────────────────────────

  /// 预加载下一首的音频直链（减少切歌等待）
  Future<void> _preloadNext() async {
    final next = _peekNextIndex();
    if (next == null || next >= _queue.length) return;
    final item = _queue[next];
    try {
      // 仅触发提取并丢弃结果，使 CDN 边缘节点预热；just_audio
      // 无原生 preload API，这里通过请求一次流头部信息预热连接。
      int maxQualityId = 0;
      final stream = await _biliVideo.getAudioStream(
        item.bvid,
        cid: item.cid,
        hiResEnabled: _hiResEnabled,
        onAvailable: (q) => maxQualityId = q,
      );
      // 保留最近一次的预加载 URL，切歌命中时可跳过重新提取
      if (stream != null) {
        _preloaded[next] = stream;
        _preloadedMaxQuality[next] = maxQualityId;
      }
    } catch (_) {
      // 预加载失败不影响主流程
    }
  }

  /// 预加载缓存：index → AudioStreamInfo
  final Map<int, AudioStreamInfo> _preloaded = {};

  /// 预加载曲目的最高可用音质：index → maxQualityId
  final Map<int, int> _preloadedMaxQuality = {};

  // ─── 请求头构建 ────────────────────────────────────────────────────────

  /// 构建音频请求头（Referer + Cookie + UA），Bilibili 直链强校验 Referer
  Map<String, String> _buildHeaders() {
    final cookies = _cookiesProvider() ?? const <String, String>{};
    final cookieStr = cookies.entries
        .where((e) => e.value.isNotEmpty)
        .map((e) => '${e.key}=${e.value}')
        .join('; ');
    return <String, String>{
      'Referer': 'https://www.bilibili.com',
      'Origin': 'https://www.bilibili.com',
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
      if (cookieStr.isNotEmpty) 'Cookie': cookieStr,
    };
  }

  /// 构建 just_audio 音源。
  ///
  /// - 原生端：注入 Referer / Origin / UA / Cookie（Bilibili 直链强校验 Referer）。
  /// - Web 端：`just_audio_web` 完全忽略 `headers`，且浏览器禁止 JS 设置这些头，
  ///   因此改为把音频直链重写为本地 dev proxy 地址（由代理补全 Referer/Cookie），
  ///   代理未启用时退回直链，避免传入不受支持的参数导致播放失败。
  ja.AudioSource _buildAudioSource(String url) {
    if (kIsWeb) {
      final proxied = WebProxy.rewriteUrl(url);
      return ja.AudioSource.uri(Uri.parse(proxied ?? url));
    }
    return ja.AudioSource.uri(Uri.parse(url), headers: _buildHeaders());
  }

  // ─── MediaItem / PlaybackState 映射 ─────────────────────────────────────

  MediaItem _toMediaItem(PlayQueueItem item) {
    return MediaItem(
      // 使用队列索引作为 id，便于 skipToQueueItem 反查
      id: item.bvid,
      title: item.title,
      artist: item.artist,
      album: item.isMusicTrack ? 'Bilibili 音乐' : 'Bilibili 视频',
      artUri: (item.coverUrl != null && item.coverUrl!.isNotEmpty)
          ? Uri.tryParse(item.coverUrl!)
          : null,
      duration: item.duration > 0 ? Duration(seconds: item.duration) : null,
      extras: {'cid': item.cid, 'isMusicTrack': item.isMusicTrack},
    );
  }

  /// 将 just_audio 当前状态映射为 audio_service 的 PlaybackState
  ///
  /// 关键：这里只读 `_player.playing` / `_player.processingState` 这类
  /// **同步生效**的实时值。`_player.playerState` 由 combineLatest 异步合成，
  /// 在 playbackEventStream（sync 流）回调里读到的是上一帧的 `playing`，
  /// 会造成「暂停后仍广播 playing: true → 按钮不变 → 再点又发 pause」。
  ///
  /// [announcingNewTrack] 为 true 时用于切歌起点：audio_service 会把
  /// 「非 idle → idle」的广播解释为需要自动调用 `handler.stop()`
  /// （见 AudioService._observePlaybackState），那会清掉刚设好的
  /// `_currentIndex`，因此起播瞬间的真实 idle 上报为 loading。
  void _publishState({bool announcingNewTrack = false}) {
    if (_disposed) return;
    final playing = _player.playing;
    var processing = _mapProcessingState(_player.processingState);
    if (announcingNewTrack && processing == AudioProcessingState.idle) {
      processing = AudioProcessingState.loading;
    }
    final controls = <MediaControl>[
      if (_hasPrevious) MediaControl.skipToPrevious,
      playing ? MediaControl.pause : MediaControl.play,
      if (_hasNext) MediaControl.skipToNext,
      MediaControl.stop,
    ];

    // androidCompactActionIndices 必须是 controls 内的合法下标且不超过 3 个：
    // 队首只有一首歌时 controls 只含 2 项，固定写 [0,1,2] 会让系统侧越界
    final compactIndices = <int>[
      for (var i = 0; i < controls.length && i < 3; i++) i,
    ];

    playbackState.add(
      PlaybackState(
        controls: controls,
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices:
            compactIndices.isEmpty ? null : compactIndices,
        processingState: processing,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _currentIndex < 0 ? 0 : _currentIndex,
        errorCode:
            _lastError != null ? int.tryParse(_lastError!.code) ?? 1 : null,
        errorMessage: _lastError?.message,
      ),
    );

    // 仅在状态跃迁时打日志，便于用 logcat 对齐「UI / 广播 / 内核」三者
    if (_lastPubPlaying != playing || _lastPubState != processing) {
      debugPrint('[audio] broadcast playing=$playing processing=$processing '
          '(kernel playing=${_player.playing} ${_player.processingState})');
      _lastPubPlaying = playing;
      _lastPubState = processing;
    }
  }

  AudioProcessingState _mapProcessingState(ja.ProcessingState state) {
    switch (state) {
      case ja.ProcessingState.idle:
        return AudioProcessingState.idle;
      case ja.ProcessingState.loading:
        return AudioProcessingState.loading;
      case ja.ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ja.ProcessingState.ready:
        return AudioProcessingState.ready;
      case ja.ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  bool get _hasPrevious =>
      _playMode == PlayMode.sequence ? _queue.isNotEmpty : _queue.length > 1;

  bool get _hasNext =>
      _playMode == PlayMode.sequence ? _queue.isNotEmpty : _queue.length > 1;

  // ─── 释放 ──────────────────────────────────────────────────────────────

  /// 释放播放器与订阅（应用退出时调用）
  Future<void> dispose() async {
    _disposed = true;
    _playWatchdog?.cancel();
    _playWatchdog = null;
    _eventResubTimer?.cancel();
    _eventResubTimer = null;
    await _eventSub?.cancel();
    _eventSub = null;
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _preloaded.clear();
    _preloadedMaxQuality.clear();
    await _qualityResolved.close();
    await _player.dispose();
  }
}
