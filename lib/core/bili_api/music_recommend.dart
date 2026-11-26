/// Hi-Res 音乐随机推荐（首页唯一内容源）
///
/// 设计动机（用户诉求：“首页推荐只有 hires 的音乐推荐，然后播放完自动下一首，
/// 就随机推荐就行”）：
///
/// * 全站推荐接口 `index/top/rcmd` 与 `popular` 返回的绝大多数是视频，
///   即便按 tid 过滤也只剩个位数，因此首页**不再使用这两个接口**，
///   改为纯音乐源组合：
///   - `x/web-interface/ranking/v2?rid=3`（音乐整区榜，实测 97 条全音乐）
///   - `x/web-interface/newlist?rid=3`（音乐区最新，实测 30 条，每日更新）
///   - `x/web-interface/search/type?search_type=bili_video`（分区关键词，
///     用于扩充风格多样性，作为后台补充）
/// * Hi-Res 判定必须走 `x/player/playurl`（`dash.flac.audio`，id=30251）。
///   但该接口每首需要 pagelist + playurl 两次请求，**不能对整池同步等待**，
///   因此采用「候选池先出、音质后台扫、结果逐步长出」的增量扫描：
///   - [randomQueue] 只做池内随机，**不发 playurl**（首次播放零额外延迟）
///   - [startScan] 在后台以小并发（默认 4）探测 30251，命中即推入 [picks]
///   - 播放链路解析出的真实音质经 [noteQuality] 回填，扫过的曲目永久缓存，
///     越用越准（“播放时再检查音质”）
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

import 'package:dog_sheep_player/core/bili_api/music.dart';
import 'package:dog_sheep_player/core/bili_api/video.dart';

/// 单条曲目的 Hi-Res 探测结论
enum HiResState {
  /// 未探测
  unknown,

  /// 确认存在 30251 / FLAC 音轨
  available,

  /// 已探测但无 Hi-Res 音轨
  absent,
}

/// 候选池 / 扫描进度快照（供 UI 显示“已扫 n/m”）
class MusicPoolStats {
  final int poolSize;
  final int probed;
  final int hires;
  final bool scanning;
  final bool loading;
  final String? error;

  const MusicPoolStats({
    required this.poolSize,
    required this.probed,
    required this.hires,
    required this.scanning,
    required this.loading,
    this.error,
  });
}

/// Hi-Res 音乐随机推荐器
class MusicRecommend {
  final BiliMusic _music;
  final BiliVideo _video;

  MusicRecommend({required BiliMusic music, required BiliVideo video})
      : _music = music,
        _video = video;

  // ─── 可调参数 ──────────────────────────────────────────────────────────

  /// 榜单二次过滤上限：≥ 10 分钟的条目多半是 L 场 / 合集 / 直播切片
  static const int _maxDurationSeconds = 10 * 60;

  /// 候选池 TTL（期内重复调用 [ensurePool] 不再发请求）
  static const Duration _poolTtl = Duration(minutes: 20);

  /// 单轮扫描最多探测多少首（每首 2 个请求，控制风控风险与耗时）
  static const int _maxProbePerScan = 48;

  /// 探测并发度
  static const int _probeConcurrency = 4;

  /// 两批探测之间的间隔（ms），避免连续 playurl 触发风控
  static const int _probeGapMs = 350;

  /// 精选数量目标：达到该数量后不再“为了填满”而停止，但会继续扫到
  /// [_maxProbePerScan] 以攒够换一批的余量
  static const int picksTarget = 12;

  /// 风格关键词（后台扩充池用，每个关键词 1~2 个请求）
  static const List<String> kPoolKeywords = [
    '古风 歌曲',
    '电子 音乐',
    '说唱',
    '民谣',
    'ACG 音乐',
    'R&B 深听',
  ];

  // ─── 内部状态 ──────────────────────────────────────────────────────────

  List<MusicTrack> _pool = const [];
  DateTime? _poolAt;
  Future<void>? _poolFuture;
  Future<void>? _expandFuture;

