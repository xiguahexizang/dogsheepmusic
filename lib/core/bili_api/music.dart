/// Bilibili 音乐相关接口（排行榜、歌单、歌曲详情等）
/// 完整实现在 Task #3 中完成，此处定义类型骨架与方法签名
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

import 'package:dog_sheep_player/core/bili_api/wbi_sign.dart';

// ─── JSON 宽松取值 ──────────────────────────────────────────────────────────
// B 站各接口同一字段类型并不稳定（duration 可能为 num，也可能为 "mm:ss"
// 字符串；owner 可能缺失或形态不同）。直接 `as` 会抛 TypeError，而
// TypeError 属于 Error，不会被 `on Exception` 捕获，会冒泡到 UI
// 表现为“加载失败”。以下 helper 统一做宽容解析。

String _str(Object? v, [String fallback = '']) =>
    v == null ? fallback : v.toString();

int _int(Object? v, [int fallback = 0]) {
  if (v is num) return v.toInt();
  final s = v?.toString().trim() ?? '';
  if (s.isEmpty) return fallback;
  if (s.contains(':')) {
    var total = 0;
    for (final part in s.split(':')) {
      final n = int.tryParse(part.trim());
      if (n == null) return fallback;
      total = total * 60 + n;
    }
    return total;
  }
  return int.tryParse(s) ?? fallback;
}

Map<String, dynamic>? _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : null;

List<dynamic> _list(Object? v) => v is List ? v : const <dynamic>[];

/// 取嵌套对象字段（owner / stat 等），形态不符时返回空 Map
Map<String, dynamic> _sub(Object? v) => _map(v) ?? const <String, dynamic>{};

// ─── 音乐分区判定 ────────────────────────────────────────────────────────────

/// Bilibili「音乐」整区（rid=3）下的子分区 tid 集合。
///
/// 实测来源：`x/web-interface/ranking/v2?rid=3` 返回条目的 tid 分布 +
/// `x/web-interface/view` 补齐的 tid。推荐 / 热门 / 搜索接口返回大量
/// 非音乐内容（游戏、生活、影视剪辑），必须按此集合严格过滤，
/// 否则首页会出现“视频太多、音乐太少”。
const Set<int> kMusicTids = {
  28, // 音乐综合
  29, // 音乐现场
  30, // 乐评盘点
  31, // 歌曲
  59, // 演奏
  130, // 音乐综合（老编号）
  193, // MV
  243, // 原创音乐
  244, // 翻唱
  245, // 虚拟歌手
  254, // 音乐玩家观摩会
  265, // 最 Bint3000（说唱）
  267, // 电台
};

/// 该 tid 是否属于音乐分区（tid<=0 视为未知，不算音乐）
bool isMusicTid(Object? rawTid) {
  final tid = rawTid is num ? rawTid.toInt() : int.tryParse('$rawTid');
  if (tid == null || tid <= 0) return false;
  return kMusicTids.contains(tid);
}

/// 过滤前后条目数与 tid 分布（debug 构建输出，便于定位
/// “视频太多、音乐太少”到底是接口没给数据还是被过滤掉了）
void debugTrackFilter(
  String source,
  List<MusicTrack> before,
  List<MusicTrack> after,
) {
  if (!kDebugMode) return;
  final dist = <String, int>{};
  for (final t in before) {
    final key = t.tid <= 0 ? 'unknown' : '${t.tid}${isMusicTid(t.tid) ? '' : '*'}';
    dist[key] = (dist[key] ?? 0) + 1;
  }
  final badBvid = before.where((t) => !t.bvid.startsWith('BV')).length;
  debugPrint('[bili:filter] $source before=${before.length} '
      'after=${after.length} nonPlayableBvid=$badBvid tidDist=$dist');
}

/// 只保留「可播 BV 号」条目；若整批都拿不到 tid（老接口不返回），
/// 则降级保留全部可播条目，避免过滤条件把列表清空。
List<MusicTrack> filterMusicTracks(Iterable<MusicTrack> src) {
  final playable = src.where((t) => t.bvid.startsWith('BV')).toList();
  final music = playable.where((t) => isMusicTid(t.tid)).toList();
  return music.isNotEmpty ? music : playable;
}

// ─── 数据类型 ───────────────────────────────────────────────────────────────

