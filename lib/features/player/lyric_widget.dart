import 'package:flutter/material.dart';

import 'package:dog_sheep_player/app/theme.dart';

/// 单行歌词
class LyricLine {
  final Duration time;
  final String text;
  const LyricLine(this.time, this.text);
}

/// LRC 解析
///
/// 匹配形如 `[mm:ss]`、`[mm:ss.xx]`、`[mm:ss.xxx]` 的时间标签，
/// 一行可能包含多个时间标签，共享其后的文本；元信息标签（如 `[ar:]`）会被忽略。
List<LyricLine> parseLrc(String raw) {
  final result = <LyricLine>[];
  final timeRe = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');
  for (final line in raw.split('\n')) {
    final matches = timeRe.allMatches(line).toList();
    if (matches.isEmpty) continue;
    final text = line.substring(matches.last.end).trim();
    if (text.isEmpty) continue;
    for (final m in matches) {
      final min = int.parse(m.group(1)!);
      final sec = int.parse(m.group(2)!);
      final fracRaw = (m.group(3) ?? '0');
      final frac = int.parse(fracRaw.padRight(3, '0').substring(0, 3));
      result.add(LyricLine(
        Duration(minutes: min, seconds: sec, milliseconds: frac),
        text,
      ));
    }
  }
  result.sort((a, b) => a.time.compareTo(b.time));
  return result;
}

/// 滚动歌词组件
///
/// - [lyricText] 为空或 [showEmpty]（非音乐来源）时显示占位文案
/// - 当前行暖金高亮、放大，其余行淡出；随 [position] 平滑居中滚动
class LyricWidget extends StatefulWidget {
  final String? lyricText;

  /// 当前播放进度
  final Duration position;

  /// 是否正在播放（用于恢复自动滚动）
  final bool autoScroll;

  /// 非音乐来源时显示的占位（视频等「暂无歌词」）
  final bool noLyricSource;

  const LyricWidget({
    super.key,
    required this.lyricText,
    required this.position,
    this.autoScroll = true,
    this.noLyricSource = false,
  });

  @override
  State<LyricWidget> createState() => _LyricWidgetState();
}

class _LyricWidgetState extends State<LyricWidget> {
  static const double _lineExtent = 52;

  List<LyricLine> _lines = const [];
  final ScrollController _scroll = ScrollController();
  int _currentIndex = -1;
  double _viewportHeight = 0;
  bool _userScrolling = false;

  @override
  void initState() {
    super.initState();
    _reparse();
  }

  @override
  void didUpdateWidget(covariant LyricWidget old) {
    super.didUpdateWidget(old);
    if (old.lyricText != widget.lyricText) {
      _reparse();
      _currentIndex = -1;
    }
    // didUpdateWidget 运行在 build 阶段，直接 animateTo 会触发
    // "Build scheduled during frame"，因此推迟到帧结束后滚动。
    final position = widget.position;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updatePosition(position);
    });
  }

  void _reparse() {
    final src = widget.lyricText;
    _lines = (src == null || src.isEmpty) ? const [] : parseLrc(src);
  }

  /// 二分查找当前行索引
  int _indexFor(Duration position) {
    if (_lines.isEmpty) return -1;
    var lo = 0, hi = _lines.length - 1, ans = -1;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      if (_lines[mid].time <= position) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }

  void _updatePosition(Duration position) {
    if (_lines.isEmpty || !_scroll.hasClients || !widget.autoScroll) return;
    final idx = _indexFor(position);
    if (idx == _currentIndex || idx < 0 || _userScrolling) return;
    _currentIndex = idx;
    // 目标偏移恰好使第 idx 行居中（padding 与 itemExtent 已抵消）
    _scroll.animateTo(
      (idx * _lineExtent).clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 无歌词 / 视频来源
    if (_lines.isEmpty) {
      return Center(
        child: Text(
          widget.noLyricSource ? '「该来源暂无歌词」' : '「暂无歌词」',
          style: const TextStyle(color: AppTheme.textSub, fontSize: 15),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        _viewportHeight = c.maxHeight;
        final padding = (_viewportHeight - _lineExtent) / 2;
        return Listener(
          onPointerDown: (_) => _userScrolling = true,
          onPointerUp: (_) {
            // 用户滚动结束后 3 秒恢复自动滚动
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted) _userScrolling = false;
            });
          },
          child: ListView.builder(
            controller: _scroll,
            itemExtent: _lineExtent,
            padding: EdgeInsets.symmetric(vertical: padding),
            physics: const BouncingScrollPhysics(),
            itemCount: _lines.length,
            itemBuilder: (context, i) {
              final active = i == _currentIndex;
              final distance = (i - _currentIndex).abs();
              final opacity = distance == 0
                  ? 1.0
                  : (1.0 - distance * 0.22).clamp(0.28, 1.0);
              return Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                  style: TextStyle(
                    fontSize: active ? 19 : 15,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active
                        ? AppTheme.accent
                        : AppTheme.textMain.withValues(alpha: opacity),
                    height: 1.3,
                    letterSpacing: 0.2,
                  ),
                  child: Text(
                    _lines[i].text,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
