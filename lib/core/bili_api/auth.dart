/// Bilibili 扫码登录 & Cookie 管理
library;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dog_sheep_player/core/auth_interceptor.dart';
import 'package:dog_sheep_player/core/network.dart';
import 'package:dog_sheep_player/core/storage/secure_box.dart';
import 'package:encrypt/encrypt.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart' show RSAPublicKey;

// ─── 扫码登录数据类型 ────────────────────────────────────────────────────────

/// generateQrCode 成功返回的数据
class QrLoginResult {
  /// 二维码内容 URL（Bilibili App 扫码后跳转的地址）
  final String url;

  /// 轮询用的 qrcode_key
  final String qrcodeKey;

  const QrLoginResult({required this.url, required this.qrcodeKey});
}

/// 扫码轮询状态枚举
enum QrPollStatus {
  /// 未扫码（code=86101）
  waiting,

  /// 已扫码未确认（code=86090）
  scanned,

  /// 已确认登录（code=0），Cookie 已由 CookieManager 写入 CookieJar
  confirmed,

  /// 二维码已过期（code=86038）
  expired,
}

/// pollQrStatus 返回结果
class QrPollResult {
  final QrPollStatus status;

  /// 仅 [QrPollStatus.confirmed] 时有值
  final Map<String, String>? cookies;

  const QrPollResult({required this.status, this.cookies});
}

/// nav 接口返回的账号简要信息（昵称 / 头像，用于首页问候与设置页）
class BiliProfile {
  final bool isLoggedIn;
  final String? nickname;
  final String? avatarUrl;
  final int mid;

  const BiliProfile({
    required this.isLoggedIn,
    this.nickname,
    this.avatarUrl,
    this.mid = 0,
  });

  /// 未登录 / 请求失败的统一空值
  static const BiliProfile anonymous = BiliProfile(isLoggedIn: false);
}

// ─── 账密登录结果枚举 ────────────────────────────────────────────────────────

enum LoginResult {
  /// 登录成功，Cookie 已获取并存储
  success,

  /// 密码错误（code=-101 或类似）
  wrongPassword,

  /// 需要验证码（code=3 或风控触发）
  needCaptcha,

  /// 网络错误
  networkError,

  /// Cookie 已过期，需重新登录
  cookieExpired,
}

// ─── 核心认证类 ─────────────────────────────────────────────────────────────

/// Bilibili 认证管理器
///
/// 负责：账密登录、Cookie 持久化、登录状态检测、VIP 状态验证、自动重登
class BiliAuth {
  /// 内置手机号
  static const String phone = '13468676878';

  /// Bilibili 登录接口
  static const String _loginUrl =
      'https://passport.bilibili.com/x/passport-login/web/login';

  /// Bilibili RSA 公钥接口
  static const String _publicKeyUrl =
      'https://passport.bilibili.com/x/passport-login/web/key';

  /// Bilibili nav 接口（用于检测登录状态与 VIP）
  static const String _navUrl = 'https://api.bilibili.com/x/web-interface/nav';

  /// 扫码登录——生成二维码
  static const String _qrGenerateUrl =
      'https://passport.bilibili.com/x/passport-login/web/qrcode/generate';

  /// 扫码登录——轮询扫码状态
  static const String _qrPollUrl =
      'https://passport.bilibili.com/x/passport-login/web/qrcode/poll';

  /// 匿名设备指纹接口（公开，无需登录），返回 b_3 / b_4 即 buvid3 / buvid4
  static const String _fingerSpiUrl =
      'https://api.bilibili.com/x/frontend/finger/spi';

  late final Dio _dio;
  late final SecureBox _secureBox;
  late final CookieJar _cookieJar;

  /// Cookie 同步快照（CookieJar.loadForRequest 为异步，对外暴露
  /// 同步 cookies 前先在此缓存最新结果，在登录 / 注入 / 初始化后刷新）
  final Map<String, String> _cookieCache = {};

  bool _initialized = false;

  /// 当前 Cookie（读自内存快照，由 [_refreshCookieCache] 同步）
  Map<String, String> get cookies => Map.unmodifiable(_cookieCache);

  /// 当前 Dio 实例（供其他模块复用）
  Dio get dio => _dio;

  /// 当前 CookieJar（供其他模块复用）
  CookieJar get cookieJar => _cookieJar;

  // ─── 初始化 ──────────────────────────────────────────────────────────────

