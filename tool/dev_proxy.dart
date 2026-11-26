/// Bilibili 本地开发代理（Web 调试专用）。
///
/// 为什么需要它：
/// 1. 浏览器同源策略会拦截 `*.bilibili.com` 的 XHR 响应（CORS）；
/// 2. 即使用 `--disable-web-security` 关掉 CORS，`Referer` / `Origin` / `Cookie`
///    属于 forbidden headers，JS 无法设置，Bilibili 风控会直接返回 403 HTML；
/// 3. 浏览器也永远不把 `Set-Cookie` 暴露给 JS，前端拿不到 SESSDATA。
///
/// 本代理用 dart:io（不受浏览器限制）转发请求，并约定：
///   URL：https://<host>/<path>  →  http://127.0.0.1:9090/p/<host>/<path>
///   上行 Cookie：请求头 `x-proxy-cookie: NAME=VAL; ...` → 真实 `Cookie` 头
///   上行 Referer/Origin/UA：`x-proxy-referer` / `x-proxy-origin` / `x-proxy-user-agent`
///   下行 Set-Cookie：响应头 `x-proxy-set-cookie`（多条用 `|||` 连接，可被 JS 读取）
///
/// 启动：
///   dart run tool/dev_proxy.dart [--port 9090]
/// 配合（Web 构建默认将 127.0.0.1:9090 作为代理地址，无需额外参数）：
///   flutter run -d chrome --web-port=7070
///   flutter run -d chrome --dart-define=DEV_PROXY_BASE=http://127.0.0.1:8899
library;

import 'dart:io';
import 'dart:typed_data';

/// 允许转发的上游域名后缀（白名单，防止代理被当作任意 URL 的跳板）
const List<String> _allowedSuffixes = <String>[
  '.bilibili.com',
  '.hdslb.com',
  '.bilivideo.com',
];

/// 不向上游转发的请求头（hop-by-hop 或由代理自行管理）
const Set<String> _skipRequestHeaders = <String>{
  'host',
  'connection',
  'keep-alive',
  'proxy-authorization',
  'te',
  'trailer',
  'transfer-encoding',
  'upgrade',
  'content-length',
  'accept-encoding', // 交给 dart:io 自行处理，自动解压 gzip
  'cookie', // 由 x-proxy-cookie 还原
  'referer', // 由 x-proxy-referer 还原
  'origin', // 由 x-proxy-origin 还原
  'user-agent', // 由 x-proxy-user-agent 还原
  'x-proxy-cookie',
  'x-proxy-referer',
  'x-proxy-origin',
  'x-proxy-user-agent',
  'sec-ch-ua',
  'sec-ch-ua-mobile',
  'sec-ch-ua-platform',
  'sec-fetch-dest',
  'sec-fetch-mode',
  'sec-fetch-site',
};

/// 不回传给前端的响应头
const Set<String> _skipResponseHeaders = <String>{
  'transfer-encoding',
  'connection',
  'keep-alive',
  'content-encoding',
  'content-length',
  'set-cookie', // 复制为 x-proxy-set-cookie 后再回传
  // 上游自带的 CORS 头会与本代理冲突（如 ACAO 指向 bilibili），一律丢弃，
  // 由 _writeCors 统一按前端 Origin 重写
  'access-control-allow-origin',
  'access-control-allow-credentials',
  'access-control-allow-methods',
  'access-control-allow-headers',
  'access-control-expose-headers',
  'access-control-max-age',
};

/// 浏览器 XHR 无法读取 Set-Cookie，改用自定义头承载（多条用 `|||` 连接）
const String _setCookieProxyHeader = 'x-proxy-set-cookie';

const String _defaultReferer = 'https://www.bilibili.com';
const String _defaultUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

