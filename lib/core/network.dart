/// Dio 网络层基础配置
/// 统一 User-Agent、Referer、Cookie 管理及错误拦截
library;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'web_proxy.dart';

class NetworkClient {
  NetworkClient._();

  /// Bilibili Web 端 User-Agent（伪装 Chrome）
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

  /// 默认 Referer
  static const String _referer = 'https://www.bilibili.com';

  /// 请求超时（毫秒）
  static const int _connectTimeout = 15000;
  static const int _receiveTimeout = 15000;
  static const int _sendTimeout = 10000;

  /// 创建带 Cookie 管理的 Dio 实例
  ///
  /// [cookieJar] 用于持久化 Cookie 的存储容器
  static Dio createDio(CookieJar cookieJar) {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(milliseconds: _connectTimeout),
        receiveTimeout: const Duration(milliseconds: _receiveTimeout),
        sendTimeout: const Duration(milliseconds: _sendTimeout),
        headers: {
          'User-Agent': _userAgent,
          'Referer': _referer,
          'Origin': 'https://www.bilibili.com',
          'Accept': 'application/json, text/plain, */*',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        },
        responseType: ResponseType.json,
      ),
    );

    // Cookie 管理器拦截器 — 自动维护 Cookie
    // Web 端使用浏览器原生 Cookie 机制，不支持也不需 CookieManager
    if (!kIsWeb) {
      dio.interceptors.add(CookieManager(cookieJar));
    }

    // Web 调试代理拦截器 — 绕过 CORS + 补齐 Referer/Cookie（见 tool/dev_proxy.dart）
    // Web 构建默认走 `http://127.0.0.1:9090`（可用 `--dart-define=DEV_PROXY_BASE=`
    // 改地址或置 `off` 关闭）；Android / iOS 构建下 [WebProxy.enabled] 恒为 false，零影响。
    if (WebProxy.enabled) {
      dio.interceptors.add(WebProxyInterceptor(cookieJar));
    }

    // 错误日志拦截器
    dio.interceptors.add(
      InterceptorsWrapper(
        onError: (DioException e, ErrorInterceptorHandler handler) {
          // 可在此添加重试逻辑（如 412 频率限制时退避重试）
          handler.next(e);
        },
      ),
    );

    return dio;
  }

  /// 创建专用于 passport.bilibili.com 登录的 Dio 实例
  /// 登录接口需要不同的 Referer
  static Dio createLoginDio(CookieJar cookieJar) {
    final dio = createDio(cookieJar);
    dio.options.headers['Referer'] = 'https://passport.bilibili.com';
    dio.options.headers['Origin'] = 'https://passport.bilibili.com';
    return dio;
  }

  /// 解析 Cookie 字符串为 Map
  /// 格式："SESSDATA=xxx; bili_jct=yyy; DedeUserID=zzz"
  static Map<String, String> parseCookieString(String raw) {
    final result = <String, String>{};
    for (final part in raw.split(RegExp(r'[;\n]'))) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final eqIdx = trimmed.indexOf('=');
      if (eqIdx == -1) continue;
      final key = trimmed.substring(0, eqIdx).trim();
      final value = trimmed.substring(eqIdx + 1).trim();
      if (key.isNotEmpty) {
        result[key] = value;
      }
    }
    return result;
  }

  /// 将 Cookie Map 序列化为字符串
  static String cookiesToString(Map<String, String> cookies) {
    return cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }
}