  /// 初始化 Dio（带 CookieManager 拦截器）并绑定 SecureBox
  ///
  /// 请在 `WidgetsFlutterBinding.ensureInitialized()` 之后调用
  Future<void> init(SecureBox secureBox) async {
    _secureBox = secureBox;

    // Cookie 持久化路径：适配 Android/iOS 应用沙箱；Web 端使用内存 CookieJar
    //
    // **Web 端必须显式用 [DefaultCookieJar]**（2026-11 实测根因）：
    // cookie_jar 4.x 的 `CookieJar()` 工厂在 Web 上返回的是 [WebCookieJar]，
    // 其 `saveFromResponse` 为空实现、`loadForRequest` 恒返回 `[]`（它假定
    // XHR 由浏览器自动管理 Cookie）。本项目 Web 端经 dev_proxy 访问
    // *.bilibili.com，浏览器不会为跨域请求携带 Bilibili Cookie，Cookie 只能
    // 由应用维护并通过 `x-proxy-cookie` 上行 —— 用 `CookieJar()` 会导致
    // importCookies / 扫码登录后的 SESSDATA 全部存不进去，nav 恒返回
    // `code=-101 账号未登录`，刷新后也一样。
    // `ignoreExpires: true` 与原生分支保持一致（B 站部分 Cookie 的
    // Expires 与本机时钟有偏差，否则会被判定过期而丢弃）。
    if (kIsWeb) {
      _cookieJar = DefaultCookieJar(ignoreExpires: true); // 内存存储，关页即失效
    } else {
      final appDir = await getApplicationDocumentsDirectory();
      final cookieDir = '${appDir.path}/.cookies/';
      _cookieJar = PersistCookieJar(
        ignoreExpires: true,
        storage: FileStorage(cookieDir),
      );
    }
    _dio = NetworkClient.createDio(_cookieJar);
    // 注册自动重登拦截器（401/403 → reLogin → 重试原请求）
    _dio.interceptors.add(AuthInterceptor(this));
    _initialized = true;

    // 尝试从 SecureBox 恢复历史 Cookie
    final saved = await secureBox.getCookies();
    if (saved != null && saved.isNotEmpty) {
      await _injectCookies(saved);
    }
    // 建立初始 Cookie 快照
    await _refreshCookieCache();

    // 补齐匿名设备 Cookie（buvid3 / buvid4），降低 Web 接口被风控的概率
    await seedAnonymousCookies();
  }

