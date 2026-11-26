/// 搜索状态管理
///
/// - [SearchHistoryController]：基于 Hive「history」box 的搜索历史
/// - [SearchController]：关键词搜索 + 分页加载
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import 'package:dog_sheep_player/core/bili_api/music.dart';
import 'package:dog_sheep_player/core/providers.dart';

// ─── 搜索历史 ───────────────────────────────────────────────────────────────

/// 单条搜索记录
class SearchHistoryItem {
  final String keyword;
  final DateTime time;
  const SearchHistoryItem(this.keyword, this.time);

  Map<String, dynamic> toMap() =>
      {'keyword': keyword, 'time': time.toIso8601String()};

  factory SearchHistoryItem.fromMap(Map m) => SearchHistoryItem(
        (m['keyword'] ?? '').toString(),
        DateTime.tryParse((m['time'] ?? '').toString()) ?? DateTime.now(),
      );
}

/// 搜索历史控制器
///
/// 数据存放在 Hive「history」box 的 `search_history` 键，按输入顺序倒序存储，
/// 最多保留 [maxSize] 条，重复关键词会移到首位。
class SearchHistoryController extends StateNotifier<List<SearchHistoryItem>> {
  SearchHistoryController(this._box) : super(_load(_box));

  static const _entryKey = 'search_history';
  static const int maxSize = 20;

  final Box<dynamic> _box;

  static List<SearchHistoryItem> _load(Box<dynamic> box) {
    final raw = box.get(_entryKey);
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(SearchHistoryItem.fromMap)
        .toList(growable: false);
  }

  /// 记录一次搜索（自动去重、置顶、截断）
  Future<void> add(String keyword) async {
    final k = keyword.trim();
    if (k.isEmpty) return;
    final next = [...state.where((e) => e.keyword != k)];
    next.insert(0, SearchHistoryItem(k, DateTime.now()));
    if (next.length > maxSize) {
      next.removeRange(maxSize, next.length);
    }
    await _box.put(_entryKey, next.map((e) => e.toMap()).toList());
    state = next;
  }

  /// 删除单条历史
  Future<void> remove(String keyword) async {
    final next = [...state]..removeWhere((e) => e.keyword == keyword);
    await _box.put(_entryKey, next.map((e) => e.toMap()).toList());
    state = next;
  }

  /// 清空历史
  Future<void> clear() async {
    await _box.delete(_entryKey);
    state = const [];
  }
}

final searchHistoryProvider =
    StateNotifierProvider<SearchHistoryController, List<SearchHistoryItem>>(
        (ref) {
  return SearchHistoryController(Hive.box('history'));
});

// ─── 搜索结果 ───────────────────────────────────────────────────────────────

/// 搜索状态
class SearchState {
  final String keyword;
  final List<MusicTrack> results;
  final int page;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final String? error;

  const SearchState({
    this.keyword = '',
    this.results = const [],
    this.page = 0,
    this.loading = false,
    this.loadingMore = false,
    this.hasMore = true,
    this.error,
  });

  bool get isEmpty => !loading && results.isEmpty && error == null;

  SearchState copyWith({
    String? keyword,
    List<MusicTrack>? results,
    int? page,
    bool? loading,
    bool? loadingMore,
    bool? hasMore,
    String? error,
    bool clearError = false,
  }) {
    return SearchState(
      keyword: keyword ?? this.keyword,
      results: results ?? this.results,
      page: page ?? this.page,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      hasMore: hasMore ?? this.hasMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// 每页条数（Bilibili 搜索默认每页约 20~30 条）
const int kSearchPageSize = 20;

/// 搜索控制器
class SearchController extends StateNotifier<SearchState> {
  SearchController(this._api) : super(const SearchState());

  final BiliMusic _api;
  int _requestSeq = 0;

  /// 发起（或重置）关键词搜索
  Future<void> search(String keyword) async {
    final k = keyword.trim();
    if (k.isEmpty) {
      state = const SearchState();
      return;
    }
    final seq = ++_requestSeq;
    state = state.copyWith(keyword: k, loading: true, clearError: true);
    final list = await _api.search(k, page: 1);
    if (seq != _requestSeq) return; // 已被更新的搜索取代
    state = state.copyWith(
      loading: false,
      results: list,
      page: 1,
      hasMore: list.length >= kSearchPageSize,
    );
  }

  /// 加载下一页并追加
  Future<void> loadMore() async {
    if (state.loading || state.loadingMore || !state.hasMore) return;
    if (state.keyword.isEmpty) return;
    final seq = _requestSeq;
    final nextPage = state.page + 1;
    state = state.copyWith(loadingMore: true);
    final list = await _api.search(state.keyword, page: nextPage);
    if (seq != _requestSeq) return;
    state = state.copyWith(
      loadingMore: false,
      results: [...state.results, ...list],
      page: nextPage,
      hasMore: list.length >= kSearchPageSize,
    );
  }

  /// 清空（返回历史视图）
  void reset() {
    _requestSeq++;
    state = const SearchState();
  }
}

final searchProvider =
    StateNotifierProvider<SearchController, SearchState>((ref) {
  return SearchController(ref.watch(biliMusicProvider));
});