/// 音乐曲目简要信息
class MusicTrack {
  /// Bilibili 视频 ID（BV 号）
  final String bvid;

  /// 曲目名称
  final String title;

  /// 艺术家 / UP 主名称
  final String artist;

  /// 封面图 URL
  final String cover;

  /// 歌词文本（LRC 格式，可能为 null）
  final String? lyric;

  /// 时长（秒）
  final int duration;

  /// 所属分区 tid（排行榜 / view / 搜索的 tid|typeid；未知为 0）
  ///
  /// 用于上层判定是否音乐分区（[isMusicTid]），避免把游戏、生活区
  /// 视频当成歌曲塞进音乐列表。
  final int tid;

  const MusicTrack({
    required this.bvid,
    required this.title,
    required this.artist,
    required this.cover,
    this.lyric,
    this.duration = 0,
    this.tid = 0,
  });

  factory MusicTrack.fromJson(Map<String, dynamic> json) {
    // 兼容多种接口返回：排行榜 / 歌单 / 搜索结果字段命名不同
    // 剥离搜索接口返回的 <em class="keyword"> 高亮标签
    String clean(Object? raw) {
      if (raw == null) return '';
      return raw.toString().replaceAll(RegExp(r'<[^>]*>'), '');
    }

    // 作者字段：搜索 / 排行榜用 owner.name，音乐服务区用 author / up_name，
    // 部分卡片用 source（UP 主名）
    final artist = json['author'] ??
        json['up_name'] ??
        json['source'] ??
        _sub(json['owner'])['name'];

    return MusicTrack(
      bvid: (json['bvid'] ?? json['bv_id'] ?? json['vid'] ?? '').toString(),
      title: clean(json['title'] ?? json['name']),
      artist: clean(artist),
      cover: (json['pic'] ?? json['cover'] ?? '').toString(),
      duration: _int(json['duration']),
      // 排行榜 / view 用 tid，搜索结果用 typeid
      tid: _int(json['tid'] ?? json['typeid']),
    );
  }

  /// 局部覆盖（推荐 / 热门接口不返回 tid，需要用 view 补齐后回填）
  MusicTrack copyWith({
    String? title,
    String? artist,
    String? cover,
    String? lyric,
    int? duration,
    int? tid,
  }) {
    return MusicTrack(
      bvid: bvid,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      cover: cover ?? this.cover,
      lyric: lyric ?? this.lyric,
      duration: duration ?? this.duration,
      tid: tid ?? this.tid,
    );
  }
}

/// 音乐曲目详细信息（包含音频流数据）
class MusicTrackDetail {
  final MusicTrack track;

  /// 分 P 列表（多 P 视频）
  final List<MusicPage> pages;

  const MusicTrackDetail({
    required this.track,
    this.pages = const [],
  });
}

/// 视频分 P 信息
class MusicPage {
  final int cid;
  final int page;
  final String part;
  final int duration;

  const MusicPage({
    required this.cid,
    required this.page,
    required this.part,
    required this.duration,
  });

  factory MusicPage.fromJson(Map<String, dynamic> json) {
    return MusicPage(
      cid: _int(json['cid']),
      page: _int(json['page'], 1),
      part: _str(json['part']),
      duration: _int(json['duration']),
    );
  }
}

/// 歌词缓存条目（null = 已确认无字幕，短 TTL 后重试）
class _LyricCacheEntry {
  final String? text;
  final DateTime expires;

  const _LyricCacheEntry({required this.text, required this.expires});
}

// ─── API 类 ─────────────────────────────────────────────────────────────────

/// Bilibili 音乐 API 封装
class BiliMusic {
  final Dio _dio;

  /// 排行榜接口（rid=3 为音乐整区）
  static const String _rankingUrl =
      'https://api.bilibili.com/x/web-interface/ranking/v2';

  /// 分区最新接口（**实测数据在 `data.archives`，不是 `data.list`**）
  static const String _newlistUrl =
      'https://api.bilibili.com/x/web-interface/newlist';

  /// 视频/音乐元数据接口
  static const String _viewUrl =
      'https://api.bilibili.com/x/web-interface/view';