Future<void> main(List<String> args) async {
  final port = int.tryParse(_flag(args, '--port') ?? '') ??
      int.tryParse(Platform.environment['DEV_PROXY_PORT'] ?? '') ??
      9090;

  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..userAgent = null; // 允许逐请求覆盖 UA

  HttpServer server;
  try {
    // 仅监听回环地址：不触发防火墙提示，也不对外暴露代理
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  } on SocketException catch (e) {
    stderr.writeln('[dev-proxy] 端口 $port 绑定失败：$e');
    stderr.writeln('[dev-proxy] 请换端口：dart run tool/dev_proxy.dart --port 9099');
    exit(1);
  }

  stdout.writeln('┌──────────────────────────────────────────────────────┐');
  stdout.writeln('│  Bilibili Dev Proxy                                  │');
  stdout.writeln('│  http://127.0.0.1:$port/p/<host>/<path>                │');
  stdout.writeln('│  白名单：${_allowedSuffixes.join(', ')}');
  stdout.writeln('│  Ctrl+C 退出                                          │');
  stdout.writeln('└──────────────────────────────────────────────────────┘');

  // 并发处理请求（扫码轮询会持续占用连接，不能串行 await）
  server.listen((req) => _handle(client, req));
}

Future<void> _handle(HttpClient client, HttpRequest req) async {
  final started = DateTime.now();
  try {
    // ── CORS 预检 ──────────────────────────────────────────────────────────
    if (req.method == 'OPTIONS') {
      _writeCors(req.response, req: req);
      req.response.statusCode = HttpStatus.noContent;
      await req.response.close();
      return;
    }

    if (req.uri.path == '/' || req.uri.path == '/health') {
      _writeCors(req.response, req: req);
      req.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write('{"code":0,"message":"dev-proxy alive","proxy":"bilibili"}');
      await req.response.close();
      return;
    }

    // ── 解析 /p/<host>/<path> ──────────────────────────────────────────────
    final segments = req.uri.pathSegments;
    if (segments.length < 2 || segments.first != 'p') {
      await _errorJson(req, HttpStatus.badRequest,
          '路径格式应为 /p/<host>/<path>，收到 ${req.uri.path}');
      return;
    }
    final upstreamHost = segments[1];
    if (!_isAllowedHost(upstreamHost)) {
      await _errorJson(req, HttpStatus.forbidden,
          '域名不在白名单内：$upstreamHost');
      return;
    }
    final upstreamPath = segments.skip(2).join('/');
    final target = Uri(
      scheme: 'https',
      host: upstreamHost,
      path: upstreamPath.isEmpty ? '/' : '/$upstreamPath',
      query: req.uri.hasQuery ? req.uri.query : null,
    );

    // ── 转发请求 ───────────────────────────────────────────────────────────
    final body = await _readBody(req);
    final forwardedCookie = _incoming(req, 'x-proxy-cookie');
    final httpReq = await client.openUrl(
      req.method,
      target,
    );
    _applyUpstreamHeaders(httpReq, req, target);

    if (body.isNotEmpty) {
      httpReq.headers.contentLength = body.length;
      httpReq.add(body);
    } else {
      httpReq.headers.contentLength = 0;
    }

    final httpResp = await httpReq.close().timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw const SocketException('上游超时'),
        );

    // ── 回传响应 ───────────────────────────────────────────────────────────
    final respHeaders = <String, String>{};
    httpResp.headers.forEach((name, values) {
      if (_skipResponseHeaders.contains(name.toLowerCase())) return;
      respHeaders[name] = values.join(', ');
    });
    final setCookies = httpResp.headers['set-cookie'];
    final respBody = await _collect(httpResp);

    _writeCors(req.response, req: req);
    for (final e in respHeaders.entries) {
      req.response.headers.set(e.key, e.value);
    }
    if (setCookies != null && setCookies.isNotEmpty) {
      // 单条自定义头，避免浏览器把多值折叠成逗号串后与 Expires 内的逗号冲突
      req.response.headers.set(_setCookieProxyHeader, setCookies.join('|||'));
      // 同时保留原始 Set-Cookie（同域调试时浏览器仍可用）
      for (final sc in setCookies) {
        req.response.headers.add('set-cookie', sc);
      }
    }
    req.response.statusCode = httpResp.statusCode;
    req.response.add(respBody);
    await req.response.close();

    _log(req.method, target, httpResp.statusCode, respBody.length, started,
        cookie: forwardedCookie, hasSetCookie: setCookies != null && setCookies.isNotEmpty);
  } catch (e, st) {
    stderr.writeln('[dev-proxy] 处理失败 ${req.method} ${req.uri}: $e');
    if (!e.toString().contains('SocketException')) stderr.writeln(st);
    try {
      // 若响应已发出则写入会抛错，忽略即可
      await _errorJson(req, HttpStatus.badGateway, '代理转发失败：$e');
    } catch (_) {}
  }
}

