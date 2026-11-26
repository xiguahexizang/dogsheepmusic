import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dog_sheep_player/app/theme.dart';
import 'package:dog_sheep_player/core/bili_api/music.dart';
import 'package:dog_sheep_player/features/player/player_provider.dart';
import 'package:dog_sheep_player/features/search/search_provider.dart';
import 'package:dog_sheep_player/shared/empty_state.dart';
import 'package:dog_sheep_player/shared/loading_shimmer.dart';
import 'package:dog_sheep_player/shared/track_tile.dart';
import 'package:dog_sheep_player/shared/utils.dart';

/// 搜索页 —— 自动聚焦搜索框、历史记录、混合结果与分页加载
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // 进入页面自动聚焦
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
    // 上拉加载更多
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      ref.read(searchProvider.notifier).loadMore();
    }
  }

  void _submit(String keyword) {
    final k = keyword.trim();
    if (k.isEmpty) return;
    ref.read(searchHistoryProvider.notifier).add(k);
    ref.read(searchProvider.notifier).search(k);
    _focusNode.unfocus();
  }

  void _onTapHistory(String keyword) {
    _controller.text = keyword;
    _controller.selection = TextSelection.collapsed(offset: keyword.length);
    _submit(keyword);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchProvider);
    final history = ref.watch(searchHistoryProvider);

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  color: AppTheme.textMain,
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                Expanded(child: _buildSearchField(state)),
              ],
            ),
          ),
        ),
      ),
      body: _buildBody(state, history),
    );
  }

  /// 搜索框：圆角白色卡片样式
  Widget _buildSearchField(SearchState state) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      textInputAction: TextInputAction.search,
      style: const TextStyle(color: AppTheme.textMain, fontSize: 15),
      cursorColor: AppTheme.accent,
      decoration: InputDecoration(
        hintText: '搜索歌曲 / 视频 / UP 主',
        hintStyle: const TextStyle(color: AppTheme.textSub, fontSize: 15),
        filled: true,
        fillColor: AppTheme.bgCard,
        prefixIcon: const Icon(Icons.search, size: 20, color: AppTheme.textSub),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: AppTheme.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: AppTheme.accent, width: 1.4),
        ),
        suffixIcon: _controller.text.isNotEmpty || state.keyword.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close_rounded,
                    size: 18, color: AppTheme.textSub),
                onPressed: () {
                  _controller.clear();
                  ref.read(searchProvider.notifier).reset();
                  setState(() {});
                },
              )
            : null,
      ),
      onChanged: (_) => setState(() {}),
      onSubmitted: _submit,
    );
  }

  Widget _buildBody(SearchState state, List<SearchHistoryItem> history) {
    // 空搜索：显示历史
    if (state.keyword.isEmpty && !state.loading) {
      return _HistoryView(
        history: history,
        onTap: _onTapHistory,
        onRemove: (k) => ref.read(searchHistoryProvider.notifier).remove(k),
        onClear: () => ref.read(searchHistoryProvider.notifier).clear(),
      );
    }

    if (state.loading) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Container(
          decoration: AppTheme.cardDecoration(),
          padding: const EdgeInsets.all(14),
          child: const SizedBox(
            height: 560,
            child: LoadingShimmer.trackList(count: 10),
          ),
        ),
      );
    }

    if (state.results.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        title: '没有找到「${state.keyword}」',
        message: '换个关键词试试吧',
      );
    }

    return _ResultsView(
      controller: _scrollController,
      state: state,
      onLoadMore: () => ref.read(searchProvider.notifier).loadMore(),
    );
  }
}

/// 历史记录视图
class _HistoryView extends StatelessWidget {
  final List<SearchHistoryItem> history;
  final void Function(String keyword) onTap;
  final void Function(String keyword) onRemove;
  final VoidCallback onClear;

  const _HistoryView({
    required this.history,
    required this.onTap,
    required this.onRemove,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return const EmptyState(
        icon: Icons.history,
        title: '暂无搜索历史',
        message: '输入关键词开始搜索吧',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Row(
          children: [
            Text('搜索历史', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            IconButton(
              tooltip: '清空历史',
              icon: const Icon(Icons.delete_outline_rounded,
                  size: 20, color: AppTheme.textSub),
              onPressed: onClear,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final item in history)
              _HistoryChip(
                label: item.keyword,
                onTap: () => onTap(item.keyword),
                onDeleted: () => onRemove(item.keyword),
              ),
          ],
        ),
      ],
    );
  }
}

/// 可删除的搜索历史标签
class _HistoryChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final VoidCallback onDeleted;
  const _HistoryChip({
    required this.label,
    required this.onTap,
    required this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    return InputChip(
      label: Text(label),
      onPressed: onTap,
      onDeleted: onDeleted,
      deleteIcon: const Icon(Icons.close_rounded, size: 16),
      labelStyle: const TextStyle(color: AppTheme.textMain, fontSize: 13),
      backgroundColor: AppTheme.bgCard,
      side: const BorderSide(color: AppTheme.divider),
      shape: const StadiumBorder(),
      deleteIconColor: AppTheme.textSub,
    );
  }
}

/// 搜索结果列表（混合歌曲/视频），支持下拉刷新 + 分页
class _ResultsView extends ConsumerWidget {
  final ScrollController controller;
  final SearchState state;
  final VoidCallback onLoadMore;

  const _ResultsView({
    required this.controller,
    required this.state,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(currentItemProvider).valueOrNull;
    final isPlaying = ref.watch(isPlayingProvider);
    final tracks = state.results;

    return RefreshIndicator(
      color: AppTheme.accent,
      backgroundColor: AppTheme.bgCard,
      onRefresh: () => ref.read(searchProvider.notifier).search(state.keyword),
      child: LayoutBuilder(
        builder: (context, c) {
          // 宽屏（内屏展开）时搜索结果双列展示。
          final columns = c.maxWidth >= 600 ? 2 : 1;
          Widget tile(int i) {
            final t = tracks[i];
            return TrackTile(
              title: t.title,
              artist: t.artist,
              coverUrl: t.cover,
              duration: t.duration,
              isCurrent: current?.bvid == t.bvid,
              isPlaying: isPlaying,
              heroTag: 'cover_${t.bvid}',
              onTap: () => _play(ref, tracks, i),
            );
          }

          if (columns == 1) {
            // 结果列表：白色卡片容器
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              child: Container(
                decoration: AppTheme.cardDecoration(),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: ListView.separated(
                  controller: controller,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: tracks.length + (state.loadingMore ? 1 : 0),
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 46),
                  itemBuilder: (context, i) {
                    if (i >= tracks.length) return const _LoadingMore();
                    return tile(i);
                  },
                ),
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Container(
              decoration: AppTheme.cardDecoration(),
              padding: const EdgeInsets.all(10),
              child: GridView.builder(
                controller: controller,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 3.0,
                ),
                itemCount: tracks.length + (state.loadingMore ? 1 : 0),
                itemBuilder: (context, i) {
                  if (i >= tracks.length) return const _LoadingMore();
                  return tile(i);
                },
              ),
            ),
          );
        },
      ),
    );
  }

  /// 搜索结果多为视频，标记 isMusic=false，播放页据此显示「暂无歌词」
  void _play(WidgetRef ref, List<MusicTrack> tracks, int index) {
    playTrackList(ref, tracks, index, isMusic: false);
  }
}

/// 分页加载底部指示器
class _LoadingMore extends StatelessWidget {
  const _LoadingMore();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child:
              CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent),
        ),
      ),
    );
  }
}