  /// 播种匿名设备 Cookie（buvid3 / buvid4）。
  ///
  /// B 站对缺少 buvid3 的 Web 请求容易直接返回 HTTP 412（风控），
  /// 首页“每日推荐”（`index/top/rcmd`）尤其敏感，表现为“加载失败”。
  /// 这里用公开的 `finger/spi` 拿到 b_3 / b_4 并写入 CookieJar（顶级域）；
  /// 已有 buvid3 时不做任何事，失败也不影响后续流程。
  Future<void> seedAnonymousCookies() async {
    _ensureInitialized();
    if (_cookieCache.containsKey('buvid3')) return;
    try {
      // 短超时：本方法在 runApp 之前执行，不能因为网络挂死而白屏
      final resp = await _dio.get<dynamic>(
        _fingerSpiUrl,
        options: Options(
          connectTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 4),
        ),
      );
      final body = resp.data;
      if (body is! Map) return;
      final d = body['data'];
      if (d is! Map) return;
      final b3 = (d['b_3'] ?? '').toString();
      final b4 = (d['b_4'] ?? '').toString();
      if (b3.isEmpty) return;
      final seed = <String, String>{'buvid3': b3};
      if (b4.isNotEmpty) seed['buvid4'] = b4;
      await _injectCookies(seed);
      await _refreshCookieCache();
    } on Exception {
      // 网络不可用时静默跳过（登录 / 日常请求会自行下发 Cookie）
    }
  }

  // ─── JSON 宽容取值 ──────────────────────────────────────────────────────

  /// 取嵌套 Map。B 站被风控时 `data` 可能为字符串 / 数组，直接
  /// `as Map<String, dynamic>?` 会抛 TypeError（属于 Error，不会被
  /// `on DioException` 捕获），从而使登录态检测 / 扫码轮询直接崩溃。
  static Map<String, dynamic>? _asMap(Object? v) =>
      v is Map ? Map<String, dynamic>.from(v) : null;

  /// 宽容取 int（`code` / `vipStatus` 等字段偶发为字符串）
  static int? _asInt(Object? v) {
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString().trim() ?? '');
  }

  // ─── 登录状态 ─────────────────────────────────────────────────────────────

  /// 检查是否已登录（Cookie 是否有效）
  /// 返回 true 表示已登录
  Future<bool> checkLoginStatus() async {
    _ensureInitialized();
    try {
      final resp = await _dio.get<dynamic>(_navUrl);
      final data = resp.data;
      if (data is! Map) return false;
      final code = data['code'];
      if (code != 0) return false;
      // isLogin 字段仅在已登录时出现
      final d = _asMap(data['data']);
      return d?['isLogin'] == true;
    } on Exception {
      // 网络异常 / 响应形态异常均视为未登录，不能向上抛
      return false;
    }
  }

  /// 检查大会员状态（vipStatus == 1）
  Future<bool> checkVipStatus() async {
    _ensureInitialized();
    try {
      final resp = await _dio.get<dynamic>(_navUrl);
      final data = resp.data;
      if (data is! Map) return false;
      if (data['code'] != 0) return false;
      final d = _asMap(data['data']);
      return _asInt(d?['vipStatus']) == 1;
    } on Exception {
      return false;
    }
  }

  /// 读取当前账号的昵称与头像（nav 接口）。
  ///
  /// 与 [checkLoginStatus] / [checkVipStatus] 不同，本方法一次请求同时拿到
  /// `uname` / `face`，用于登录后填充首页问候与设置页账号信息。
  /// 失败返回 [BiliProfile.anonymous]。
  Future<BiliProfile> fetchProfile() async {
    _ensureInitialized();
    try {
      final resp = await _dio.get<dynamic>(_navUrl);
      final body = resp.data;
      if (body is! Map) return BiliProfile.anonymous;
      if ((_asInt(body['code']) ?? -1) != 0) {
        return BiliProfile.anonymous;
      }
      final d = body['data'];
      if (d is! Map) return BiliProfile.anonymous;
      final nickname = (d['uname'] ?? '').toString().trim();
      final avatar = (d['face'] ?? '').toString().trim();
      return BiliProfile(
        isLoggedIn: d['isLogin'] == true,
        nickname: nickname.isEmpty ? null : nickname,
        avatarUrl: avatar.isEmpty ? null : avatar,
        mid: _asInt(d['mid']) ?? 0,
      );
    } on Exception {
      return BiliProfile.anonymous;
    }
  }

  // ─── 自动登录 ─────────────────────────────────────────────────────────────

  /// 是否有本地持久化 Cookie（内存快照检查，无网络 IO）。
  /// 仅用于应用启动路由判断，不代表 Cookie 未过期。
  bool get hasSavedCookies => _cookieCache.containsKey('SESSDATA');

  /// 自动登录完整流程：
  /// 1. 检测现有 Cookie 是否仍有效 → 有效即返回 [LoginResult.success]
  /// 2. 无效则尝试密码登录（已被遇遇极验滑块限制，不推荐使用）
  /// 3. 密码登录失败后调用方应跳转扫码登录页
  ///
  /// 注：扫码登录流程由 [generateQrCode] + [pollQrStatus] 实现，
  ///     调用方需自行轮询。
  Future<LoginResult> autoLogin() async {
    _ensureInitialized();

    // 先检测现有 Cookie 是否仍有效
    if (await checkLoginStatus()) {
      return LoginResult.success;
    }

    // 从加密箱读取密码
    final password = await _secureBox.getPassword();
    if (password == null || password.isEmpty) {
      // 无密码存储，需用户先输入
      return LoginResult.wrongPassword;
    }

    // 执行账密登录
    final result = await loginWithPassword(password);
    if (result == LoginResult.success) {
      // 登录成功，持久化 Cookie
      final fresh = await _readCookiesFromJar();
      if (fresh.isNotEmpty) {
        await _secureBox.saveCookies(fresh);
      }
    }
    return result;
  }

  // ─── 账密登录实现（已废，仅供历史 Cookie 过期时尝试）───────────────

  /// 使用手机号 + 密码登录。
  ///
  /// **注意**：实测 Bilibili 新设备密码登录会触发遇遇极验滑块 + 短信验证码，
  /// 实际自动化成功率极低。推荐使用扫码登录（[generateQrCode] + [pollQrStatus]）。
  /// 保留本方法是为了历史版本兼容和失败降级。
  ///
  /// 流程：
  /// 1. GET nav 接口初始化 Cookie（获取 bili_jct 作为 csrf）
  /// 2. 获取 RSA 公钥
  /// 3. RSA 加密密码
  /// 4. POST 登录接口
  /// 5. 解析响应，提取 Cookie
  @Deprecated('密码登录已被遇遇极验拦截，推荐使用扫码登录')
  Future<LoginResult> loginWithPassword(String password) async {
    _ensureInitialized();

    try {
      // Step 1: 初始化 Cookie，获取 csrf（bili_jct）
      await _dio.get<dynamic>(
        'https://www.bilibili.com',
        options: Options(
          headers: {'Referer': 'https://passport.bilibili.com/login'},
        ),
      );
      final initialCookies = await _readCookiesFromJar();
      final csrf = initialCookies['bili_jct'] ?? '';

      // Step 2: 获取 RSA 公钥
      String hash = '';
      RSAPublicKey? rsaPublicKey;
      try {
        final keyResp = await _dio.get<dynamic>(_publicKeyUrl);
        final keyData = keyResp.data;
        if (keyData is Map && keyData['code'] == 0) {
          final kd = _asMap(keyData['data']);
          hash = (kd?['hash'] ?? '').toString();
          final publicKeyStr = kd?['key']?.toString();
          if (publicKeyStr != null) {
            rsaPublicKey = _parseRsaPublicKey(publicKeyStr);
          }
        }
      } on Exception {
        // 公钥获取失败则降级明文密码
      }

      // Step 3: 准备密码（RSA 加密，失败则明文）
      final encryptedPassword = _encryptPassword(password, hash, rsaPublicKey);

      // Step 4: POST 登录
      final loginResp = await _dio.post<dynamic>(
        _loginUrl,
        data: FormData.fromMap({
          'username': phone,
          'password': encryptedPassword,
          'keep': '0',
          'csrf': csrf,
        }),
        options: Options(
          headers: {
            'Referer': 'https://passport.bilibili.com/login',
            'Origin': 'https://passport.bilibili.com',
          },
        ),
      );

      // Step 5: 解析响应
      final result = _handleLoginResponse(loginResp.data);
      if (result == LoginResult.success) {
        // 登录接口会写入新 Cookie，刷新内存快照保持同步可用
        await _refreshCookieCache();
      }
      return result;
    } on DioException catch (e) {
      if (e.response?.statusCode == 412) {
        // 412 Precondition Failed — Bilibili 风控，需验证码
        return LoginResult.needCaptcha;
      }
      return LoginResult.networkError;
    } on Exception {
      return LoginResult.networkError;
    }
  }

  LoginResult _handleLoginResponse(dynamic rawData) {
    if (rawData is! Map) return LoginResult.networkError;
    final code = rawData['code'];
    if (code == 0) {
      // 登录成功；Cookie 已由 CookieManager 自动写入 CookieJar
      return LoginResult.success;
    }
    if (code == -101) return LoginResult.wrongPassword;
    if (code == 3 || code == -403) return LoginResult.needCaptcha;
    // 其他非零 code 视为密码错误（含 code=-105 账户不存在等）
    return LoginResult.wrongPassword;
  }

  // ─── 密码 RSA 加密 ────────────────────────────────────────────────────────

  String _encryptPassword(String password, String hash, RSAPublicKey? key) {
    if (key == null || hash.isEmpty) {
      // 无法获取公钥，直接返回明文
      return password;
    }
    try {
      // Bilibili 加密规则：ciphertext = RSA(hash + password)
      final plain = '$hash$password';
      final encrypter = Encrypter(RSA(publicKey: key));
      final encrypted = encrypter.encrypt(plain);
      return encrypted.base64;
    } on Exception {
      // RSA 加密失败，降级明文
      return password;
    }
  }

  /// 解析 Bilibili PEM 格式 RSA 公钥
  /// 例：-----BEGIN PUBLIC KEY-----\n...
  RSAPublicKey? _parseRsaPublicKey(String pemStr) {
    try {
      final key = RSAKeyParser().parse(pemStr);
      if (key is RSAPublicKey) return key;
      return null;
    } on Exception {
      return null;
    }
  }

  // ─── 重新登录（密码更新后） ───────────────────────────────────────────────

  /// 更新密码并重新登录
  Future<LoginResult> reLogin(String newPassword) async {
    await _secureBox.savePassword(newPassword);
    return loginWithPassword(newPassword);
  }

  // ─── 手动导入 Cookie ───────────────────────────────────────────────────────

  /// 从原始 Cookie 字符串手动导入（备选方案，当账密登录被验证码拦截时使用）
  ///
  /// 格式示例：`"SESSDATA=xxx; bili_jct=yyy; DedeUserID=zzz"`
  Future<bool> importCookies(String rawCookieStr) async {
    _ensureInitialized();
    final parsed = NetworkClient.parseCookieString(rawCookieStr);
    if (parsed.isEmpty) return false;
    // 验证导入的 Cookie 是否有效
    final injected = await _injectCookies(parsed);
    if (injected && await checkLoginStatus()) {
      await _secureBox.saveCookies(parsed);
      await _refreshCookieCache();
      return true;
    }
    return false;
  }

  /// 将 Cookie Map 注入到 CookieJar。
  ///
  /// **必须显式设置 `domain = '.bilibili.com'`**：[DefaultCookieJar] 对“无 domain
  /// 属性”的 Cookie 按 host 精确匹配存取（见其 loadForRequest，
  /// 仅 `hostname == domain` 才命中）。若只挂在 www / passport 下，
  /// 则 `api.bilibili.com`（nav / 推荐 / 排行 / 搜索）请求不会携带 SESSDATA，
  /// 接口按未登录返回，首页“每日推荐 / 热门歌曲”因此加载失败。
  /// 设为顶级域后，所有 `*.bilibili.com` 子域共享这批 Cookie（与浏览器行为一致）。
  Future<bool> _injectCookies(Map<String, String> cookies) async {
    try {
      final uris = [
        Uri.parse('https://www.bilibili.com'),
        Uri.parse('https://passport.bilibili.com'),
        Uri.parse('https://api.bilibili.com'),
      ];
      final cookieList = cookies.entries
          .map((e) => Cookie(e.key, e.value)
            ..path = '/'
            ..domain = '.bilibili.com')
          .toList();
      for (final uri in uris) {
        await _cookieJar.saveFromResponse(uri, cookieList);
      }
      return true;
    } on Exception {
      return false;
    }
  }

  /// 从 CookieJar 读取当前 bilibili.com 的 Cookie，并刷新内存快照
  Future<Map<String, String>> _readCookiesFromJar() async {
    final fresh = await _refreshCookieCache();
    return fresh;
  }

  /// 从 CookieJar 重新加载 bilibili.com Cookie 并更新 [_cookieCache]
  ///
  /// 三个 host 都要读：顶级域（`.bilibili.com`）共享 Cookie 任读一个即可命中，
  /// 但 passport / www 在登录过程中也可能写入 **host-only** Cookie（无 domain
  /// 属性，cookie_jar 按 host 精确匹配），因此三个域名合并才能保证
  /// SESSDATA / bili_jct 等完整入快照。
  Future<Map<String, String>> _refreshCookieCache() async {
    try {
      final uris = [
        Uri.parse('https://www.bilibili.com'),
        Uri.parse('https://passport.bilibili.com'),
        Uri.parse('https://api.bilibili.com'),
      ];
      final merged = <String, String>{};
      for (final uri in uris) {
        final jarCookies = await _cookieJar.loadForRequest(uri);
        for (final c in jarCookies) {
          merged[c.name] = c.value;
        }
      }
      _cookieCache
        ..clear()
        ..addAll(merged);
    } on Exception {
      // 读取失败时保留旧快照
    }
    return Map.unmodifiable(_cookieCache);
  }

  // ─── 扫码登录 ──────────────────────────────────────────────────────────────

  /// 生成登录二维码。
  ///
  /// GET `passport.bilibili.com/x/passport-login/web/qrcode/generate`
  /// 成功返回 [QrLoginResult]，失败（网络错误 / 非零 code）返回 null。
  Future<QrLoginResult?> generateQrCode() async {
    _ensureInitialized();
    try {
      final resp = await _dio.get<dynamic>(
        _qrGenerateUrl,
        options: Options(
          headers: {
            'Referer': 'https://www.bilibili.com',
            'Origin': 'https://www.bilibili.com',
          },
        ),
      );
      final body = resp.data;
      if (body is! Map || body['code'] != 0) return null;
      final d = _asMap(body['data']);
      final url = d?['url']?.toString();
      final qrcodeKey = d?['qrcode_key']?.toString();
      if (url == null ||
          url.isEmpty ||
          qrcodeKey == null ||
          qrcodeKey.isEmpty) {
        return null;
      }
      return QrLoginResult(url: url, qrcodeKey: qrcodeKey);
    } on Exception {
      return null;
    }
  }

  /// 轮询扫码状态。
  ///
  /// GET `passport.bilibili.com/x/passport-login/web/qrcode/poll?qrcode_key=xxx`
  ///
  /// 接口外层 `code` 恒为 0（API 调用成功），内层 `data.code` 代指当前扫码状态。
  /// 部分实现中状态码直接在外层，本方法对两种格式均兼容。
  ///
  /// **confirmed（code=0）** 时：
  /// - CookieManager 会自动将 Set-Cookie 写入 [CookieJar]；
  /// - 本方法同时调用 [_refreshCookieCache] 并持久化到 [SecureBox]，
  ///   返回携带 Cookie Map 的 [QrPollResult]。
  Future<QrPollResult> pollQrStatus(String qrcodeKey) async {
    _ensureInitialized();
    try {
      final resp = await _dio.get<dynamic>(
        _qrPollUrl,
        queryParameters: {'qrcode_key': qrcodeKey},
        options: Options(
          headers: {
            'Referer': 'https://www.bilibili.com',
            'Origin': 'https://www.bilibili.com',
          },
        ),
      );
      final body = resp.data;
      if (body is! Map) {
        return const QrPollResult(status: QrPollStatus.waiting);
      }

      // 解析状态码：优先取内层 data.code，降级取外层 code
      final d = _asMap(body['data']);
      final innerCode = _asInt(d?['code']);
      final outerCode = _asInt(body['code']) ?? -1;
      final statusCode = innerCode ?? outerCode;

      if (statusCode == 0) {
        // 登录成功：先从 CookieJar 刷新内存快照
        await _refreshCookieCache();
        var fresh = Map<String, String>.from(_cookieCache);

        // 快照里没有 SESSDATA：则从响应头手动提取并注入
        if (!fresh.containsKey('SESSDATA')) {
          final setCookies = resp.headers['set-cookie'] ?? [];
          final extracted = _extractCookiesFromHeaders(setCookies);
          if (extracted.containsKey('SESSDATA')) {
            await _injectCookies(extracted);
            fresh = Map<String, String>.from(await _refreshCookieCache());
          }
        }

        if (fresh.containsKey('SESSDATA')) {
          // **无条件回注一次**：passport 返回的 Set-Cookie 可能被存成
          // host-only（仅 passport.bilibili.com），而 api.bilibili.com 的
          // nav / 推荐 / 排行榜请求必须携带 SESSDATA。[_injectCookies] 会将其
          // 统一升级为 `.bilibili.com` 顶级域，避免首页“每日推荐 / 热门歌曲”失败。
          await _injectCookies(fresh);
          fresh = Map<String, String>.from(await _refreshCookieCache());
          await _secureBox.saveCookies(fresh);
        }
        return QrPollResult(status: QrPollStatus.confirmed, cookies: fresh);
      }

      return switch (statusCode) {
        86101 => const QrPollResult(status: QrPollStatus.waiting),
        86090 => const QrPollResult(status: QrPollStatus.scanned),
        86038 => const QrPollResult(status: QrPollStatus.expired),
        _ => const QrPollResult(status: QrPollStatus.waiting),
      };
    } on DioException {
      return const QrPollResult(status: QrPollStatus.waiting);
    }
  }

  /// 从 Set-Cookie 响应头列表提取 Cookie Map（备用）
  Map<String, String> _extractCookiesFromHeaders(List<String> headers) {
    final result = <String, String>{};
    for (final h in headers) {
      // 格式："NAME=VALUE; Path=/; Domain=.bilibili.com; ..."
      final firstPair = h.split(';').first.trim();
      final eq = firstPair.indexOf('=');
      if (eq <= 0) continue;
      final name = firstPair.substring(0, eq).trim();
      final value = firstPair.substring(eq + 1).trim();
      if (name.isNotEmpty) result[name] = value;
    }
    return result;
  }

  // ─── 登出 ─────────────────────────────────────────────────────────────────

  /// 清除所有 Cookie（本地文件存储 + 内存缓存），不影响已存储的密码
  Future<void> logout() async {
    await _cookieJar.deleteAll();
    await _secureBox.clearCookies();
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('BiliAuth not initialized. Call init() first.');
    }
  }
}
