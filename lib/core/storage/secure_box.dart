/// Hive AES 加密箱 — 安全存储密码、Cookie 及配置
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:hive/hive.dart';

/// 安全存储箱，使用 AES 加密保护敏感数据（密码、Cookie 等）
/// AES 密钥本身存储在未加密的普通 Box 中（设备绑定，不上传）
class SecureBox {
  static const _boxName = 'secure_box';
  static const _keyBoxName = 'secure_key_box';
  static const _keyName = 'aes_key';

  late final Box<dynamic> _box;
  late final Box<dynamic> _keyBox;

  bool _initialized = false;

  /// 初始化：生成或读取 AES 密钥，打开加密箱
  Future<void> init() async {
    if (_initialized) return;

    _keyBox = await Hive.openBox<dynamic>(_keyBoxName);

    // 读取已有密钥或生成新密钥（32 字节）
    Uint8List aesKey;
    final stored = _keyBox.get(_keyName);
    if (stored is List && stored.length == 32) {
      aesKey = Uint8List.fromList(stored.cast<int>());
    } else {
      aesKey = _generateAesKey();
      await _keyBox.put(_keyName, aesKey.toList());
    }

    final cipher = HiveAesCipher(aesKey);
    _box = await Hive.openBox<dynamic>(_boxName, encryptionCipher: cipher);
    _initialized = true;
  }

  Uint8List _generateAesKey() {
    final random = Random.secure();
    final key = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      key[i] = random.nextInt(256);
    }
    return key;
  }

  // ─── 密码 ────────────────────────────────────────────────────────────────

  /// 存储登录密码
  Future<void> savePassword(String password) => _box.put('password', password);

  /// 读取登录密码，未设置时返回 null
  Future<String?> getPassword() async => _box.get('password') as String?;

  /// 是否已设置密码
  Future<bool> hasPassword() async {
    final pw = _box.get('password') as String?;
    return pw != null && pw.isNotEmpty;
  }

  /// 清除已存储的密码
  Future<void> clearPassword() => _box.delete('password');

  // ─── Cookie ──────────────────────────────────────────────────────────────

  /// 存储 Cookie（SESSDATA、bili_jct 等）
  Future<void> saveCookies(Map<String, String> cookies) =>
      _box.put('cookies', Map<String, dynamic>.from(cookies));

  /// 读取 Cookie，不存在时返回 null
  Future<Map<String, String>?> getCookies() async {
    final raw = _box.get('cookies');
    if (raw is Map) {
      return raw.map(
        (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
      );
    }
    return null;
  }

  /// 清除已存储的 Cookie
  Future<void> clearCookies() => _box.delete('cookies');

  // ─── Hi-Res 开关 ─────────────────────────────────────────────────────────

  /// 存储 Hi-Res 音质开关状态（默认为 true）
  Future<void> saveHiResEnabled(bool enabled) =>
      _box.put('hires_enabled', enabled);

  /// 读取 Hi-Res 音质开关状态，未设置时返回 true
  Future<bool> getHiResEnabled() async =>
      _box.get('hires_enabled', defaultValue: true) as bool;

  // ─── 通用 KV ─────────────────────────────────────────────────────────────

  /// 存储任意键值对
  Future<void> put(String key, dynamic value) => _box.put(key, value);

  /// 读取任意键值
  dynamic get(String key) => _box.get(key);

  /// 删除任意键
  Future<void> delete(String key) => _box.delete(key);

  /// 清除整个加密箱
  Future<void> clear() => _box.clear();
}
