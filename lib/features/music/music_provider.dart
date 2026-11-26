/// 音乐区数据状态管理
///
/// - [rankingProvider]：音乐排行榜
/// - [playlistTracksProvider]：指定歌单内曲目（family，按 catalog id）——
///   推荐歌单 UI 已下线，保留供未来重新接入
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dog_sheep_player/core/bili_api/music.dart';
import 'package:dog_sheep_player/core/providers.dart';

/// 音乐排行榜
final rankingProvider =
    FutureProvider.autoDispose<List<MusicTrack>>((ref) async {
  final api = ref.watch(biliMusicProvider);
  return api.getRanking();
});

/// 指定歌单的曲目列表（family by catalog id）
final playlistTracksProvider = FutureProvider.autoDispose
    .family<List<MusicTrack>, String>((ref, id) async {
  final api = ref.watch(biliMusicProvider);
  return api.getPlaylist(id);
});
