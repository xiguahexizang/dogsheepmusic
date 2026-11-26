/// Bilibili 推荐接口（每日推荐、热门音乐等）
/// 完整实现在 Task #4 中完成，此处定义类型骨架与方法签名
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

import 'package:dog_sheep_player/core/bili_api/music.dart';
import 'package:dog_sheep_player/core/bili_api/wbi_sign.dart';

// ─── 数据类型 ───────────────────────────────────────────────────────────────

/// 推荐批次信息
class RecommendBatch {
  /// 批次 ID（用于分页加载更多）
  final String batchId;

  /// 推荐曲目列表
  final List<MusicTrack> tracks;

  const RecommendBatch({
    required this.batchId,
    required this.tracks,
  });
}

// ─── API 类 ─────────────────────────────────────────────────────────────────

/// Bilibili 推荐 API 封装
class BiliRecommend {
  final Dio _dio;

  /// 首页推荐接口
  static const String _rcmdUrl =
      'https://api.bilibili.com/x/web-interface/index/top/rcmd';

  /// 视频元数据接口（补齐推荐 / 热门条目缺失的 tid）
  static const String _viewUrl =
      'https://api.bilibili.com/x/web-interface/view';

  /// 音乐源复用：排行榜 / 分区最新 / 音乐搜索
  ///
  /// 与 [BiliRecommend] 共享同一个 Dio（登录态、代理、Cookie 完全一致）。
  late final BiliMusic _music = BiliMusic(_dio);

  /// 每日推荐期望条数（不足则从音乐榜单 / 分区最新补齐）
  static const int _dailyTarget = 20;

  WbiKeys? _wbiCache;
  DateTime? _wbiCacheTime;

  BiliRecommend(this._dio);

  /// 获取并缓存 WBI 密钥（10 分钟）。
  ///
  /// 失败时**不写缓存**，下一次调用会重新拉取；密钥本身与登录态无关，
  /// 因此登录成功后应立即调用 [clearWbiCache] 让后续请求使用最新密钥。
  Future<WbiKeys> _getWbiKeys() async {
    final now = DateTime.now();
    if (_wbiCache != null &&
        _wbiCacheTime != null &&
        now.difference(_wbiCacheTime!) < const Duration(minutes: 10)) {
      return _wbiCache!;
    }
    final keys = await WbiSign.getWbiKeys(_dio);
    _wbiCache = keys;
    _wbiCacheTime = now;
    return keys;
  }

  /// 清空 WBI 密钥缓存（登录态变化、或签名被拒时调用）
  void clearWbiCache() {
    _wbiCache = null;
    _wbiCacheTime = null;
  }

  Map<String, dynamic>? _unwrapData(dynamic raw) {
    if (raw is! Map) return null;
    // code 正常情况下为 num；风控页 / 代理返回异常内容时可能为字符串，
    // 因此用宽容解析避免 `as num?` 抛 TypeError（Error 不会被 on Exception 捕获）
    final rawCode = raw['code'];
    final code = rawCode is num
        ? rawCode.toInt()
        : int.tryParse(rawCode?.toString() ?? '') ?? -1;
    if (code != 0) {
      debugPrint('[bili:recommend] api code=$code message=${raw['message']}');
      return null;
    }
    final d = raw['data'];
    return d is Map<String, dynamic>
        ? d
        : (d is Map ? Map<String, dynamic>.from(d) : null);
  }

  /// 统一异常记录：吞掉异常会让“加载失败”变成无迹可查的空列表，
  /// 因此这里在 debug 构建下输出真实原因，便于定位 Cookie / WBI / 风控问题。
  void _logError(String where, Object error) {
    if (kDebugMode) {
      debugPrint('[bili:recommend] $where failed: $error');
    }
  }

