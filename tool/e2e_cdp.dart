/// E2E helper over Chrome DevTools Protocol (pure Dart, `dart run` OK).
///
/// Commands:
///   dart run tool/e2e_cdp.dart cookie                 # sniff x-proxy-cookie from app requests
///   dart run tool/e2e_cdp.dart shot <path> <out.png> [waitMs] [w] [h]
///   dart run tool/e2e_cdp.dart eval <jsFile> [waitMs]
///   dart run tool/e2e_cdp.dart probe                  # reload and list proxied requests
///
/// The page websocket URL is read from .dart_tool/e2e_ws_url.txt (written by
/// tool/_e2e_chrome.ps1) or discovered from http://127.0.0.1:9222/json.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const String _debugHttp = 'http://127.0.0.1:9222';
const String _appBase = 'http://localhost:7070';
const String _cookieOut = '.dart_tool/e2e_cookie.txt';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: e2e_cdp.dart <cookie|shot|eval|probe> [args]');
    exit(64);
  }
  final cmd = args.first;
  final ws = await _pageWsUrl();
  final cdp = await _Cdp.connect(ws);
  try {
    switch (cmd) {
      case 'cookie':
        await cdp.captureCookie();
      case 'probe':
        await cdp.probe();
      case 'shot':
        final path = args.length > 1 ? args[1] : '/';
        final out = args.length > 2 ? args[2] : 'e2e_shot.png';
        final wait = int.parse(args.length > 3 ? args[3] : '9000');
        final w = int.parse(args.length > 4 ? args[4] : '1100');
        final h = int.parse(args.length > 5 ? args[5] : '1400');
        await cdp.screenshot(path, out, wait, w, h);
      case 'console':
        final path = args.length > 1 ? args[1] : '/';
        final wait = int.parse(args.length > 2 ? args[2] : '25000');
        await cdp.listenConsole(path, wait);
      case 'metrics':
        final w = int.parse(args.length > 1 ? args[1] : '1100');
        final h = int.parse(args.length > 2 ? args[2] : '1500');
        await cdp.send('Emulation.setDeviceMetricsOverride', {
          'width': w,
          'height': h,
          'deviceScaleFactor': 1,
          'mobile': false,
        });
        print('METRICS $w x $h');
      case 'snap':
        final out = args.length > 1 ? args[1] : 'e2e_snap.png';
        final wait = int.parse(args.length > 2 ? args[2] : '2500');
        final sw = int.parse(args.length > 3 ? args[3] : '1100');
        final sh = int.parse(args.length > 4 ? args[4] : '1500');
        await cdp.snap(out, wait, sw, sh);
      case 'listen':
        final wait = int.parse(args.length > 1 ? args[1] : '15000');
        await cdp.listenOnly(wait);
      case 'tap':
        final x = double.parse(args[1]);
        final y = double.parse(args[2]);
        await cdp.tap(x, y);
      case 'tapshot':
        // metrics + tap + capture in one CDP session, so the viewport used to
        // compute the tap coordinates is guaranteed to be the live one.
        final x = double.parse(args[1]);
        final y = double.parse(args[2]);
        final out = args.length > 3 ? args[3] : '.dart_tool/e2e_tap.png';
        final wait = int.parse(args.length > 4 ? args[4] : '8000');
        final w = int.parse(args.length > 5 ? args[5] : '1100');
        final h = int.parse(args.length > 6 ? args[6] : '1500');
        await cdp.tapThenShot(x, y, out, wait, w, h);
      case 'ttapshot':
        // same as tapshot but synthesizes touch events (Flutter Web maps them
        // to pointer events of kind touch), for widgets that ignore the mouse.
        final x = double.parse(args[1]);
        final y = double.parse(args[2]);
        final out = args.length > 3 ? args[3] : '.dart_tool/e2e_ttap.png';
        final wait = int.parse(args.length > 4 ? args[4] : '8000');
        final w = int.parse(args.length > 5 ? args[5] : '1100');
        final h = int.parse(args.length > 6 ? args[6] : '1500');
        await cdp.touchThenShot(x, y, out, wait, w, h);
      case 'typeenv':
        final value = Platform.environment[args.length > 1 ? args[1] : 'E2E_COOKIE'] ?? '';
        await cdp.typeText(value);
      case 'eval':
        final file = File(args[1]);
        final wait = int.parse(args.length > 2 ? args[2] : '60000');
        await cdp.evaluateFile(file, wait);
      case 'wake':
        await cdp.wake();
      case 'inject':
        await cdp.inject();
      case 'restore':
        await cdp.restore();
      case 'shots':
        // batch: one file, lines "<urlPath> <out.png> <w> <h> [waitMs]" (# to
        // comment). Single CDP session, so no per-run dart compile cost.
        final script = File(args[1]);
        for (final raw in script.readAsLinesSync()) {
          final line = raw.trim();
          if (line.isEmpty || line.startsWith('#')) continue;
          final p = line.split(RegExp(r'\s+'));
          final wait = p.length > 4 ? int.parse(p[4]) : 11000;
          await cdp.screenshot(p[0], p[1], wait, int.parse(p[2]), int.parse(p[3]));
        }
      default:
        stderr.writeln('unknown command: $cmd');
    }
  } finally {
    await cdp.close();
  }
}

