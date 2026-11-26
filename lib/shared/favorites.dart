/// 收藏管理：以 Hive「favorites」box 持久化当前播放曲目的收藏状态
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import 'package:dog_sheep_player/core/audio/audio_handler.dart';
import 'package:dog_sheep_player/shared/models.dart';

/// 收藏控制器
///
/// 内部维护 `bvid -> FavoriteTrack` 映射，state 暴露为 bvid 集合，
/// 便于 UI 以 O(1) 判断「当前曲目是否已收藏」。
class FavoritesController extends StateNotifier<Set<String>> {
  FavoritesController(this._box) : super(_load(_box));

  final Box<dynamic> _box;

  static Set<String> _load(Box<dynamic> box) {
    return box.keys.map((k) => k.toString()).toSet();
  }

  /// 全部收藏记录（按存储顺序）
  List<FavoriteTrack> get all => _box.values
      .whereType<Map>()
      .map((m) => FavoriteTrack.fromMap(m))
      .toList();

  /// 是否已收藏指定 bvid
  bool contains(String bvid) => state.contains(bvid);

  /// 切换收藏状态，返回切换后是否为收藏
  Future<bool> toggle(PlayQueueItem item) async {
    if (state.contains(item.bvid)) {
      await _box.delete(item.bvid);
      state = {...state}..remove(item.bvid);
      return false;
    }
    final fav = FavoriteTrack(
      bvid: item.bvid,
      title: item.title,
      artist: item.artist,
      coverUrl: item.coverUrl,
      duration: item.duration,
      isMusicTrack: item.isMusicTrack,
    );
    await _box.put(item.bvid, fav.toMap());
    state = {...state, item.bvid};
    return true;
  }

  /// 移除收藏
  Future<void> remove(String bvid) async {
    await _box.delete(bvid);
    state = {...state}..remove(bvid);
  }
}

/// 收藏 Provider（依赖已打开的「favorites」box）
final favoritesProvider =
    StateNotifierProvider<FavoritesController, Set<String>>((ref) {
  return FavoritesController(Hive.box('favorites'));
});
