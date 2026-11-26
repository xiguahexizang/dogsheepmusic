/// Bilibili 视频 / 音频流接口
/// 完整实现在 Task #3 中完成，此处定义类型骨架与方法签名
library;

import 'package:dio/dio.dart';
import 'package:dog_sheep_player/core/bili_api/wbi_sign.dart';

// ─── JSON 宽松取值 ──────────────────────────────────────────────────────────
// playurl / view / pagelist 的字段类型并非绝对稳定（如 `data` 在部分
// 异常返回中为数组、`deadline` 可能为字符串）。`as` 失败会抛 TypeError，
// 而 TypeError 属于 Error，不会被 `on DioException` / `on Exception` 捕获，
// 会直接冒泡导致播放 / 页面崩溃。因此统一走下列宽容取值。

String _str(Object? v, [String fallback = '']) =>
    v == null ? fallback : v.toString();

String? _strOrNull(Object? v) {
  if (v == null) return null;
  final s = v.toString();
  return s.isEmpty ? null : s;
}

int _int(Object? v, [int fallback = 0]) {
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString().trim() ?? '') ?? fallback;
}

int? _intOrNull(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString().trim());
}

Map<String, dynamic>? _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : null;

List<dynamic> _list(Object? v) => v is List ? v : const <dynamic>[];

Map<String, dynamic> _sub(Object? v) => _map(v) ?? const <String, dynamic>{};

// ─── 数据类型 ───────────────────────────────────────────────────────────────

/// 音频流信息（从 playurl 接口解析得到）
class AudioStreamInfo {
  /// 音频流直链 URL
  final String url;

  /// 音质 ID（Bilibili qn 值：0=125kbps, 16=16kbps, 32=32kbps, 64=64kbps, 80=80kbps, 116=Hi-Res）
  final int qualityId;

  /// 编解码器（mp4a / flac / eac3 等）
  final String codec;

  /// 码率（bps）。实测**档位 id 与音质无单调关系**，音质高低只能靠该值排序
  final int bandwidth;

  /// MIME 类型（如 audio/mp4、audio/flac）
  final String? mimeType;

  /// URL 过期时间戳（秒），null 表示不过期
  final int? expireTimestamp;

  /// 备用域名列表
  final List<String> backupUrls;

  const AudioStreamInfo({
    required this.url,
    required this.qualityId,
    required this.codec,
    this.bandwidth = 0,
    this.mimeType,
    this.expireTimestamp,
    this.backupUrls = const [],
  });

  factory AudioStreamInfo.fromJson(Map<String, dynamic> json) {
    // Bilibili DASH audio[] 实际字段：baseUrl / backupUrl / mimeType / codecs
    // 兼容部分接口返回的 url / base_url / codecid
    final backup = json['backupUrl'] ?? json['backup_url'];
    return AudioStreamInfo(
      url:
          (json['baseUrl'] ?? json['base_url'] ?? json['url'] ?? '').toString(),
      qualityId: _int(json['id']),
      codec: (json['codecs'] ?? json['codec'] ?? 'mp4a').toString(),
      bandwidth: _int(json['bandwidth']),
      mimeType: _strOrNull(json['mimeType'] ?? json['mime_type']),
      expireTimestamp: _intOrNull(json['deadline']),
      backupUrls: _list(backup).map((e) => e.toString()).toList(),
    );
  }
}

/// 视频元数据
class VideoMeta {
  /// BV 号
  final String bvid;

  /// 视频标题
  final String title;

  /// UP 主昵称
  final String uploaderName;

  /// UP 主 mid
  final int uploaderMid;

  /// 封面缩略图 URL
  final String thumbnailUrl;

  /// 歌词（视频通常无歌词，null 表示无）
  final String? lyric;

  /// 播放次数
  final int playCount;

  /// 视频时长（秒）
  final int duration;

  /// 分 P 列表
  final List<VideoPage> pages;

  const VideoMeta({
    required this.bvid,
    required this.title,
    required this.uploaderName,
    required this.uploaderMid,
    required this.thumbnailUrl,
    this.lyric,
    this.playCount = 0,
    this.duration = 0,
    this.pages = const [],
  });

  factory VideoMeta.fromJson(Map<String, dynamic> json) {
    final pages = _list(json['pages'])
        .whereType<Map<String, dynamic>>()
        .map(VideoPage.fromJson)
        .toList();
    final owner = _sub(json['owner']);
    final stat = _sub(json['stat']);
    return VideoMeta(
      bvid: _str(json['bvid']),
      title: _str(json['title']),
      uploaderName: _str(owner['name']),
      uploaderMid: _int(owner['mid']),
      thumbnailUrl: _str(json['pic']),
      playCount: _int(stat['view']),
      duration: _int(json['duration']),
      pages: pages,
    );
  }
}