Future<String> _pageWsUrl() async {
  final f = File('.dart_tool/e2e_ws_url.txt');
  if (f.existsSync()) {
    final first = f.readAsLinesSync().first.trim();
    if (first.startsWith('ws://')) return first;
  }
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse('$_debugHttp/json'));
    final resp = await req.close().timeout(const Duration(seconds: 5));
    final body = await resp.transform(utf8.decoder).join();
    final list = jsonDecode(body) as List<dynamic>;
    for (final t in list.whereType<Map<String, dynamic>>()) {
      if (t['type'] == 'page' && '${t['url']}'.contains('localhost:7070')) {
        return '${t['webSocketDebuggerUrl']}';
      }
    }
    for (final t in list.whereType<Map<String, dynamic>>()) {
      if (t['type'] == 'page') return '${t['webSocketDebuggerUrl']}';
    }
  } finally {
    client.close();
  }
  throw StateError('no CDP page target found');
}

class _Cdp {
  _Cdp(this._ws);

  final WebSocket _ws;
  int _id = 0;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  final List<Map<String, dynamic>> _requests = [];
  final List<String> _console = [];

  static String _formatConsole(String method, Map<String, dynamic>? params) {
    if (params == null) return '';
    if (method == 'Runtime.exceptionThrown') {
      final d = params['exceptionDetails'] as Map<String, dynamic>?;
      final ex = d?['exception'] as Map<String, dynamic>?;
      return 'EXC ${d?['text']} ${ex?['description'] ?? ex?['value']}';
    }
    if (method == 'Log.entryAdded') {
      final e = params['entry'] as Map<String, dynamic>?;
      return '[${e?['level']}] ${e?['source']} ${e?['text']} ${e?['url'] ?? ''}';
    }
    final args = (params['args'] as List? ?? const [])
        .map((a) => '${(a as Map)['value'] ?? a['description'] ?? a['type']}')
        .join(' ');
    return '[${params['type']}] $args';
  }

  static Future<_Cdp> connect(String wsUrl) async {
    final ws = await WebSocket.connect(wsUrl);
    final cdp = _Cdp(ws);
    ws.listen((raw) {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      final id = msg['id'];
      if (id is int && cdp._pending.containsKey(id)) {
        cdp._pending[id]!.complete(msg);
        cdp._pending.remove(id);
        return;
      }
      cdp._onEvent(msg);
    });
    await cdp.send('Page.enable');
    await cdp.send('Network.enable');
    await cdp.send('Runtime.enable');
    return cdp;
  }

  Future<void> close() async => _ws.close();

  void _onEvent(Map<String, dynamic> msg) {
    final method = msg['method'];
    if (method == 'Runtime.consoleAPICalled' ||
        method == 'Runtime.exceptionThrown' ||
        method == 'Log.entryAdded') {
      _console.add(_formatConsole(method!, msg['params'] as Map<String, dynamic>?));
    }
    if (msg['method'] != 'Network.requestWillBeSent') return;
    final params = msg['params'] as Map<String, dynamic>;
    final request = params['request'] as Map<String, dynamic>;
    final url = '${request['url']}';
    if (!url.contains('127.0.0.1:9090')) return;
    final headers = (request['headers'] as Map<String, dynamic>?) ?? {};
    _requests.add({
      'url': url,
      'method': request['method'],
      'cookieHeader': headers['x-proxy-cookie'] ?? headers['X-Proxy-Cookie'],
    });
  }