/// 读取请求体（GET 时为空）
Future<Uint8List> _readBody(HttpRequest req) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in req) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

Future<Uint8List> _collect(HttpClientResponse resp) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in resp) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

/// 构造发往上游的请求头：还原浏览器无法设置的 Referer / Origin / Cookie / UA
void _applyUpstreamHeaders(
  HttpClientRequest httpReq,
  HttpRequest req,
  Uri target,
) {
  final headers = httpReq.headers;

  // 透传其余请求头
  req.headers.forEach((name, values) {
    final lower = name.toLowerCase();
    if (_skipRequestHeaders.contains(lower)) return;
    try {
      headers.add(name, values.join(', '));
    } on Exception {
      // 个别受限头 dart:io 不允许设置，忽略即可
    }
  });

  headers.set(
    'Referer',
    _incoming(req, 'x-proxy-referer') ?? _defaultReferer,
  );
  headers.set(
    'Origin',
    _incoming(req, 'x-proxy-origin') ?? 'https://${target.host}',
  );
  headers.set(
    'User-Agent',
    _incoming(req, 'x-proxy-user-agent') ?? _defaultUserAgent,
  );

  final cookie = _incoming(req, 'x-proxy-cookie');
  if (cookie != null && cookie.isNotEmpty) {
    headers.set(HttpHeaders.cookieHeader, cookie);
  }

  if (headers.value(HttpHeaders.acceptHeader) == null) {
    headers.set(HttpHeaders.acceptHeader, 'application/json, text/plain, */*');
  }
}

String? _incoming(HttpRequest req, String name) {
  final values = req.headers[name];
  if (values == null || values.isEmpty) return null;
  return values.join('; ');
}

bool _isAllowedHost(String host) {
  final lower = host.toLowerCase();
  for (final suffix in _allowedSuffixes) {
    if (lower.endsWith(suffix) || lower == suffix.substring(1)) return true;
  }
  return false;
}

/// 统一附加 CORS 头，使前端可跨端口读取响应（含 x-proxy-set-cookie）
void _writeCors(HttpResponse resp, {required HttpRequest req}) {
  final origin = req.headers.value('origin') ?? '*';
  final requested = req.headers.value('access-control-request-headers');
  final headers = resp.headers;
  headers.set('Access-Control-Allow-Origin', origin);
  headers.set(
    'Access-Control-Allow-Methods',
    'GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS',
  );
  headers.set(
    'Access-Control-Allow-Headers',
    (requested != null && requested.isNotEmpty) ? requested : '*',
  );
  headers.set(
    'Access-Control-Expose-Headers',
    '$_setCookieProxyHeader, content-type, x-request-id',
  );
  headers.set('Access-Control-Max-Age', '86400');
  headers.add('Vary', 'Origin, Access-Control-Request-Headers');
}

Future<void> _errorJson(HttpRequest req, int status, String message) async {
  _writeCors(req.response, req: req);
  req.response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write('{"code":$status,"message":${_jsonString(message)},"data":null}');
  await req.response.close();
  _log(req.method, req.uri, status, 0, DateTime.now());
}

String _jsonString(String value) =>
    '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', ' ')}"';

void _log(
  String method,
  Uri target,
  int status,
  int bytes,
  DateTime started, {
  String? cookie,
  bool hasSetCookie = false,
}) {
  final ms = DateTime.now().difference(started).inMilliseconds;
  final flags = <String>[
    if (cookie != null && cookie.isNotEmpty) '↑cookie(${cookie.length}B)',
    if (hasSetCookie) '↓set-cookie',
  ].join(' ');
  stdout.writeln(
    '[dev-proxy] ${TimeStamp.format(DateTime.now())} $method '
    '${target.host}${target.path} → $status (${bytes}B, ${ms}ms)'
    '${flags.isEmpty ? '' : '  [$flags]'}',
  );
}

/// 极简时间戳（避免引入 intl）
class TimeStamp {
  static String format(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}

String? _flag(List<String> args, String name) {
  final i = args.indexOf(name);
  if (i >= 0 && i + 1 < args.length) return args[i + 1];
  final prefix = '$name=';
  for (final a in args) {
    if (a.startsWith(prefix)) return a.substring(prefix.length);
  }
  return null;
}