  /// 播放器信息接口 —— **唯一可用的歌词来源**（CC 字幕）
  ///
  /// 实测：`x/music-common/lyric/get`、`x/music/short/get`、
  /// `audio/music-service-c/web/lyric`、`x/player/lyric/get` 全部 HTTP 404，
  /// `x/player/wbi/v2` 返回 0 条字幕，只有 `x/player/v2` 有 `subtitles[]`。
  static const String _playerV2Url =
      'https://api.bilibili.com/x/player/v2';

  /// 搜索接口
  static const String _searchUrl =
      'https://api.bilibili.com/x/web-interface/search/type';

  /// 视频页面前缀（playurl / player/v2 / 搜索接口需要对应 Referer）
  static const String _watchPrefix = 'https://www.bilibili.com/video/';

  /// WBI 密钥缓存
  WbiKeys? _wbiCache;
  DateTime? _wbiCacheTime;

  BiliMusic(this._dio);

  /// 清空 WBI 密钥缓存（登录态变化后重新取密钥，与 recommend.dart 一致）
  void clearWbiCache() {
    _wbiCache = null;
    _wbiCacheTime = null;
  }

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

  /// 从响应中提取 data 字段（code==0）
  ///
  /// code 在风控页 / 代理异常内容里可能是字符串，直接 `!= 0` 会误判，
  /// 因此宽容解析（与 recommend.dart 保持同一策略）。
  Map<String, dynamic>? _unwrapData(dynamic raw) {
    if (raw is! Map) return null;
    final rawCode = raw['code'];
    final code = rawCode is num
        ? rawCode.toInt()
        : int.tryParse(rawCode?.toString() ?? '') ?? -1;
    if (code != 0) return null;
    return _map(raw['data']);
  }

  /// 获取音乐排行榜
  ///
  /// 接口：GET https://api.bilibili.com/x/web-interface/ranking/v2?rid=3&type=all
  ///
  /// **rid 实测**（2026-11）：`rid=29` 已被 B 站拒给（`code=-400 请求错误`），
  /// `rid=3` 为音乐整区榜单（97 条，全部音乐分区），`rid=1001` 为子分区榜单
  /// （作为降级，仍按 [isMusicTid] 过滤避免污染）。
  ///
  /// **type 实测**：`all` / `origin` 可用，`rise` 返回 `code=-400`（飙升榜已下线）。
  Future<List<MusicTrack>> getRanking({String type = 'all'}) async {
    for (final rid in const ['3', '1001']) {
      try {
        final keys = await _getWbiKeys();
        final params = WbiSign.sign({'rid': rid, 'type': type}, keys);
        final resp = await _dio.get<dynamic>(
          _rankingUrl,
          queryParameters: params,
        );
        final d = _unwrapData(resp.data);
        final list = _list(d?['list']);
        if (list.isEmpty) continue;
        final raw = list
            .whereType<Map<String, dynamic>>()
            .map(MusicTrack.fromJson)
            .toList();
        final filtered = filterMusicTracks(raw);
        debugTrackFilter('ranking(rid=$rid,type=$type)', raw, filtered);
        if (filtered.isNotEmpty) return filtered;
      } on Exception {
        // 换一个 rid 重试；均失败则返回空列表
      }
    }
    return const [];
  }

  /// 获取音乐分区最新（每日更新的分区稿件）
  ///
  /// 接口：GET https://api.bilibili.com/x/web-interface/newlist?rid=3&pn=1&ps=30
  ///
  /// **实测**：数据在 `data.archives`（20 条，19/20 为音乐分区），
  /// 旧实现读 `data.list` 因此恒为空。
  Future<List<MusicTrack>> getRegionNew({int page = 1, int size = 30}) async {
    try {
      final keys = await _getWbiKeys();
      final params = WbiSign.sign({
        'rid': '3',
        'pn': page.toString(),
        'ps': size.toString(),
      }, keys);
      final resp = await _dio.get<dynamic>(
        _newlistUrl,
        queryParameters: params,
      );
      final d = _unwrapData(resp.data);
      final archives = _list(d?['archives']);
      final list = archives.isNotEmpty ? archives : _list(d?['list']);
      if (list.isEmpty) return const [];
      final raw = list
          .whereType<Map<String, dynamic>>()
          .map(MusicTrack.fromJson)
          .toList();
      final filtered = filterMusicTracks(raw);
      debugTrackFilter('newlist(rid=3,pn=$page)', raw, filtered);
      return filtered;
    } on Exception {
      return const [];
    }
  }

