/// 音频会话配置（基于 audio_session）
///
/// 职责：
/// - 创建并配置全局 [AudioSession]：contentType=music，
///   焦点增益 gain，`androidWillPauseWhenDucked=false`（他人可 duck 的提示音 → 压低音量而非暂停）
/// - 监听打断事件（interruptionEventStream）：来电 / 其他 App 抢占焦点时暂停播放，
///   打断结束后不自动恢复（由用户手动继续，符合音乐播放器惯例）
/// - 监听 becomingNoisy（耳机拔出 / 蓝牙断开）→ 自动暂停
///
/// just_audio 会自动复用全局 [AudioSession] 单例，因此本方法在完成配置后，
/// [DogSheepAudioHandler] 内部的 AudioPlayer 无需额外传入会话即可生效。
library;

import 'package:audio_session/audio_session.dart';

import 'package:dog_sheep_player/core/audio/audio_handler.dart';

/// 狗羊播放器音频会话配置入口
class AudioSessionConfig {
  const AudioSessionConfig._();

  /// 音乐播放会话参数（采用官方 music 配方）：
  /// - iOS：playback 类别（静音键不静音、支持后台播放）
  /// - Android：contentType=music / usage=media，焦点增益 gain；
  ///   androidWillPauseWhenDucked 取默认 false（他人可 duck 提示音时压低音量而非暂停）
  static const AudioSessionConfiguration dogSheepConfiguration =
      AudioSessionConfiguration.music();

  /// 配置音频会话并绑定打断 / 耳机拔出回调
  ///
  /// 建议在 `AudioService.init()` 之前调用。[handlerProvider] 延迟求值
  /// （会话事件触发时才回调获取 handler，避免初始化时序问题）。
  static Future<AudioSession> configure(
    DogSheepAudioHandler Function() handlerProvider,
  ) async {
    final session = await AudioSession.instance;
    await session.configure(dogSheepConfiguration);

    // ─── 打断事件（焦点丢失 / 来电 / 他人开始播放）───────────────────────
    // begin=true 表示打断开始 → 暂停；begin=false 表示打断结束 → 不自动恢复。
    // 可 duck 的短暂提示音（导航播报）由系统压低音量而非触发本事件；
    // 真正的焦点丢失（AUDIOFOCUS_LOSS / LOSS_TRANSIENT）会以打断开始呈现，此处暂停。
    session.interruptionEventStream.listen((event) {
      if (event.begin) {
        final handler = handlerProvider();
        if (handler.isPlaying) {
          handler.pause();
        }
      }
    });

    // ─── 耳机拔出 / 蓝牙断开 ─────────────────────────────────────────────
    session.becomingNoisyEventStream.listen((_) {
      final handler = handlerProvider();
      if (handler.isPlaying) {
        handler.pause();
      }
    });

    return session;
  }
}
