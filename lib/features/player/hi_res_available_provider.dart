/// Hi-Res 可用性判断
///
/// 综合「当前曲目实际存在的最高音质」与「用户大会员状态」，
/// 供 [HiResToggle] 决定是启用完整动效开关，还是进入禁用态。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dog_sheep_player/core/bili_api/video.dart';
import 'package:dog_sheep_player/core/providers.dart';
import 'package:dog_sheep_player/features/player/player_provider.dart';

/// Bilibili Hi-Res FLAC 音质档位（qualityId >= 该值视为存在 Hi-Res 轨）
const int kHiResQualityId = BiliVideo.hiResQualityId;

/// 当前曲目实际可用的最高 qualityId（响应式，随切歌 / 音质解析更新）
final hiResMaxQualityIdProvider = StreamProvider<int>((ref) async* {
  final handler = ref.watch(audioHandlerProvider);
  // 先推送当前快照，再持续监听后续变更
  yield handler.currentTrackMaxQualityId;
  yield* handler.qualityResolvedStream;
});

/// 当前曲目是否存在可用的 Hi-Res 音轨（不含会员判断）
final hiResTrackSupportedProvider = Provider<bool>((ref) {
  final hasItem = ref.watch(currentItemProvider).valueOrNull != null;
  final maxQualityId = ref.watch(hiResMaxQualityIdProvider).valueOrNull ?? 0;
  return hasItem && maxQualityId >= kHiResQualityId;
});

/// Hi-Res 开关整体是否可用：大会员 + 曲目含 Hi-Res 轨
///
/// 非大会员或该曲目无 Hi-Res 轨时返回 false，UI 进入禁用态。
final hiResAvailableProvider = Provider<bool>((ref) {
  final isVip = ref.watch(vipStatusProvider);
  final supported = ref.watch(hiResTrackSupportedProvider);
  return isVip && supported;
});