  /// bvid -> 探测结论（会话级缓存，扫过就不重复请求）
  final Map<String, HiResState> _state = {};

  /// 已确认有 Hi-Res 的曲目（[picks] 的顺序即展示顺序）
  final List<MusicTrack> _picks = [];

  /// 待探测队列（shuffle 后依次消费）
  List<MusicTrack> _pending = const [];

  int _probed = 0;
  bool _scanning = false;
  bool _loadingPool = false;
  String? _error;

  final StreamController<List<MusicTrack>> _picksController =
      StreamController<List<MusicTrack>>.broadcast();
  final StreamController<MusicPoolStats> _statsController =
      StreamController<MusicPoolStats>.broadcast();

  // ─── 对外快照 / 流 ─────────────────────────────────────────────────────

  /// 已确认有 Hi-Res 的精选曲目
  List<MusicTrack> get picks => List.unmodifiable(_picks);

  /// 精选变化流（扫描过程中逐步增长）
  Stream<List<MusicTrack>> get picksStream => _picksController.stream;

  /// 池 / 扫描进度流
  Stream<MusicPoolStats> get statsStream => _statsController.stream;

  MusicPoolStats get stats => MusicPoolStats(
        poolSize: _pool.length,
        probed: _probed,
        hires: _picks.length,
        scanning: _scanning,
        loading: _loadingPool,
        error: _error,
      );

  HiResState stateOf(String bvid) =>
      _state[bvid] ?? HiResState.unknown;

  /// 登录态变化（扫码成功 / 导入 Cookie）后重置：
  /// 丢弃 WBI 密钥与候选池 TTL，下一首拉取用新会话签名；
  /// 但**保留已探测的 Hi-Res 结论**（playurl 结果与音质档位本身无关，
  /// 重扫代价高）。
  void resetForNewSession() {
    _music.clearWbiCache();
    _video.clearWbiCache();
    _poolAt = null;
    _error = null;
    _notifyStats();
  }

  // ─── 候选池 ────────────────────────────────────────────────────────────

  /// 确保候选池可用（TTL 内直接复用；并发调用共享同一次加载）
  Future<void> ensurePool({bool force = false}) async {
    final at = _poolAt;
    if (!force &&
        _pool.isNotEmpty &&
        at != null &&
        DateTime.now().difference(at) < _poolTtl) {
      return;
    }
    final running = _poolFuture;
    if (!force && running != null) return running;
    final f = _loadPool();
    _poolFuture = f;
    try {
      await f;
    } finally {
      if (_poolFuture == f) _poolFuture = null;
    }
  }

  /// 第一阶段（快速）：排行榜 + 分区最新，共 3 个请求
  Future<void> _loadPool() async {
    _loadingPool = true;
    _error = null;
    _notifyStats();
    try {
      final merged = <String, MusicTrack>{};
      final sources = <List<MusicTrack>>[
        await _music.getRanking(),
        await _music.getRegionNew(size: 30),
        await _music.getRanking(type: 'origin'),
      ];
      var raw = 0;
      for (final list in sources) {
        raw += list.length;
        _merge(merged, list);
      }
      if (merged.isEmpty) {
        _error = raw == 0 ? '音乐接口无返回' : '二次过滤后为空';
        debugPrint('[bili:mixrec] pool empty raw=$raw');
      }
      final list = merged.values.toList()..shuffle();
      _pool = list;
      _poolAt = DateTime.now();
      _pending = list;
      debugPrint('[bili:mixrec] pool loaded raw=$raw '
          'afterDuration=${list.length}');
      _notifyStats();
    } catch (e) {
      _error = '$e';
      debugPrint('[bili:mixrec] pool load failed: $e');
      _notifyStats();
    } finally {
      _loadingPool = false;
      _notifyStats();
    }
  }

