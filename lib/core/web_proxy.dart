/// Web 端本地开发代理（dev proxy）支持。
///
/// 浏览器环境下 Bilibili 接口无法直连：
/// 1. 同源策略拦截响应（CORS）；
/// 2. `Referer` / `Origin` / `Cookie` 是 forbidden headers，JS 设置无效，
///    即使加 `--disable-web-security` 绕过 CORS，Bilibili 仍会因缺少 Referer
///    返回 403 风控页；
/// 3. `Set-Cookie` 永远不会暴露给 JS，前端拿不到 SESSDATA。
///
/// 因此 Web 调试时把所有 `*.bilibili.com` / `*.hdslb.com` 请求改走本地代理
/// （`tool/dev_proxy.dart`），约定：
///   `https://passport.bilibili.com/x/...`
///     → `http://127.0.0.1:9090/p/passport.bilibili.com/x/...`
///   上行 Cookie  → `x-proxy-cookie`
///   下行 Cookie  → `x-proxy-set-cookie`（多条以 `|||` 连接）
///   Referer/Origin/UA → `x-proxy-referer` / `x-proxy-origin` / `x-proxy-user-agent`
///
/// 启用方式（仅 Web 需要，Android/iOS 完全不受影响）：
///   dart run tool/dev_proxy.dart --port 9090
///   flutter run -d chrome --web-port=7070
///
/// Web 构建下默认启用（地址 `http://127.0.0.1:9090`），无需额外参数；
/// 可用 `--dart-define=DEV_PROXY_BASE=http://127.0.0.1:8899` 改端口，
/// 或 `--dart-define=DEV_PROXY_BASE=off` 强制关闭（直连，会被 CORS 拦）。
library;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// 代理配置与 URL 重写
class WebProxy {
  WebProxy._();

  /// 编译期注入的代理地址；未注入时 Web 端使用默认地址，
  /// 显式传入 `off` / `none` / `disable` 则关闭代理（直连）。
  static const String _configuredBase =
      String.fromEnvironment('DEV_PROXY_BASE');

  /// Web 端未指定 DEV_PROXY_BASE 时的默认代理地址（与 tool/dev_proxy.dart 默认端口一致）
  static const String _defaultBase = 'http://127.0.0.1:9090';

  /// 显式关闭代理的取值
  static const Set<String> _offValues = {
    'off',
    'none',
    'false',
    'disable',
    'disabled',
    '0'
  };

  /// 实际生效的代理根地址（空串表示不代理）
  static final String _baseUrl = _resolveBase();

  static String _resolveBase() {
    final cfg = _configuredBase.trim();
    if (cfg.isEmpty) return _defaultBase;
    if (_offValues.contains(cfg.toLowerCase())) return '';
    return cfg.endsWith('/') ? cfg.substring(0, cfg.length - 1) : cfg;
  }

  /// 上行 Cookie 头
  static const String cookieUpHeader = 'x-proxy-cookie';

  /// 下行 Set-Cookie 头
  static const String setCookieDownHeader = 'x-proxy-set-cookie';

  /// 多条 Set-Cookie 的分隔符（Cookie 值内不会出现）
  static const String setCookieSeparator = '|||';

  static const String refererHeader = 'x-proxy-referer';
  static const String originHeader = 'x-proxy-origin';
  static const String userAgentHeader = 'x-proxy-user-agent';

  /// 需要走代理的域名后缀（含音频 CDN `*.bilivideo.com`）
  static const List<String> _allowedSuffixes = <String>[
    '.bilibili.com',
    '.hdslb.com',
    '.bilivideo.com',
  ];

  /// 当前构建是否启用代理
  ///
  /// 仅 Web 生效；Android / iOS / 桌面原生构建恒为 false，零影响。
  static bool get enabled => kIsWeb && _baseUrl.isNotEmpty;

  /// 代理根地址，例如 `http://127.0.0.1:9090`
  static String get baseUrl => _baseUrl;

  /// 该主机是否需要代理
  static bool isProxiedHost(String host) {
    final lower = host.toLowerCase();
    return _allowedSuffixes.any((s) => lower.endsWith(s));
  }

  /// `https://host/path` → `http://127.0.0.1:9090/p/host/path`
  ///
  /// 返回 null 表示该 URL 无需代理。原 URL 内联的 query 会原样保留
  /// （Dio 之后仍会追加 `queryParameters`，行为与直连一致）。
  static String? rewriteUrl(String url) {
    if (!enabled) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || !isProxiedHost(uri.host)) return null;
    final rewritten = '$_baseUrl/p/${uri.host}${uri.path}';
    return uri.hasQuery ? '$rewritten?${uri.query}' : rewritten;
  }

  /// 给**非 Dio** 的图片加载（`Image.network` / `CachedNetworkImage`）用的地址。
  ///
  /// 浏览器加载 `<img>` 时不会带上任何自定义头，也无法绕过 CDN 的 CORS /
  /// 防盗链，因此 `i0.hdslb.com` 一类的封面在 Web 调试时会直接加载失败
  /// （表现为所有封面都是占位图标）。改走 dev_proxy 后由代理补 Referer 并
  /// 回 `Access-Control-Allow-Origin`，图片才能正常显示。
  static String imageUrl(String url) => rewriteUrl(url) ?? url;
}

