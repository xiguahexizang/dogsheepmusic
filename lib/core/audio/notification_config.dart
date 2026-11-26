/// audio_service 通知栏 / 前台服务配置
///
/// 通知栏展示内容（由 [DogSheepAudioHandler] 发布的 MediaItem / PlaybackState 驱动）：
/// - 曲名（MediaItem.title）
/// - 艺术家 / UP 主（MediaItem.artist）
/// - 封面（MediaItem.artUri，系统异步拉取）
/// - 按钮：上一首 / 播放-暂停 / 下一首（androidCompactActionIndices 由
///   handler 按当前 controls 长度动态生成，最多 3 项）
/// - 进度条与 seek 操作（MediaAction.seek 等 systemActions）
///
/// 点击通知打开 App（androidNotificationClickStartsActivity = true）。
library;

import 'package:audio_service/audio_service.dart';

/// 狗羊播放器 AudioService 配置常量
///
/// 在 `main()` 中传入 `AudioService.init(config: dogSheepAudioServiceConfig)`。
final AudioServiceConfig dogSheepAudioServiceConfig = AudioServiceConfig(
  // ─── 通知渠道 ──────────────────────────────────────────────────────────
  androidNotificationChannelId: 'com.dogsheep.player.audio',
  androidNotificationChannelName: 'DogSheep音乐',
  androidNotificationChannelDescription: '音乐播放控制',

  // ─── 通知行为 ──────────────────────────────────────────────────────────
  // 播放中通知常驻（不可滑动清除）；暂停后仍保持前台服务与通知，方便恢复播放
  androidNotificationOngoing: true,
  androidStopForegroundOnPause: false,
  // 点击通知打开 App 主界面
  androidNotificationClickStartsActivity: true,

  // ─── 图标 ──────────────────────────────────────────────────────────────
  androidNotificationIcon: 'mipmap/ic_launcher',
);
