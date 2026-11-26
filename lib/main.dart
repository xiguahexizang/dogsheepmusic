import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:dog_sheep_player/app/router.dart';
import 'package:dog_sheep_player/core/audio/audio_handler.dart';
import 'package:dog_sheep_player/core/audio/audio_session_config.dart';
import 'package:dog_sheep_player/core/audio/notification_config.dart';
import 'package:dog_sheep_player/core/bili_api/auth.dart';
import 'package:dog_sheep_player/core/bili_api/music.dart';
import 'package:dog_sheep_player/core/bili_api/video.dart';
import 'package:dog_sheep_player/core/providers.dart';
import 'package:dog_sheep_player/core/storage/secure_box.dart';

import 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化 Hive 本地存储
  await Hive.initFlutter();

  // 注册 Box
  await Hive.openBox('settings');
  await Hive.openBox('music_cache');
  await Hive.openBox('history');
  await Hive.openBox('favorites');

  // 初始化 SecureBox（AES 加密箱）
  final secureBox = SecureBox();
  await secureBox.init();

  // 初始化 BiliAuth（扫码登录 & Cookie 管理）
  // auth.init() 会从 SecureBox 恢复历史 Cookie 并注入 CookieJar，
  // 必须在路由判断之前完成，以便读取 hasSavedCookies。
  final auth = BiliAuth();
  await auth.init(secureBox);

  // ─── 初始路由判断 ────────────────────────────────────────────────────────
  // 有持久化 Cookie → 进首页（异步验证有效性，失败则跳转扫码页）
  // 无 Cookie（首次安装 / 已登出）→ 直接进扫码登录页
  final initialLocation = auth.hasSavedCookies ? null : RouteNames.login;

  // ─── 音频处理器 ──────────────────────────────────────────────────────────
  // just_audio 在 Web 上可用；audio_service 的通知栏与音频会话为原生专有，
  // Web 上跳过，避免 MissingPluginException 导致 handler 完全不可用。
  DogSheepAudioHandler? audioHandler;
  try {
    final handler = DogSheepAudioHandler(
      biliVideo: BiliVideo(auth.dio),
      biliMusic: BiliMusic(auth.dio),
      cookiesProvider: () => auth.cookies,
    );
    if (!kIsWeb) {
      // 配置音频会话：contentType=music、焦点打断暂停、耳机拔出暂停。
      // 必须在 AudioService.init() 之前，just_audio 会自动复用此全局会话单例。
      await AudioSessionConfig.configure(() => handler);
      // 初始化 AudioService（后台播放 + 通知栏 MediaItem，关键接线）
      await AudioService.init(
        builder: () => handler,
        config: dogSheepAudioServiceConfig,
      );
    }
    // 绑定 just_audio 事件流 → audio_service PlaybackState / MediaItem
    await handler.init();
    audioHandler = handler;
  } catch (e) {
    debugPrint('Audio init failed (non-fatal): $e');
    audioHandler = null;
  }

  // 创建路由（initialLocation 根据是否有保存的 Cookie 决定）
  final router = createAppRouter(initialLocation: initialLocation);

  // 启动自动登录（异步，不阻塞首帧渲染）
  // 仅当有本地 Cookie 时才尝试验证。若 Cookie 已过期，跳转扫码登录页。
  if (auth.hasSavedCookies) {
    // ignore: unawaited_futures
    auth.autoLogin().then((result) {
      // 恢复 Hi-Res 默认开关（仅音频初始化成功时）
      final handler = audioHandler;
      if (handler != null) {
        secureBox.getHiResEnabled().then((enabled) {
          handler.hiResEnabled = enabled;
        });
      }
      // Cookie 失效 → 引导用户重新扫码
      if (result != LoginResult.success) {
        router.go(RouteNames.login);
      }
    });
  }

  runApp(
    ProviderScope(
      overrides: [
        secureBoxProvider.overrideWithValue(secureBox),
        biliAuthProvider.overrideWithValue(auth),
        if (audioHandler != null)
          audioHandlerProvider.overrideWithValue(audioHandler),
        appRouterProvider.overrideWithValue(router),
      ],
      child: const DogSheepApp(),
    ),
  );
}