  /// 获取精选歌单内的曲目
  ///
  /// **实测**：旧接口 `audio/music-service-c/web/song/of-catalog?sid=xxx`
  /// 目录里约定的 8 个 catalog sid 全部 HTTP 404（接口已下线），而且该接口
  /// 返回的是歌曲 sid（无 bvid）根本无法播放，因此歌单改为「描述符」形式：
  /// - `rank:all` / `rank:origin` → 排行榜（[getRanking]）
  /// - `new:3` → 分区最新（[getRegionNew]）
  /// - `kw:关键词` → 音乐分区搜索（[searchMusic]）
  ///
  /// 未知描述符（包括旧的纯数字 sid）不再发请求，直接降级为排行榜。
  Future<List<MusicTrack>> getPlaylist(String descriptor) async {
    final id = descriptor.trim();
    if (id.isEmpty) return const [];
    if (id.startsWith('rank:')) {
      final type = id.substring(5);
      final list = await getRanking(type: type.isEmpty ? 'all' : type);
      if (list.isEmpty && type != 'all') return getRanking();
      return list;
    }
    if (id.startsWith('new:')) {
      final list = await getRegionNew();
      if (list.isNotEmpty) return list;
      return getRanking();
    }
    if (id.startsWith('kw:')) {
      final keyword = id.substring(3);
      final list = await searchMusic(keyword);
      if (list.isNotEmpty) return list;
      return getRanking();
    }
    return getRanking();
  }

  /// 获取歌曲详情（含分 P 信息与歌词）
  ///
  /// 接口：GET https://api.bilibili.com/x/web-interface/view?bvid={bvid}
  Future<MusicTrackDetail?> getTrackDetail(String bvid) async {
    try {
      final resp = await _dio.get<dynamic>(
        _viewUrl,
        queryParameters: {'bvid': bvid},
      );
      final d = _unwrapData(resp.data);
      if (d == null) return null;

      final pagesRaw =
          _list(d['pages']).whereType<Map<String, dynamic>>().toList();
      final firstCid = pagesRaw.isNotEmpty ? _int(pagesRaw.first['cid']) : 0;

      final lyric = await getLyric(bvid, cid: firstCid);

      final track = MusicTrack(
        bvid: _str(d['bvid']),
        title: _str(d['title']),
        artist: _str(_sub(d['owner'])['name']),
        cover: _str(d['pic']),
        duration: _int(d['duration']),
        tid: _int(d['tid']),
        lyric: lyric,
      );

      final pages = pagesRaw.map(MusicPage.fromJson).toList();

      return MusicTrackDetail(track: track, pages: pages);
    } on Exception {
      return null;
    }
  }

  /// 获取歌词（标准 LRC 文本）
  ///
  /// **唯一可用接口**：GET https://api.bilibili.com/x/player/v2?bvid=&cid=
  /// 取 `data.subtitle.subtitles[]`（含 `ai-zh` AI 字幕），再把 `subtitle_url`
  /// 指向的 JSON `body[]`（`{from, to, content}`）转成 `[mm:ss.xx]` 行，
  /// 以匹配 `lyric_widget.parseLrc` 的正则。
  ///
  /// 已实测不可用（不要再尝试）：`x/music-common/lyric/get`、`x/music/short/get`、
  /// `audio/music-service-c/web/lyric`、`x/player/lyric/get` 均 404；
  /// `x/player/wbi/v2` 返回 0 条字幕。
  ///
  /// **两个实测要点**（同一 bvid+cid 反复请求统计，2026-11）：
  /// 1. **必须登录**：只带 buvid3/buvid4 的匿名请求 `subtitles` 恒为空
  ///    （实测 0/4），响应里的 `data.need_login_subtitle` 即此含义；
  ///    `BiliAuth.importCookies` / 扫码注入的 SESSDATA 是前提。
  /// 2. **服务端返回带有意外的偶发性**（与 Referer / 签名 / 请求间隔无关）：
  ///    同一 (bvid,cid) 连续请求命中率约 30%~60%，`x/player/wbi/v2` 则恒为
  ///    0 条（实测 0/12，必须用非签名的 `x/player/v2`）。因此重试 6 次，
  ///    间隔 900~2400ms 抖动（固定节奏容易连续落空）。
  ///    只缓存命中结果（30 分钟）；未命中写 60s 短缓存，避免播放器
  ///    反复重建时把配额空耗在同一首上。
  Future<String?> getLyric(String bvid, {int cid = 0}) async {
    if (!bvid.startsWith('BV')) return null;
    final cached = _lyricCache[bvid];
    if (cached != null && cached.expires.isAfter(DateTime.now())) {
      return cached.text;
    }
    final text = await _fetchLyric(bvid, cid: cid);
    _lyricCache[bvid] = _LyricCacheEntry(
      text: text,
      // 命中缓存 30 分钟；未命中只锁 60 秒，切回该曲时还能再试
      expires: DateTime.now().add(
        text == null
            ? const Duration(seconds: 60)
            : const Duration(minutes: 30),
      ),
    );
    return text;
  }