  /// 第二阶段（后台）：分区关键词搜索扩充池，不阻塞首屏
  Future<void> _expandPool() async {
    final running = _expandFuture;
    if (running != null) return running;
    final f = () async {
      try {
        final merged = <String, MusicTrack>{};
        for (final t in _pool) {
          merged[t.bvid] = t;
        }
        for (final kw in kPoolKeywords) {
          _merge(merged, await _music.searchMusic(kw));
        }
        final known = _pool.map((e) => e.bvid).toSet();
        final extra =
            merged.values.where((t) => !known.contains(t.bvid)).toList();
        if (extra.isEmpty) return;
        _pool = [..._pool, ...extra];
        // 新曲目插到待探测队列前部（已扫过的不会重扫）
        _pending = [...extra, ..._pending];
        debugPrint('[bili:mixrec] pool expanded +${extra.length} '
            'total=${_pool.length}');
        _notifyStats();
      } catch (e) {
        debugPrint('[bili:mixrec] pool expand failed: $e');
      }
    }();
    _expandFuture = f;
    try {
      await f;
    } finally {
      if (_expandFuture == f) _expandFuture = null;
    }
  }

  /// 合并去重 + 二次过滤（可播 BV / 音乐 tid / 时长 < 10 分钟）
  void _merge(Map<String, MusicTrack> dst, List<MusicTrack> src) {
    var droppedLong = 0;
    for (final t in src) {
      if (!t.bvid.startsWith('BV')) continue;
      if (!isMusicTid(t.tid)) continue;
      // duration==0 表示接口未给出时长，保留；超过 10 分钟判为长视频/合集
      if (t.duration > _maxDurationSeconds) {
        droppedLong++;
        continue;
      }
      dst.putIfAbsent(t.bvid, () => t);
    }
    if (droppedLong > 0) {
      debugPrint('[bili:mixrec] dropLongVideo=$droppedLong');
    }
  }

  // ─── Hi-Res 扫描 ───────────────────────────────────────────────────────

  /// 启动后台扫描（立即返回，结果经 [picksStream] 逐步推送）
  void startScan() {
    unawaited(_scan());
  }

  Future<void> _scan() async {
    if (_scanning) return;
    _scanning = true;
    _notifyStats();
    var expanded = false;
    var sinceLastNotify = 0;
    try {
      await ensurePool();
      while (_probed < _maxProbePerScan) {
        // 池内已无待探测曲目 → 用关键词搜索扩充一轮（只扩一次，避免无限循环）
        if (_pending.isEmpty) {
          if (expanded) break;
          expanded = true;
          await _expandPool();
          if (_pending.isEmpty) break;
          continue;
        }
        final batch = <MusicTrack>[];
        while (batch.length < _probeConcurrency && _pending.isNotEmpty) {
          final t = _pending.first;
          _pending = _pending.sublist(1);
          // 已探测过的直接跳过，不占用本轮配额
          if (_state.containsKey(t.bvid)) continue;
          batch.add(t);
        }
        if (batch.isEmpty) continue; // 全部命中缓存，回到循环顶部（_pending 已空）

        final results = await Future.wait(
          batch.map((t) async => MapEntry(t, await probeHires(t.bvid))),
        );
        for (final entry in results) {
          _probed++;
          if (entry.value) _addPick(entry.key);
        }
        sinceLastNotify += batch.length;
        if (sinceLastNotify >= _probeConcurrency) {
          sinceLastNotify = 0;
          _notifyPicks();
          _notifyStats();
        }
        if (_probeGapMs > 0) {
          await Future<void>.delayed(const Duration(milliseconds: _probeGapMs));
        }
      }
    } catch (e) {
      _error = '$e';
      debugPrint('[bili:mixrec] scan failed: $e');
    } finally {
      _scanning = false;
      _notifyPicks();
      _notifyStats();
      debugPrint('[bili:mixrec] scan done probed=$_probed '
          'hiresPicks=${_picks.length} pool=${_pool.length}');
    }
  }