/// 视频分 P 信息
class VideoPage {
  final int cid;
  final int page;
  final String part;
  final int duration;

  const VideoPage({
    required this.cid,
    required this.page,
    required this.part,
    required this.duration,
  });

  factory VideoPage.fromJson(Map<String, dynamic> json) {
    return VideoPage(
      cid: _int(json['cid']),
      page: _int(json['page'], 1),
      part: _str(json['part']),
      duration: _int(json['duration']),
    );
  }
}

// ─── API 类 ─────────────────────────────────────────────────────────────────

/// Bilibili 视频 / 音频流 API 封装
class BiliVideo {
  final Dio _dio;

  /// playurl 接口地址
  static const String _playurl = 'https://api.bilibili.com/x/player/playurl';

  /// 视频播放页前缀（playurl 需要带 Referer，否则易触发 403 风控）
  static const String _watchPrefix = 'https://www.bilibili.com/video/';

  /// Hi-Res FLAC 档位 id（存在于 `dash.flac.audio`，不在 `dash.audio[]` 里）
  static const int hiResQualityId = 30251;

  /// web-interface/view 视频元数据接口地址
  static const String _viewUrl =
      'https://api.bilibili.com/x/web-interface/view';

  /// pagelist 分 P 列表接口地址
  static const String _pageListUrl =
      'https://api.bilibili.com/x/player/pagelist';

  /// WBI 密钥缓存（有效期 10 分钟，减少重复请求）
  WbiKeys? _wbiCache;
  DateTime? _wbiCacheTime;

  BiliVideo(this._dio);

  /// 清空 WBI 密钥缓存（登录态变化后重新取密钥）
  void clearWbiCache() {
    _wbiCache = null;
    _wbiCacheTime = null;
  }

  /// 获取带缓存的 WBI 密钥
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