  /// 歌词结果缓存（bvid → LRC / null）
  final Map<String, _LyricCacheEntry> _lyricCache = {};

  Future<String?> _fetchLyric(String bvid, {int cid = 0}) async {
    try {
      var actualCid = cid;
      if (actualCid <= 0) {
        final resp = await _dio.get<dynamic>(
          _viewUrl,
          queryParameters: {'bvid': bvid},
        );
        final d = _unwrapData(resp.data);
        final pages = _list(d?['pages']);
        if (pages.isNotEmpty) {
          actualCid = _int(_map(pages.first)?['cid']);
        }
      }
      if (actualCid <= 0) return null;

      Map? target;
      for (var attempt = 0; attempt < 6 && target == null; attempt++) {
        if (attempt > 0) {
          // 抖动间隔：命中率本身是随机的，固定节奏容易整段落空
          await Future<void>.delayed(
            Duration(milliseconds: 900 + attempt * 300),
          );
        }
        final resp = await _dio.get<dynamic>(
          _playerV2Url,
          queryParameters: {'bvid': bvid, 'cid': actualCid.toString()},
          options: Options(headers: {'Referer': '$_watchPrefix$bvid'}),
        );
        final d = _unwrapData(resp.data);
        // 注意：`subtitles` 是 **List**，不能再套 `_map()`（`_map` 对 List 返回
        // null → subtitles 恒为空 → 歌词永远取不到）。实测拦截器里响应明明有
        // 1~2 条字幕，而本函数判定为空，就是这个类型误用造成的。
        final subtitleNode = _map(d?['subtitle']);
        final subtitles = _list(subtitleNode?['subtitles']).whereType<Map>();
        if (subtitles.isEmpty) {
          _logApi('getLyric($bvid) attempt=$attempt no-subtitle', resp.data);
          continue;
        }
        target = _pickSubtitle(subtitles);
      }
      if (target == null) return null;

      // subtitle_url 实测为协议相对地址（//aisubtitle.hdslb.com/...），必须补 https:
      final url = _absoluteUrl(_str(target['subtitle_url']));
      if (url.isEmpty) return null;

      final bodyResp = await _dio.get<dynamic>(
        url,
        options: Options(headers: {'Referer': '$_watchPrefix$bvid'}),
      );
      final body = _list(_map(bodyResp.data)?['body']);
      if (body.isEmpty) return null;
      final lrc = _subtitlesToLrc(body);
      return lrc.isEmpty ? null : lrc;
    } on Exception {
      return null;
    }
  }

  /// 字幕候选：优先人工中文字幕，其次 ai-zh，最后任意可用字幕
  static Map? _pickSubtitle(Iterable<Map> subtitles) {
    Map? fallback;
    for (final raw in subtitles) {
      final url = _absoluteUrl(_str(raw['subtitle_url']));
      if (url.isEmpty) continue;
      final lan = _str(raw['lan']).toLowerCase();
      if (lan == 'ai-zh') {
        fallback ??= raw;
        continue;
      }
      if (lan == 'zh' || lan == 'zh-cn' || lan.startsWith('zh-')) return raw;
    }
    if (fallback != null) return fallback;
    for (final raw in subtitles) {
      if (_absoluteUrl(_str(raw['subtitle_url'])).isNotEmpty) return raw;
    }
    return null;
  }