  /// 将推荐条目映射为 MusicTrack
  /// 首页推荐条目结构：{ id, title, type, param(=bvid), cover, owner_name, duration, ... }
  MusicTrack? _trackFromRcmd(Map<String, dynamic> e) {
    final bvid = (e['bvid'] ??
            (e['param'] is String && (e['param'] as String).startsWith('BV')
                ? e['param']
                : e['id']))
        .toString();
    if (bvid.isEmpty || bvid == 'null') return null;
    // popular / feed 类接口：封面可能为 `pic` 或 List<String>，作者可能在 owner.name
    final owner = e['owner'];
    final artist = e['owner_name'] ??
        e['author'] ??
        e['up_name'] ??
        (owner is Map ? owner['name'] : null) ??
        '';
    final rawCover = e['cover'] ?? e['pic'] ?? '';
    final cover = rawCover is List
        ? (rawCover.isNotEmpty ? rawCover.first : '')
        : rawCover;
    return MusicTrack(
      bvid: bvid,
      title: (e['title'] ?? '').toString(),
      artist: artist.toString(),
      cover: cover.toString(),
      duration: _durationSeconds(e['duration']),
    );
  }

  /// duration 字段在不同接口里可能是秒数（num）或 `mm:ss` / 纯数字字符串
  static int _durationSeconds(dynamic raw) {
    if (raw is num) return raw.toInt();
    if (raw is String) {
      if (!raw.contains(':')) return int.tryParse(raw) ?? 0;
      final parts = raw.split(':');
      var seconds = 0;
      for (final p in parts) {
        seconds = seconds * 60 + (int.tryParse(p.trim()) ?? 0);
      }
      return seconds;
    }
    return 0;
  }

  /// 发起带 WBI 签名的 GET，返回响应里的 `data` 对象。
  /// code != 0 时返回 null（内部已记录错误码）。
  Future<Map<String, dynamic>?> _signedGet(
    String url,
    Map<String, dynamic> rawParams,
  ) async {
    final keys = await _getWbiKeys();
    final resp = await _dio.get<dynamic>(
      url,
      queryParameters: WbiSign.sign(rawParams, keys),
    );
    return _unwrapData(resp.data);
  }

  /// 从 data 对象里取列表（不同接口分别命名为 list / item / items.recommend）
  static List<dynamic>? _extractList(Map<String, dynamic>? d) {
    if (d == null) return null;
    final direct = d['list'] ?? d['item'];
    if (direct is List) return direct;
    final items = d['items'];
    if (items is Map) {
      final rec = items['recommend'] ?? items['list'];
      if (rec is List) return rec;
    }
    return null;
  }

  /// 获取每日推荐（需登录态 + WBI 签名）
  ///
  /// 接口：GET https://api.bilibili.com/x/web-interface/index/top/rcmd
  ///
  /// **实测问题**：rcmd 返回的是全站个性化推荐（8 条里仅 1 条是音乐），
  /// 且条目本身**不带 tid**（只有 `type`/`param`），无法直接判定分区。
  /// 因此流程改为：
  /// 1. `x/web-interface/view` 并发（6 路）补齐 tid
  /// 2. 按 [isMusicTid] 严格过滤，剔除游戏/生活/影视剪辑
  /// 3. 不足 [_dailyTarget] 条时用音乐排行榜（rid=3）+ 分区最新（newlist）补齐并去重
  ///
  /// 过滤前后的条目数与 tid 分布会在 debug 构建下打印（[debugTrackFilter]）。
  Future<List<MusicTrack>> getDailyRecommend() async {
    var raw = const <MusicTrack>[];
    try {
      final d = await _signedGet(_rcmdUrl, const {
        'version': '1',
        'fnver': '0',
        'fnval': '40',
      });
      raw = _toTracks(_extractList(d));
    } catch (error) {
      _logError('getDailyRecommend', error);
    }

    final enriched = await _enrichTids(raw);
    final music =
        enriched.where((t) => t.bvid.startsWith('BV') && isMusicTid(t.tid)).toList();
    debugTrackFilter('rcmd(view+tid)', enriched, music);

    if (music.length >= _dailyTarget) return music;

    // 不足则用真正的音乐源补齐（popular 是全站热门，几乎无音乐，不能当降级源）
    final result = List<MusicTrack>.from(music);
    _appendUnique(result, await getHotMusic(), _dailyTarget);
    if (result.length < _dailyTarget) {
      _appendUnique(result, await _music.getRegionNew(size: 30), _dailyTarget);
    }
    debugPrint('[bili:recommend] getDailyRecommend final=${result.length} '
        'rcmdMusic=${music.length}');
    return result;
  }

