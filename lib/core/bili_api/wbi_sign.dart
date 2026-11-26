/// Bilibili WBI 签名算法
/// 用于生成 w_rid 和 wts 参数，是 Bilibili Web API 的反爬签名机制
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

/// WBI 密钥对（从 nav 接口 wbi_img 字段提取）
class WbiKeys {
  /// img_key：从 img_url 文件名（去扩展名）提取，通常 32 位十六进制字符串
  final String imgKey;

  /// sub_key：从 sub_url 文件名（去扩展名）提取，通常 32 位十六进制字符串
  final String subKey;

  const WbiKeys({required this.imgKey, required this.subKey});

  @override
  String toString() => 'WbiKeys(imgKey: $imgKey, subKey: $subKey)';
}

/// WBI 密钥获取 / 签名异常
///
/// 必须是 `Exception` 而非 `Error`：业务层（`music.dart` /
/// `recommend.dart`）统一用 `on Exception` 兜底并降级，若抛 `StateError`
/// 则绕过错处理直接冒泡到 Riverpod FutureProvider，UI 显示“加载失败”。
class WbiSignException implements Exception {
  /// 错误描述
  final String message;

  const WbiSignException(this.message);

  @override
  String toString() => 'WbiSignException: $message';
}

/// Bilibili WBI 签名工具
class WbiSign {
  WbiSign._();

  /// 混淆表（固定 64 个下标，取 rawKey[tab[i]] 得 mixinKey 第 i 位）
  static const List<int> _mixinKeyEncTab = [
    46,
    47,
    18,
    2,
    53,
    8,
    23,
    32,
    15,
    50,
    10,
    31,
    58,
    3,
    45,
    35,
    27,
    43,
    5,
    49,
    33,
    9,
    42,
    19,
    29,
    28,
    14,
    39,
    12,
    38,
    41,
    13,
    37,
    48,
    7,
    6,
    24,
    55,
    40,
    61,
    26,
    17,
    54,
    1,
    20,
    51,
    21,
    56,
    30,
    0,
    25,
    52,
    11,
    57,
    4,
    62,
    59,
    44,
    36,
    22,
    60,
    34,
    16,
    63,
  ];

  /// 从 URL 中提取文件名（去掉路径和扩展名）
  /// 例：https://i0.hdslb.com/bfs/wbi/abc123.png → abc123
  static String _extractKeyFromUrl(String url) {
    final filename = url.split('/').last;
    final dotIndex = filename.indexOf('.');
    return dotIndex == -1 ? filename : filename.substring(0, dotIndex);
  }

  /// 通过 imgKey + subKey 计算 mixinKey（32 字符）
  static String _computeMixinKey(WbiKeys keys) {
    final rawKey = keys.imgKey + keys.subKey; // 通常 64 字符
    // 混淆表最大下标 63；密钥异常偏短时直接取值会抛 RangeError（属于 Error，
    // 无法被 `on Exception` 捕获），因此这里提前判定并抛可捕获的异常。
    if (rawKey.length < 64) {
      throw WbiSignException(
        'WBI keys: mixin key source too short (len=${rawKey.length})',
      );
    }
    final buffer = StringBuffer();
    for (var i = 0; i < 32; i++) {
      buffer.write(rawKey[_mixinKeyEncTab[i]]);
    }
    return buffer.toString();
  }

  /// 从 nav 接口获取 WBI 密钥（imgKey / subKey）
  ///
  /// 接口：GET https://api.bilibili.com/x/web-interface/nav
  ///
  /// **响应结构**（务必按此层级取值）：
  /// ```json
  /// {
  ///   "code": 0,            // 未登录时为 -101，不影响 wbi_img 返回
  ///   "message": "0",
  ///   "data": {
  ///     "isLogin": true,
  ///     "wbi_img": { "img_url": "https://i0.hdslb.com/bfs/wbi/xxx.png",
  ///                  "sub_url": "https://i0.hdslb.com/bfs/wbi/yyy.png" }
  ///   }
  /// }
  /// ```
  ///
  /// 两个易踩的坑（曾导致首页“每日推荐 / 热门歌曲”恒显示“加载失败”）：
  /// 1. `wbi_img` 位于 **`data` 内部**，不是响应顶层；
  /// 2. 未登录时 `code == -101` 但 `data.wbi_img` 依然有效，
  ///    因此**不能因为 code != 0 就放弃取密钥**（WBI 密钥本身与登录态无关）。
  static Future<WbiKeys> getWbiKeys(Dio dio) async {
    final response = await dio.get<dynamic>(
      'https://api.bilibili.com/x/web-interface/nav',
    );
    final body = response.data;
    if (body is! Map) {
      throw WbiSignException(
          'WBI keys: unexpected nav response type: ${body.runtimeType}');
    }

    // wbi_img 正常位于 data 之内；兼容极少数把它放在顶层的返回形态
    final payload = body['data'];
    final wbiImg =
        (payload is Map ? payload['wbi_img'] : null) ?? body['wbi_img'];
    if (wbiImg is! Map) {
      throw WbiSignException(
        'WBI keys: wbi_img field missing in nav response '
        '(code=${body['code']}, message=${body['message']})',
      );
    }
    final imgUrl = (wbiImg['img_url'] ?? '').toString();
    final subUrl = (wbiImg['sub_url'] ?? '').toString();
    if (imgUrl.isEmpty || subUrl.isEmpty) {
      throw const WbiSignException('WBI keys: img_url or sub_url is empty');
    }
    return WbiKeys(
      imgKey: _extractKeyFromUrl(imgUrl),
      subKey: _extractKeyFromUrl(subUrl),
    );
  }

  /// 对请求参数进行 WBI 签名，返回附加了 wts 和 w_rid 的新参数 Map
  ///
  /// 算法步骤：
  /// 1. 附加 wts（当前 Unix 时间戳，秒）
  /// 2. 按 key 字典序排序所有参数
  /// 3. 值过滤：去除 `!'()*~` 字符后转字符串
  /// 4. 拼接原始 query string（key=value&...，不做 URL 编码）
  /// 5. 在 query 末尾拼接 mixinKey，对其做 MD5 → w_rid
  /// 6. 返回原始参数 + wts + w_rid
  static Map<String, dynamic> sign(
    Map<String, dynamic> params,
    WbiKeys keys,
  ) {
    final mixinKey = _computeMixinKey(keys);
    final wts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

    // 合并原始参数与 wts
    final allParams = Map<String, dynamic>.from(params)..['wts'] = wts;

    // 按 key 字典序排序
    final sortedKeys = allParams.keys.toList()..sort();

    // 构建原始 query string（不做 URL 编码，直接拼接 key=value）
    // 值过滤：去除 ! ' ( ) * ~ 字符
    final query = sortedKeys.map((key) {
      final rawValue = allParams[key]?.toString() ?? '';
      final filteredValue = rawValue.replaceAll(RegExp(r"[!'()*~]"), '');
      return '$key=$filteredValue';
    }).join('&');

    // MD5(query + mixinKey) → w_rid
    final wRid = _md5Hex('$query$mixinKey');

    return Map<String, dynamic>.from(allParams)..['w_rid'] = wRid;
  }

  /// 便捷方法：一次性获取密钥并签名（适合调用频率不高的场景）
  static Future<Map<String, dynamic>> signWithFetch(
    Dio dio,
    Map<String, dynamic> params,
  ) async {
    final keys = await getWbiKeys(dio);
    return sign(params, keys);
  }

  static String _md5Hex(String input) {
    final bytes = utf8.encode(input);
    final digest = md5.convert(bytes);
    return digest.toString(); // 已经是小写十六进制字符串
  }
}