/// 让 Dio 在 Web 上经由 dev proxy 收发 Bilibili 请求，并与 [CookieJar] 双向同步。
///
/// 业务层（`auth.dart` / `music.dart` / `video.dart`）无需任何改动：
/// 它们照常写真实的 Bilibili URL、照常设置 Referer/Origin、照常从
/// `CookieJar` 读取 Cookie，本拦截器负责把它们翻译成代理约定。
class WebProxyInterceptor extends Interceptor {
  WebProxyInterceptor(this._cookieJar);

  final CookieJar _cookieJar;

  /// 原始（Bilibili）URI 在 extra 中的键，响应阶段用于按域存 Cookie
  static const String _originalUriKey = 'webProxyOriginalUri';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _onRequest(options, handler);
  }

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final original = options.uri;
    final absolute = options.path.startsWith('http')
        ? options.path
        : '${options.baseUrl}${options.path}';
    final proxied = WebProxy.rewriteUrl(absolute);
    if (!WebProxy.enabled || proxied == null) {
      handler.next(options);
      return;
    }
    options.extra[_originalUriKey] = original;

    // Referer / Origin / User-Agent：浏览器会静默丢弃这些头，改由自定义头上行
    options.headers[WebProxy.refererHeader] =
        options.headers['Referer'] ?? 'https://www.bilibili.com';
    options.headers[WebProxy.originHeader] =
        options.headers['Origin'] ?? 'https://www.bilibili.com';
    final ua = options.headers['User-Agent'];
    if (ua is String && ua.isNotEmpty) {
      options.headers[WebProxy.userAgentHeader] = ua;
    }
    // 复制完成后必须删掉原始头：XHR 对 forbidden headers 会直接报
    // `Refused to set unsafe header "User-Agent"/"Referer"/"Origin"`，
    // 每个请求刷 3 条控制台错误（功能不受影响，但日志完全不可读）。
    options.headers.remove('Referer');
    options.headers.remove('Origin');
    options.headers.remove('User-Agent');

    // Cookie：浏览器禁止 JS 设置，改为自定义头
    try {
      final cookies = await _cookieJar.loadForRequest(original);
      if (cookies.isNotEmpty) {
        options.headers[WebProxy.cookieUpHeader] =
            cookies.map((c) => '${c.name}=${c.value}').join('; ');
      }
    } catch (_) {
      // Cookie 读取失败不影响请求本身
    }

    // Dio 的 RequestOptions.uri 是只读派生属性，改写 path 即可切换目标地址
    // （path 以 "http" 开头时 baseUrl 会被忽略）
    options.baseUrl = '';
    options.path = proxied;
    handler.next(options);
  }

  @override
  void onResponse(
      Response<dynamic> response, ResponseInterceptorHandler handler) {
    _onResponse(response, handler);
  }

  Future<void> _onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) async {
    final original = response.requestOptions.extra[_originalUriKey];
    final raw = response.headers[WebProxy.setCookieDownHeader];
    if (original is Uri && raw != null && raw.isNotEmpty) {
      final cookies = <Cookie>[];
      for (final item in raw
          .join(WebProxy.setCookieSeparator)
          .split(WebProxy.setCookieSeparator)) {
        final value = item.trim();
        if (value.isEmpty) continue;
        try {
          cookies.add(Cookie.fromSetCookieValue(value));
        } catch (_) {
          final parsed = _parseLoose(value);
          if (parsed != null) cookies.add(parsed);
        }
      }
      if (cookies.isNotEmpty) {
        try {
          await _cookieJar.saveFromResponse(original, cookies);
        } catch (_) {
          // 存储失败时保持原响应透传
        }
      }
    }
    handler.next(response);
  }

  /// 宽松解析 `name=value; Attr` —— 用于 `Cookie.fromSetCookieValue` 抛异常时兜底
  static Cookie? _parseLoose(String setCookieValue) {
    final parts = setCookieValue.split(';');
    final nameValue = parts.first;
    final eq = nameValue.indexOf('=');
    if (eq <= 0) return null;
    final cookie = Cookie(
      nameValue.substring(0, eq).trim(),
      nameValue.substring(eq + 1).trim(),
    )..path = '/';
    for (final attr in parts.skip(1)) {
      final kv = attr.trim();
      final sep = kv.indexOf('=');
      final key = (sep == -1 ? kv : kv.substring(0, sep)).trim().toLowerCase();
      final val = sep == -1 ? '' : kv.substring(sep + 1).trim();
      switch (key) {
        case 'domain':
          if (val.isNotEmpty) cookie.domain = val;
        case 'path':
          if (val.isNotEmpty) cookie.path = val;
        case 'max-age':
          cookie.maxAge = int.tryParse(val);
        case 'secure':
          cookie.secure = true;
      }
    }
    return cookie;
  }
}