  static String _absoluteUrl(String raw) {
    if (raw.isEmpty) return '';
    if (raw.startsWith('https://') || raw.startsWith('http://')) return raw;
    if (raw.startsWith('//')) return 'https:$raw';
    return '';
  }

  /// 字幕 JSON body → LRC（`parseLrc` 需要 `[mm:ss.xx]` 形式）
  static String _subtitlesToLrc(List<dynamic> body) {
    final buf = StringBuffer();
    for (final raw in body) {
      final m = _map(raw);
      if (m == null) continue;
      final text = _str(m['content']).trim();
      if (text.isEmpty) continue;
      final rawFrom = m['from'];
      final from = rawFrom is num
          ? rawFrom.toDouble()
          : double.tryParse('$rawFrom') ?? 0.0;
      final totalMs = (from * 1000).round().clamp(0, 24 * 3600 * 1000);
      final mm = (totalMs ~/ 60000).toString().padLeft(2, '0');
      final ss = ((totalMs % 60000) / 1000)
          .toStringAsFixed(2)
          .padLeft(5, '0');
      buf.write('[$mm:$ss]$text\n');
    }
    return buf.toString().trim();
  }

  /// 接口返回非 0 code / 非 JSON 时的诊断输出（不含 Cookie / 完整 URL）
  void _logApi(String where, dynamic raw) {
    if (!kDebugMode) return;
    if (raw is Map) {
      debugPrint('[bili:music] $where code=${raw['code']} '
          'message=${raw['message']}');
    } else {
      final s = '$raw';
      debugPrint('[bili:music] $where nonJson type=${raw.runtimeType} '
          'head=${s.length > 80 ? s.substring(0, 80) : s}');
    }
  }

  /// 搜索（视频/音乐）
  ///
  /// 接口：GET https://api.bilibili.com/x/web-interface/search/type
  /// 参数：search_type=video, keyword, page，需 WBI 签名
  ///
  /// **实测**：必须带 `search.bilibili.com` 的 Referer，否则接口返回 HTML
  /// 风控页（JSON 解析失败→列表恒空）；Referer 里的关键词必须 URL 编码，
  /// 含中文时未编码会直接抛 `FormatException: Invalid HTTP header field value`。
  /// 结果条目分区字段是 `typeid`（非 `tid`），时长为 `mm:ss` 字符串。
  ///
  /// **风控**：该接口约 1qps，连续请求时会给 `code=0` 但 `result` 缺失（实测
  /// 多个关键词交替出现 0 条 / 20 条），因此空结果时退避 900ms 重试一次。
  Future<List<MusicTrack>> search(String keyword, {int page = 1}) async {
    final rawParams = <String, dynamic>{
      'search_type': 'video',
      'keyword': keyword,
      'page': page.toString(),
    };
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final keys = await _getWbiKeys();
        final params = WbiSign.sign(rawParams, keys);
        final resp = await _dio.get<dynamic>(
          _searchUrl,
          queryParameters: params,
          options: Options(headers: {
            'Referer':
                'https://search.bilibili.com/all?keyword=${Uri.encodeComponent(keyword)}',
          }),
        );
        final d = _unwrapData(resp.data);
        if (d == null) {
          _logApi('search($keyword) attempt=$attempt', resp.data);
        } else {
          final list = _list(d['result']);
          if (list.isNotEmpty) {
            return list
                .whereType<Map<String, dynamic>>()
                .map(MusicTrack.fromJson)
                .toList();
          }
          debugPrint('[bili:music] search($keyword) attempt=$attempt 空 result');
        }
      } on Exception catch (error) {
        debugPrint('[bili:music] search($keyword) attempt=$attempt error: $error');
      }
      if (attempt == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 900));
      }
    }
    return const [];
  }

  /// 音乐分区搜索（严格过滤 tid，剔除游戏/生活/影视剪辑）
  Future<List<MusicTrack>> searchMusic(String keyword, {int page = 1}) async {
    final raw = await search(keyword, page: page);
    final music = raw
        .where((t) => t.bvid.startsWith('BV') && isMusicTid(t.tid))
        .toList();
    debugTrackFilter('searchMusic($keyword)', raw, music);
    return music;
  }
}