  /// 获取热门音乐
  ///
  /// 旧实现走 `x/web-interface/popular`（全站热门，过滤后几乎为空），
  /// 现语义改为“热门音乐”，直接取音乐整区排行榜（rid=3，实测 97 条全音乐）。
  Future<List<MusicTrack>> getHotMusic() => _music.getRanking();

  /// 并发补齐 tid（仅对 tid<=0 且 bvid 合法的条目，最多 [concurrency] 路）
  Future<List<MusicTrack>> _enrichTids(
    List<MusicTrack> tracks, {
    int concurrency = 6,
  }) async {
    final need = tracks
        .where((t) => t.tid <= 0 && t.bvid.startsWith('BV'))
        .toList();
    if (need.isEmpty) return tracks;

    final tidByBvid = <String, int>{};
    for (var i = 0; i < need.length; i += concurrency) {
      final end = (i + concurrency) > need.length ? need.length : i + concurrency;
      final batch = need.sublist(i, end);
      await Future.wait(batch.map((t) async {
        try {
          final resp = await _dio.get<dynamic>(
            _viewUrl,
            queryParameters: {'bvid': t.bvid},
          );
          final d = _unwrapData(resp.data);
          final rawTid = d?['tid'];
          final tid = rawTid is num
              ? rawTid.toInt()
              : int.tryParse(rawTid?.toString() ?? '');
          if (tid != null && tid > 0) tidByBvid[t.bvid] = tid;
        } catch (error) {
          _logError('view(${t.bvid})', error);
        }
      }));
    }
    if (tidByBvid.isEmpty) return tracks;
    return tracks
        .map((t) => t.tid > 0 ? t : t.copyWith(tid: tidByBvid[t.bvid]))
        .toList();
  }

  /// 按 bvid 去重追加，直到达到 [target] 条
  static void _appendUnique(
    List<MusicTrack> dst,
    List<MusicTrack> src,
    int target,
  ) {
    for (final t in src) {
      if (dst.length >= target) return;
      if (!t.bvid.startsWith('BV')) continue;
      if (dst.any((e) => e.bvid == t.bvid)) continue;
      dst.add(t);
    }
  }

  /// 获取音乐排行榜（首页“热门歌曲”数据源）
  ///
  /// 接口：GET https://api.bilibili.com/x/web-interface/ranking/v2?rid=3&type=all
  ///
  /// **rid 实测结论**（2026-11，直接请求验证）：
  /// - `rid=29` → `code=-400 请求错误`（该编号已失效，旧代码因此拿不到任何数据）
  /// - `rid=3`  → 音乐整区榜单（97 条，首选）
  /// - `rid=1001` → 音乐子分区榜单（仅作兼容降级）
  ///
  /// 不再降级到 popular（全站热门，会重新把非音乐内容塞进首页）。
  Future<List<MusicTrack>> getRanking() => _music.getRanking();

  List<MusicTrack> _toTracks(List<dynamic>? raw) {
    if (raw == null) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(_trackFromRcmd)
        .whereType<MusicTrack>()
        .toList();
  }

  /// 加载更多推荐（分页）
  ///
  /// 接口：GET https://api.bilibili.com/x/web-interface/index/top/rcmd
  /// 注：[batchId] 作为分页游标（bnid）；返回同样需要 view 补 tid + 音乐过滤，
  /// 否则分页会把非音乐内容灌进首页。
  ///
  /// **rid 已移除**：旧实现带 `'rid': '29'`，该编号实测 `code=-400`。
  Future<RecommendBatch> loadMore(String batchId) async {
    final rawParams = <String, dynamic>{
      'version': '1',
      'fnver': '0',
      'fnval': '40',
      if (batchId.isNotEmpty) 'bnid': batchId,
    };
    try {
      final d = await _signedGet(_rcmdUrl, rawParams);
      final rawItems = _extractList(d);
      final tracks = _toTracks(rawItems);
      final enriched = await _enrichTids(tracks);
      final music = enriched
          .where((t) => t.bvid.startsWith('BV') && isMusicTid(t.tid))
          .toList();
      debugTrackFilter('loadMore', enriched, music);
      final nextBnid = (d?['bnid'] ?? batchId).toString();
      return RecommendBatch(batchId: nextBnid, tracks: music);
    } catch (error) {
      _logError('loadMore', error);
      return RecommendBatch(batchId: batchId, tracks: const []);
    }
  }
}
