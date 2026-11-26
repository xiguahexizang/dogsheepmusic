/// 首页数据加载状态管理
///
/// 首页内容为**纯 Hi-Res 音乐随机推荐**（不再使用全站视频推荐接口）：
/// * [hiResPicksProvider]：已确认存在 30251/fLaC 音轨的曲目，随后台扫描
///   逐步增长；
/// * [musicPoolStatsProvider]：候选池规模与扫描进度，用于“正在扫描”提示；
/// * [hotSongsProvider]：音乐整区排行榜 Top N（UI 标题为「音乐排行」）；
/// * [playRandomMix] / [playRandomFrom]：点击任意曲目 → 预填 20-30 首
///   随机队列 + 播放模式置为随机（播完自动随机下一首）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dog_sheep_player/core/audio/audio_handler.dart';
import 'package:dog_sheep_player/core/bili_api/music.dart';
import 'package:dog_sheep_player/core/bili_api/music_recommend.dart';
import 'package:dog_sheep_player/core/providers.dart';
import 'package:dog_sheep_player/features/player/player_provider.dart';

// ─── Hi-Res 精选 ────────────────────────────────────────────────────────────

/// 随机播放队列预填曲目数（用户要求 20-30 首）
const int kHomeQueueLength = 30;

/// Hi-Res 精选曲目（后台扫描过程中逐步长出，不阻塞首屏）
final hiResPicksProvider = StreamProvider<List<MusicTrack>>((ref) async* {
  final rec = ref.watch(musicRecommendProvider);
  yield rec.picks;
  yield* rec.picksStream;
});

/// 候选池 / 扫描进度
final musicPoolStatsProvider = StreamProvider<MusicPoolStats>((ref) async* {
  final rec = ref.watch(musicRecommendProvider);
  yield rec.stats;
  yield* rec.statsStream;
});

/// 启动首页推荐：确保候选池已拉取并后台扫描 Hi-Res
void startHomeRecommend(WidgetRef ref) {
  final rec = ref.read(musicRecommendProvider);
  rec.startScan();
}

// ─── 随机播放 ───────────────────────────────────────────────────────────────

/// 以 [start] 为第一首，预填随机队列并开始播放（随机模式）。
///
/// 队列生成只走内存中的候选池随机，**不等待 playurl**，因此点击即播。
Future<void> playRandomFrom(WidgetRef ref, MusicTrack start) async {
  final rec = ref.read(musicRecommendProvider);
  final tracks = await rec.randomQueueFrom(start, length: kHomeQueueLength);
  await _startRandomQueue(ref, tracks, 0);
}

/// 直接随机播放一批精选（不指定起点）
Future<void> playRandomMix(WidgetRef ref) async {
  final rec = ref.read(musicRecommendProvider);
  final tracks = await rec.randomQueue(length: kHomeQueueLength);
  await _startRandomQueue(ref, tracks, 0);
}

/// 随机队列 + 随机播放模式的统一起播入口
Future<void> _startRandomQueue(
  WidgetRef ref,
  List<MusicTrack> tracks,
  int startIndex,
) async {
  if (tracks.isEmpty) return;
  ref.read(playModeProvider.notifier).mode = PlayMode.shuffle;
  final items = tracks
      .map((t) => PlayQueueItem.fromMusicTrack(t, isMusicTrack: true))
      .toList();
  await ref
      .read(playQueueProvider.notifier)
      .play(items, startIndex: startIndex.clamp(0, items.length - 1));
}

// ─── 音乐排行 ───────────────────────────────────────────────────────────────

/// 排行榜展示条数
const int kHomeHotLimit = 10;

/// 音乐排行榜 Top 10（数据源为音乐整区 rid=3，非全站热门）
final hotSongsProvider =
    FutureProvider.autoDispose<List<MusicTrack>>((ref) async {
  final music = ref.watch(biliMusicProvider);
  final list = await music.getRanking();
  return list.length > kHomeHotLimit ? list.sublist(0, kHomeHotLimit) : list;
});

// ─── 问候语 ─────────────────────────────────────────────────────────────────

/// 根据当前时间返回问候语
String greetingForNow([DateTime? now]) {
  final h = (now ?? DateTime.now()).hour;
  if (h < 5) return '夜深了';
  if (h < 11) return '早上好';
  if (h < 13) return '中午好';
  if (h < 18) return '下午好';
  return '晚上好';
}
