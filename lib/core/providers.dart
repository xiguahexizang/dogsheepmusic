/// Riverpod 全局 Provider 声明
/// 管理网络层、认证、存储、登录状态等共享依赖
library;

import 'dart:async' show unawaited;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bili_api/auth.dart';
import 'bili_api/music.dart';
import 'bili_api/music_recommend.dart';
import 'bili_api/recommend.dart';
import 'bili_api/video.dart';
import 'audio/audio_handler.dart';
import 'storage/secure_box.dart';

// ─── 存储层 ─────────────────────────────────────────────────────────────────

/// SecureBox 单例 Provider（需在 main() 中完成 Hive 初始化后覆盖）
final secureBoxProvider = Provider<SecureBox>((ref) {
  throw UnimplementedError('secureBoxProvider must be overridden in main()');
});

// ─── 网络层 ─────────────────────────────────────────────────────────────────

/// CookieJar Provider（由 BiliAuth 持有并共享）
final cookieJarProvider = Provider<CookieJar>((ref) {
  final auth = ref.watch(biliAuthProvider);
  return auth.cookieJar;
});

/// 主 Dio 实例 Provider（已登录态）
final dioProvider = Provider<Dio>((ref) {
  final auth = ref.watch(biliAuthProvider);
  return auth.dio;
});

// ─── 认证层 ─────────────────────────────────────────────────────────────────

/// BiliAuth 单例 Provider（需在 main() 中完成 init() 后覆盖）
final biliAuthProvider = Provider<BiliAuth>((ref) {
  throw UnimplementedError('biliAuthProvider must be overridden in main()');
});

// ─── API 封装层 ─────────────────────────────────────────────────────────────

/// 视频 API Provider
final biliVideoProvider = Provider<BiliVideo>((ref) {
  return BiliVideo(ref.watch(dioProvider));
});

/// 音乐 API Provider
final biliMusicProvider = Provider<BiliMusic>((ref) {
  return BiliMusic(ref.watch(dioProvider));
});

/// 推荐 API Provider
final biliRecommendProvider = Provider<BiliRecommend>((ref) {
  return BiliRecommend(ref.watch(dioProvider));
});

/// Hi-Res 音乐随机推荐器（首页唯一内容源）
///
/// **不要 autoDispose**：候选池（TTL 20min）与已探测的 Hi-Res 结论需要
/// 跨页面 / 跨导航复用，否则每次回首页都要重发几十个 playurl 请求。
///
/// 在这里同时完成两处接线：
/// * [DogSheepAudioHandler.queueRefill]：随机队列走完一轮时后台续源，
///   保证“播完自动下一首、随机推荐不断档”。
/// * [DogSheepAudioHandler.qualityResolvedStream]：把播放时解析出的
///   真实最高音质回填给推荐器（“播放时再检查音质”，精选列表越用越准）。
final musicRecommendProvider = Provider<MusicRecommend>((ref) {
  final rec = MusicRecommend(
    music: ref.watch(biliMusicProvider),
    video: ref.watch(biliVideoProvider),
  );
  final handler = ref.watch(audioHandlerProvider);

  handler.queueRefill = () async {
    final tracks = await rec.randomQueue(length: 20);
    return tracks
        .map((t) => PlayQueueItem.fromMusicTrack(t, isMusicTrack: true))
        .toList();
  };

  final sub = handler.qualityResolvedStream.listen((maxQualityId) {
    final item = handler.currentItem;
    if (item != null) rec.noteQuality(item.bvid, maxQualityId);
  });

  ref.onDispose(() {
    handler.queueRefill = null;
    unawaited(sub.cancel());
    rec.dispose();
  });
  return rec;
});

// ─── 音频播放层 ─────────────────────────────────────────────────────────────

/// 音频处理器 Provider（主由 main() 经 AudioService.init() 创建后覆盖）
///
/// 覆盖示例（已在 main() 中完成接线）：
/// ```dart
/// final audioHandler = DogSheepAudioHandler(
///   biliVideo: ..., biliMusic: ..., cookiesProvider: () => auth.cookies,
/// );
/// await AudioSessionConfig.configure(() => audioHandler);
/// await AudioService.init(
///   builder: () => audioHandler,
///   config: dogSheepAudioServiceConfig,
/// );
/// await audioHandler.init();
/// // ProviderScope(overrides: [audioHandlerProvider.overrideWithValue(audioHandler), ...])
/// ```
///
/// **兜底**：Web 端不支持 audio_service 的通知栏 / 音频会话（AudioService.init
/// 会抛 MissingPluginException），因而不会被覆盖。此处改为延迟创建一个
/// 裸 [DogSheepAudioHandler]（just_audio 在 Web 可用），避免 UI 层
/// `ref.read(audioHandlerProvider)` 抛 UnimplementedError 导致页面构建崩溃。
final audioHandlerProvider = Provider<DogSheepAudioHandler>((ref) {
  final auth = ref.watch(biliAuthProvider);
  final handler = DogSheepAudioHandler(
    biliVideo: BiliVideo(auth.dio),
    biliMusic: BiliMusic(auth.dio),
    cookiesProvider: () => auth.cookies,
  );
  // 帧结束后再绑定事件流，避免在 Provider 构建期间触发 setState
  Future.microtask(() async {
    try {
      await handler.init();
    } catch (e) {
      debugPrint('audioHandler fallback init failed: $e');
    }
  });
  return handler;
});

// ─── 状态层 ─────────────────────────────────────────────────────────────────

/// 登录状态枚举
enum LoginStatus {
  /// 未检测
  unknown,

  /// 已登录且 Cookie 有效
  loggedIn,

  /// 未登录（无 Cookie 或 Cookie 已失效）
  loggedOut,

  /// 登录中（正在执行自动登录）
  loggingIn,

  /// 登录失败（密码错误或需要验证码）
  failed,
}

/// 登录状态 Provider
final loginStatusProvider =
    StateProvider<LoginStatus>((ref) => LoginStatus.unknown);

/// 大会员状态 Provider（true = 大会员）
final vipStatusProvider = StateProvider<bool>((ref) => false);

/// Hi-Res 音质开关 Provider（默认开启）
final hiResEnabledProvider = StateProvider<bool>((ref) => true);

/// 当前用户昵称 Provider（登录成功后填充）
final userNicknameProvider = StateProvider<String?>((ref) => null);

/// 当前用户头像 Provider
final userAvatarProvider = StateProvider<String?>((ref) => null);
