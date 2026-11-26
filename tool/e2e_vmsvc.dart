/// TEMP (Task #13 E2E): 通过 flutter run 的 Dart VM Service，在正在运行的
/// Web 应用 isolate 内调用 `BiliAuth.importCookies()`，验证 Web 端
/// Cookie 持久化链路（SecureBox / Hive / IndexedDB）。
///
/// Cookie 只从环境变量 E2E_COOKIE 读取：不写文件、不打印值。
/// 用法：dart run tool/e2e_vmsvc.dart <http://127.0.0.1:PORT/TOKEN=...=>
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final vmUri = args.isNotEmpty ? args.first : '';
  if (vmUri.isEmpty || !vmUri.startsWith('http')) {
    stderr.writeln('usage: e2e_vmsvc.dart <http://127.0.0.1:PORT/TOKEN>');
    exit(64);
  }
  final cookie = (Platform.environment['E2E_COOKIE'] ?? '').trim();
  if (cookie.isEmpty) {
    stderr.writeln('E2E_COOKIE env var is empty');
    exit(65);
  }
  final http = Uri.parse(vmUri);
  final base = http.path.endsWith('/')
      ? http.path.substring(0, http.path.length - 1)
      : http.path;
  final ws = Uri(scheme: 'ws', host: http.host, port: http.port, path: '$base/ws');

  final conn = await WebSocket.connect(ws.toString());
  var seq = 0;
  final pending = <int, Completer<Map<String, dynamic>>>{};
  conn.listen((raw) {
    final msg = jsonDecode(raw as String) as Map<String, dynamic>;
    final id = msg['id'];
    if (id is int) {
      pending.remove(id)?.complete(msg);
    }
  });

  Future<Map<String, dynamic>> rpc(String method, Map<String, dynamic> params) async {
    final id = ++seq;
    final c = Completer<Map<String, dynamic>>();
    pending[id] = c;
    conn.add(jsonEncode({'id': id, 'method': method, 'params': params}));
    return c.future.timeout(const Duration(seconds: 40));
  }

  final vm = await rpc('getVM', <String, dynamic>{});
  final isolates = ((vm['result'] as Map)['isolates'] as List?) ?? const [];
  if (isolates.isEmpty) {
    print('NO_ISOLATE ${jsonEncode(vm)}');
    exit(1);
  }
  final isolateId = (isolates.first as Map)['id'] as String;
  print('ISOLATE $isolateId');

  final iso = await rpc('getIsolate', <String, dynamic>{'isolateId': isolateId});
  final rootLib = ((iso['result'] as Map)['rootLib'] as Map?)?['id'] as String?;
  print('ROOTLIB $rootLib');
  if (rootLib == null) {
    print('NO_ROOTLIB ${_redact(jsonEncode(iso), cookie)}');
    exit(1);
  }

  // 单表达式（DDC evaluate 不支持 await 语句）：用 .then 链触发，
  // 结果通过 app print -> flutter run stdout 输出，本工具只关心副作用。
  final expr = '(() { '
      'final sb = SecureBox(); '
      'final a = BiliAuth(); '
      'return sb.init().then((_) => a.init(sb))'
      '.then((_) => a.importCookies(\'${_esc(cookie)}\'))'
      '.then((ok) => sb.getCookies().then((saved) { '
      "print('E2E_IMPORT ok=\$ok hasSaved=\${a.hasSavedCookies} "
      "names=\${saved?.keys.toList()} n=\${saved?.length}'); "
      'return ok; })) '
      '})();';

  // 注意：dwds 的 evaluate 参数名是 isolateId + targetId（rootLib 的 id），
  // 不支持 targetLib；缺 isolateId 会报 "type 'Null' is not a subtype of String"。
  final res = await rpc('evaluate', <String, dynamic>{
    'isolateId': isolateId,
    'targetId': rootLib,
    'expression': expr,
  });
  final safe = _redact(jsonEncode(res['result'] ?? res['error'] ?? {}), cookie);
  print('EVAL ${safe.length > 400 ? safe.substring(0, 400) : safe}');

  await conn.close();
  exit(0);
}

String _esc(String s) => s.replaceAll('\\', '\\\\').replaceAll("'", r"\'");

String _redact(String text, String secret) {
  var out = text;
  for (final part in secret.split(RegExp(r'[;\s]'))) {
    if (part.length > 8) out = out.replaceAll(part, '<REDACTED>');
  }
  return out;
}