  /// “换一批”：把已展示的精选挪到池尾并重新洗牌，继续扫描新曲目
  Future<void> rotatePicks() async {
    await ensurePool();
    final shown = _picks.map((e) => e.bvid).toSet();
    final head = _pool.where((t) => !shown.contains(t.bvid)).toList()..shuffle();
    final tail = _pool.where((t) => shown.contains(t.bvid)).toList();
    _pool = [...head, ...tail];
    _pending = head;
    _picks.clear();
    _probed = 0;
    _notifyPicks();
    startScan();
  }

  /// 探测单曲目是否存在 Hi-Res 音轨（会话级缓存）
  Future<bool> probeHires(String bvid) async {
    final cached = _state[bvid];
    if (cached != null) return cached == HiResState.available;
    bool has = false;
    try {
      // cid=0：getAudioStream 内部先用 pagelist 解析首个分 P（共 2 个请求）
      await _video.getAudioStream(
        bvid,
        cid: 0,
        hiResEnabled: true,
        onAvailable: (maxQualityId) {
          has = maxQualityId >= BiliVideo.hiResQualityId;
        },
      );
    } catch (e) {
      debugPrint('[bili:mixrec] probe($bvid) failed: $e');
      has = false;
    }
    _state[bvid] = has ? HiResState.available : HiResState.absent;
    return has;
  }

  /// 播放链路回填真实音质（“播放时再检查音质”，命中即加入精选）
  void noteQuality(String bvid, int maxQualityId) {
    if (bvid.isEmpty || maxQualityId <= 0) return;
    final has = maxQualityId >= BiliVideo.hiResQualityId;
    _state[bvid] = has ? HiResState.available : HiResState.absent;
    if (!has) return;
    for (final t in _pool) {
      if (t.bvid == bvid) {
        _addPick(t);
        break;
      }
    }
    _notifyPicks();
  }

  void _addPick(MusicTrack t) {
    if (_picks.any((e) => e.bvid == t.bvid)) return;
    _picks.add(t);
  }

  // ─── 随机播放队列 ──────────────────────────────────────────────────────

  /// 生成随机播放队列：**不发 playurl**，只做池内随机。
  ///
  /// 排序策略：已确认 Hi-Res 的优先（随机），其余音乐按随机补齐到
  /// [length] 条，保证“点一首 → 几十首随机音乐”立即开始且不断档。
  Future<List<MusicTrack>> randomQueue({int length = 30}) async {
    await ensurePool();
    if (_pool.isEmpty) return const [];
    final picked = <String, MusicTrack>{};
    for (final t in [..._picks]..shuffle()) {
      if (picked.length >= length) break;
      picked.putIfAbsent(t.bvid, () => t);
    }
    if (picked.length < length) {
      for (final t in [..._pool]..shuffle()) {
        if (picked.length >= length) break;
        if (_state[t.bvid] == HiResState.available) continue;
        picked.putIfAbsent(t.bvid, () => t);
      }
    }
    final list = picked.values.take(length).toList();
    if (kDebugMode) {
      debugPrint('[bili:mixrec] randomQueue n=${list.length} '
          'hiresFirst=${_picks.length} pool=${_pool.length}');
    }
    return list;
  }

  /// 以 [start] 为第一首生成随机队列（首页点击曲目时使用）
  Future<List<MusicTrack>> randomQueueFrom(
    MusicTrack start, {
    int length = 30,
  }) async {
    final list = await randomQueue(length: length);
    if (list.isEmpty) return [start];
    list.removeWhere((t) => t.bvid == start.bvid);
    return [start, ...list];
  }

  // ─── 通知 / 释放 ───────────────────────────────────────────────────────

  void _notifyPicks() {
    if (_picksController.isClosed) return;
    _picksController.add(picks);
  }

  void _notifyStats() {
    if (_statsController.isClosed) return;
    _statsController.add(stats);
  }

  void dispose() {
    _picksController.close();
    _statsController.close();
  }
}