  Future<Map<String, dynamic>> send(String method,
      [Map<String, dynamic>? params]) async {
    final id = ++_id;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    _ws.add(jsonEncode({
      'id': id,
      'method': method,
      'params': params ?? <String, dynamic>{},
    }));
    return completer.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () => {'timeout': method},
    );
  }

  Future<dynamic> eval(String expression, {bool awaitPromise = true}) async {
    final resp = await send('Runtime.evaluate', {
      'expression': expression,
      'awaitPromise': awaitPromise,
      'returnByValue': true,
    });
    final result = resp['result'] as Map<String, dynamic>?;
    final inner = result?['result'] as Map<String, dynamic>?;
    if (result?['exceptionDetails'] != null) {
      print('EVAL_EXCEPTION: ${jsonEncode(result!['exceptionDetails'])}');
    }
    return inner?['value'];
  }

  Future<void> _waitMs(int ms) => Future<void>.delayed(
        Duration(milliseconds: ms),
      );

  /// Reload the app and grab the x-proxy-cookie the app sends to the proxy.
  Future<void> captureCookie() async {
    await send('Page.navigate', {'url': '$_appBase/'});
    String? cookie;
    for (var i = 0; i < 40 && cookie == null; i++) {
      await _waitMs(500);
      for (final r in _requests) {
        final c = r['cookieHeader'];
        if (c is String && c.contains('SESSDATA')) {
          cookie = c;
          break;
        }
      }
    }
    final namesSeen = <String>{};
    for (final r in _requests) {
      final c = r['cookieHeader'];
      if (c is String) {
        for (final part in c.split(';')) {
          final kv = part.trim();
          final eq = kv.indexOf('=');
          if (eq > 0) namesSeen.add(kv.substring(0, eq));
        }
      }
    }
    print('proxied_requests=${_requests.length}');
    print('cookie_names=${namesSeen.toList()..sort()}');
    if (cookie == null) {
      print('RESULT: NO_SESSDATA (app is not logged in)');
      return;
    }
    File(_cookieOut)
      ..createSync(recursive: true)
      ..writeAsStringSync(cookie, flush: true);
    print('RESULT: SESSDATA_FOUND len=${cookie.length} -> $_cookieOut');
  }

  Future<void> snap(String out, int waitMs, int width, int height) async {
    await send('Emulation.setDeviceMetricsOverride', {
      'width': width,
      'height': height,
      'deviceScaleFactor': 1,
      'mobile': false,
    });
    await _waitMs(waitMs);
    final resp = await send('Page.captureScreenshot', {'format': 'png'});
    final data = (resp['result'] as Map<String, dynamic>?)?['data'] as String?;
    if (data == null) {
      print('SNAP_FAILED');
      return;
    }
    File(out)
      ..createSync(recursive: true)
      ..writeAsBytesSync(base64Decode(data));
    print('SNAP_OK $out href=${await eval('location.href')}');
  }

  Future<void> tap(double x, double y) async {
    await send('Input.dispatchMouseEvent', {
      'type': 'mouseMoved',
      'x': x,
      'y': y,
    });
    await send('Input.dispatchMouseEvent', {
      'type': 'mousePressed',
      'x': x,
      'y': y,
      'button': 'left',
      'clickCount': 1,
      'buttons': 1,
    });
    await send('Input.dispatchMouseEvent', {
      'type': 'mouseReleased',
      'x': x,
      'y': y,
      'button': 'left',
      'clickCount': 1,
      'buttons': 0,
    });
    print('TAP $x,$y');
  }

  Future<void> typeText(String text) async {
    if (text.isEmpty) {
      print('TYPE_SKIP empty (env var missing)');
      return;
    }
    await send('Input.insertText', {'text': text});
    print('TYPE_OK ${text.length} chars');
  }

  Future<void> listenConsole(String path, int waitMs) async {
    await send('Log.enable');
    await send('Page.navigate', {'url': '$_appBase$path'});
    await _waitMs(waitMs);
    print('proxied_requests=${_requests.length}');
    for (final r in _requests) {
      print('REQ ${r['url']} cookie=${r['cookieHeader'] != null}');
    }
    print('--- console (${_console.length}) ---');
    for (final line in _console) {
      if (line.trim().isEmpty) continue;
      print(line.length > 400 ? '${line.substring(0, 400)}...' : line);
    }
    print('href=${await eval('location.href')}');
  }

  /// Listen to console/log events on the *current* page (no navigation), so a
  /// tap-driven interaction can be observed.
  Future<void> listenOnly(int waitMs) async {
    await send('Log.enable');
    final before = _console.length;
    await _waitMs(waitMs);
    print('--- console (+${_console.length - before}) ---');
    for (final line in _console.skip(before)) {
      if (line.trim().isEmpty) continue;
      print(line.length > 400 ? '${line.substring(0, 400)}...' : line);
    }
    print('href=${await eval('location.href')}');
  }

  Future<void> probe() async {
    await send('Page.navigate', {'url': '$_appBase/'});
    await _waitMs(12000);
    for (final r in _requests) {
      print('${r['method']} ${r['url']} cookie=${r['cookieHeader'] != null}');
    }
    print('href=${await eval('location.href')}');
  }

  Future<void> screenshot(
    String path,
    String out,
    int waitMs,
    int width,
    int height,
  ) async {
    await send('Emulation.setDeviceMetricsOverride', {
      'width': width,
      'height': height,
      'deviceScaleFactor': 1,
      'mobile': false,
    });
    await send('Network.setCacheDisabled', {'cacheDisabled': true});
    // Release builds register a service worker; a unique query keeps every
    // e2e run on a fresh document instead of a cached main.dart.js.
    final bust = path.contains('?')
        ? '$path&t=${DateTime.now().millisecondsSinceEpoch}'
        : '$path?t=${DateTime.now().millisecondsSinceEpoch}';
    await send('Page.navigate', {'url': '$_appBase$bust'});
    await _waitMs(waitMs);
    print('href=${await eval('location.href')}');
    final resp = await send('Page.captureScreenshot', {'format': 'png'});
    final data = (resp['result'] as Map<String, dynamic>?)?['data'] as String?;
    if (data == null) {
      print('SHOT_FAILED: ${jsonEncode(resp)}');
      return;
    }
    File(out)
      ..createSync(recursive: true)
      ..writeAsBytesSync(base64Decode(data));
    print('SHOT_OK $out (${data.length} b64 chars)');
  }

  /// Restore / raise the browser window so Chrome stops throttling rAF.
  /// A hidden page produces no Flutter frames, which makes freshly built
  /// FadeIn content look permanently blank in screenshots.
  Future<void> wake() async {
    final info = await send('Target.getTargetInfo');
    final targetId =
        ((info['result'] as Map?)?['targetInfo'] as Map?)?['targetId'];
    final w = await send('Browser.getWindowForTarget', {'targetId': targetId});
    final windowId = (w['result'] as Map?)?['windowId'];
    print('windowId=$windowId bounds=${jsonEncode((w['result'] as Map?)?['bounds'])}');
    if (windowId is int) {
      await send('Browser.setWindowBounds', {
        'windowId': windowId,
        'bounds': {'windowState': 'normal'},
      });
      await send('Browser.setWindowBounds', {
        'windowId': windowId,
        'bounds': {'left': 40, 'top': 40, 'width': 1360, 'height': 1040},
      });
    }
    await send('Page.setWebLifecycleState', {'state': 'active'});
    await send('Page.bringToFront');
    await _waitMs(2000);
    final vis = await eval("document.visibilityState");
    final hid = await eval('document.hidden');
    print('visibility=$vis hidden=$hid');
  }

  Future<void> tapTouch(double x, double y) async {
    await send('Input.dispatchTouchEvent', {
      'type': 'touchStart',
      'touchPoints': [
        {'x': x, 'y': y, 'id': 1}
      ],
    });
    await _waitMs(80);
    await send('Input.dispatchTouchEvent', {
      'type': 'touchEnd',
      'touchPoints': <Map<String, dynamic>>[],
    });
    print('TTAP $x,$y');
  }

  Future<void> touchThenShot(double x, double y, String out, int waitMs,
      int width, int height) async {
    await send('Log.enable');
    await send('Emulation.setDeviceMetricsOverride', {
      'width': width,
      'height': height,
      'deviceScaleFactor': 1,
      'mobile': false,
    });
    await _waitMs(1500);
    print('viewport=${await eval('window.innerWidth + "x" + window.innerHeight')} '
        'view=${await eval('(() => { const r = document.querySelector("flutter-view")?.getBoundingClientRect(); '
            'return r ? Math.round(r.width) + "x" + Math.round(r.height) + "@" + Math.round(r.y) : "none"; })()')}');
    await tapTouch(x, y);
    await _waitMs(waitMs);
    final resp = await send('Page.captureScreenshot', {'format': 'png'});
    final data = (resp['result'] as Map<String, dynamic>?)?['data'] as String?;
    if (data == null) {
      print('TTAPSHOT_FAILED');
    } else {
      File(out)
        ..createSync(recursive: true)
        ..writeAsBytesSync(base64Decode(data));
      print('TTAPSHOT_OK $out base=${await eval('location.href')}');
    }
  }

  Future<void> tapThenShot(double x, double y, String out, int waitMs,
      int width, int height) async {
    await send('Log.enable');
    await send('Emulation.setDeviceMetricsOverride', {
      'width': width,
      'height': height,
      'deviceScaleFactor': 1,
      'mobile': false,
    });
    await _waitMs(1200);
    final vp = await eval('window.innerWidth + "x" + window.innerHeight');
    print('viewport=$vp tap=($x,$y)');
    await tap(x, y);
    await _waitMs(waitMs);
    final resp = await send('Page.captureScreenshot', {'format': 'png'});
    final data = (resp['result'] as Map<String, dynamic>?)?['data'] as String?;
    if (data == null) {
      print('TAPSHOT_FAILED');
    } else {
      File(out)
        ..createSync(recursive: true)
        ..writeAsBytesSync(base64Decode(data));
      print('TAPSHOT_OK $out');
    }
    print('--- console (${_console.length}) ---');
    for (final line in _console) {
      if (line.trim().isEmpty) continue;
      print(line.length > 300 ? '${line.substring(0, 300)}...' : line);
    }
  }

  Future<void> evaluateFile(File jsFile, int waitMs) async {
    final expr = jsFile.readAsStringSync();
    final value = await eval(expr);
    print('EVAL_RESULT: $value');
    if (waitMs > 0 && value == null) {
      await _waitMs(waitMs);
    }
  }

  /// Navigate with ?e2e=<base64url(cookie)> so the app boots through the real
  /// `BiliAuth.importCookies()` path. Cookie value is never printed.
  Future<void> inject() async {
    final cookie = (Platform.environment['E2E_COOKIE'] ?? '').trim();
    if (cookie.isEmpty) {
      print('NO_COOKIE_ENV');
      return;
    }
    final b64 = base64Url.encode(utf8.encode(cookie));
    await send('Emulation.setDeviceMetricsOverride', {
      'width': 1100,
      'height': 1500,
      'deviceScaleFactor': 1,
      'mobile': false,
    });
    // Never serve a stale DDC bundle from the Chrome cache during e2e runs.
    await send('Network.setCacheDisabled', {'cacheDisabled': true});
    // Unique `t` so Chrome always performs a full document reload.
    await send('Page.navigate',
        {'url': '$_appBase/?e2e=$b64&t=${DateTime.now().millisecondsSinceEpoch}'});
    for (var i = 0; i < 60; i++) {
      await _waitMs(1000);
      if (_console.any((l) => l.contains('E2E_INJECT'))) break;
    }
    for (final l in _console.where((l) => l.contains('E2E_'))) {
      print('CONSOLE ${l.length > 700 ? l.substring(0, 700) : l}');
    }
    print('cookieHeaderSeen=${_requests.any((r) => r['cookieHeader'] != null)}'
        ' requests=${_requests.length}');
    for (final r in _requests) {
      final u = Uri.parse('${r['url']}');
      print('REQ ${u.path} cookie=${r['cookieHeader'] != null}');
    }
    print('href=${await eval('location.href')}');
    final resp = await send('Page.captureScreenshot', {'format': 'png'});
    final data = (resp['result'] as Map<String, dynamic>?)?['data'] as String?;
    if (data != null) {
      File('.dart_tool/e2e_inject.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(base64Decode(data));
      print('SHOT_OK .dart_tool/e2e_inject.png');
    }
  }

  /// Reload from a clean URL (no query) to prove the persisted Cookie survives.
  Future<void> restore() async {
    await send('Network.setCacheDisabled', {'cacheDisabled': true});
    await send('Emulation.setDeviceMetricsOverride', {
      'width': 1100,
      'height': 1500,
      'deviceScaleFactor': 1,
      'mobile': false,
    });
    await send('Page.navigate', {'url': '$_appBase/'});
    await _waitMs(20000);
    print('requests=${_requests.length} '
        'withCookie=${_requests.where((r) => r['cookieHeader'] != null).length}');
    final names = <String>{};
    for (final r in _requests) {
      final c = r['cookieHeader'];
      if (c is String) {
        for (final part in c.split(';')) {
          final eq = part.trim().indexOf('=');
          if (eq > 0) names.add(part.trim().substring(0, eq));
        }
      }
    }
    print('cookie_names=${names.toList()..sort()}');
    print('href=${await eval('location.href')}');
    final resp = await send('Page.captureScreenshot', {'format': 'png'});
    final data = (resp['result'] as Map<String, dynamic>?)?['data'] as String?;
    if (data != null) {
      File('.dart_tool/e2e_restore.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(base64Decode(data));
      print('SHOT_OK .dart_tool/e2e_restore.png');
    }
  }
}