  /// 获取视频音频流 URL（根据 Hi-Res 开关选择音质）
  ///
  /// 接口：GET https://api.bilibili.com/x/player/playurl
  /// 参数：bvid, cid, **fnval=4048**, fourk=1
  ///
  /// fnval 位掩码（实测）：
  ///   * `16`  = DASH（必需，否则无独立音频流）
  ///   * `4048` = 16+64+128+256+512+1024+2048，额外下发 `dash.flac`（Hi-Res）
  ///     与 `dash.dolby`（杜比全景声），为 `16` 的超集 —— 本实现固定使用 4048
  ///   * `112` / `4064` 会被接口判为非法参数，直接返回 `code=-400`
  ///
  /// 音频档位分布（实测，需大会员）：
  ///   * `dash.audio[]`：仅 30216 / 30232 / 30280，**永不出现 30251**
  ///   * `dash.flac.audio`：**Hi-Res 30251（codecs=fLaC）在这里**，
  ///     且仅当 `dash.flac.display == true` 时该曲目真的有 Hi-Res 源
  ///   * `dash.dolby.audio`：杜比轨（可能是数组，也可能是单对象）
  ///
  /// **不可按 qualityId 数值排序判定音质**（30280 的 id 大于 30251，但它是
  /// 171kbps 的 AAC；30216 在部分曲目里是 HE-AAC 53kbps）。统一按
  /// `bandwidth` 降序，并把 Hi-Res 单独提到最高优先级。
  ///
  /// [cid] 为 0 时自动拉取第一个分 P 的 cid。
  ///
  /// [onAvailable]（可选）在解析出音频流列表后被调用，回传该曲目
  /// **实际存在的最高 qualityId**（无论 hiResEnabled 选择哪一档），
  /// 供上层判断当前曲目是否具备 Hi-Res（>= 30251）能力。
  Future<AudioStreamInfo?> getAudioStream(
    String bvid, {
    required int cid,
    required bool hiResEnabled,
    void Function(int maxQualityId)? onAvailable,
  }) async {
    // cid 为 0 时，通过分页接口解析首个有效 cid
    int actualCid = cid;
    if (actualCid == 0) {
      final pages = await getPageList(bvid);
      if (pages.isEmpty) return null;
      actualCid = pages.first.cid;
    }

    // 构建请求参数并进行 WBI 签名
    final rawParams = <String, dynamic>{
      'bvid': bvid,
      'cid': actualCid.toString(),
      'fnval': '4048', // DASH + FLAC(Hi-Res) + Dolby（见方法级注释）
      'fourk': '1',
    };

    Map<String, dynamic> signedParams;
    try {
      final keys = await _getWbiKeys();
      signedParams = WbiSign.sign(rawParams, keys);
    } on Exception {
      // WBI 签名失败时降级为未签名请求（部分账号仍可返回）
      signedParams = rawParams;
    }

    final Response<dynamic> resp;
    try {
      resp = await _dio.get<dynamic>(
        _playurl,
        queryParameters: signedParams,
        options: Options(headers: {'Referer': '$_watchPrefix$bvid'}),
      );
    } on DioException {
      return null;
    }

    final data = resp.data;
    if (data is! Map || data['code'] != 0) return null;
    final d = _map(data['data']);
    if (d == null) return null;

    // 解析 DASH 音频流：audio[] + flac.audio + dolby.audio
    final dash = _map(d['dash']);
    final candidates = <AudioStreamInfo>[];

    void addFrom(Object? raw) {
      if (raw is List) {
        for (final e in raw) {
          addFrom(e);
        }
        return;
      }
      if (raw is! Map) return;
      final info = AudioStreamInfo.fromJson(Map<String, dynamic>.from(raw));
      if (info.url.isEmpty) return;
      // 同一 URL 只保留一条（flac / dolby 常与 audio[] 重复下发）
      if (candidates.any((e) => e.url == info.url)) return;
      candidates.add(info);
    }

    addFrom(dash?['audio']);
    addFrom(_map(dash?['flac'])?['audio']);
    addFrom(_map(dash?['dolby'])?['audio']);

    if (candidates.isEmpty) {
      // 降级：DASH 无音频时尝试 durl（普通 mp4 音频内嵌于视频，无法单独提取）
      onAvailable?.call(0);
      return null;
    }

    bool hiResOf(AudioStreamInfo e) =>
        e.qualityId == hiResQualityId ||
        e.codec.toLowerCase().contains('flac');
    final hiResEntries = candidates.where(hiResOf).toList();

    // 按 bandwidth 降序作为“普通档位”的音质顺序
    final normal = candidates.where((e) => !hiResOf(e)).toList()
      ..sort((a, b) => b.bandwidth.compareTo(a.bandwidth));

    // 上报该曲目实际可用的最高音质：有 Hi-Res 轨即为 30251
    final maxQualityId = hiResEntries.isNotEmpty
        ? hiResQualityId
        : (normal.isNotEmpty ? normal.first.qualityId : candidates.first.qualityId);
    onAvailable?.call(maxQualityId);

    if (hiResEnabled && hiResEntries.isNotEmpty) {
      // Hi-Res 开启：优先返回 30251 / FLAC 轨
      return hiResEntries.first;
    }
    // Hi-Res 关闭（或该曲目无 Hi-Res 轨）：在普通档位里取带宽最高的一档
    if (normal.isNotEmpty) return normal.first;
    return candidates.first;
  }

  /// 获取视频元数据（标题、UP 主、分 P 列表等）
  ///
  /// 接口：GET https://api.bilibili.com/x/web-interface/view?bvid={bvid}
  Future<VideoMeta?> getVideoMeta(String bvid) async {
    try {
      final resp = await _dio.get<dynamic>(
        _viewUrl,
        queryParameters: {'bvid': bvid},
      );
      final data = resp.data;
      if (data is! Map || data['code'] != 0) return null;
      final d = _map(data['data']);
      if (d == null) return null;
      return VideoMeta.fromJson(d);
    } on Exception {
      // 网络 / 解析异常均降级为 null（上层给出可重试提示）
      return null;
    }
  }

  /// 通过 bvid 获取分 P 列表（不依赖视频元数据接口）
  ///
  /// 接口：GET https://api.bilibili.com/x/player/pagelist?bvid={bvid}
  Future<List<VideoPage>> getPageList(String bvid) async {
    try {
      final resp = await _dio.get<dynamic>(
        _pageListUrl,
        queryParameters: {'bvid': bvid},
      );
      final data = resp.data;
      if (data is! Map || data['code'] != 0) return const [];
      final list = _list(data['data']);
      if (list.isEmpty) return const [];
      return list
          .whereType<Map<String, dynamic>>()
          .map(VideoPage.fromJson)
          .toList();
    } on Exception {
      return const [];
    }
  }
}
