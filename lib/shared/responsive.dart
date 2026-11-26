import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dog_sheep_player/shared/folding_provider.dart';

/// 屏幕状态枚举（Z Fold 三态）。
enum ScreenState {
  /// 外屏 / 普通手机（逻辑宽度 < 600dp）。
  phone,

  /// 内屏展开（逻辑宽度 >= 600dp）—— 左右分栏。
  foldable,

  /// 悬停（半折，横铰）—— 上下分屏。
  flex,
}

/// 响应式布局工具。
///
/// 断点采用 Material 规范的 **600dp**：
/// - `< 600dp` → [ScreenState.phone]
/// - `>= 600dp` → [ScreenState.foldable]
/// - 悬停横铰姿态（原生检测）优先判定为 [ScreenState.flex]
///
/// 折叠检测在部分设备 / 模拟器上不可用，因此 flex 判定完全依赖
/// [FoldingState.isFlexPosture]；不可用时自然回退到按宽度判断，
/// 不会破坏 phone 态默认布局。
class Responsive {
  Responsive._();

  /// 展开态断点（dp）。
  static const double foldableBreakpoint = 600;

  // ─── 展开态（折叠屏内屏）紧凑布局参数 ────────────────────────────────
  // 用户反馈“左侧列表太宽、直板机拥挤”，因此导航 / 右侧面板按宽度分档收窄，
  // 把横向空间尽量让给中间内容区。

  /// 带文字标签的导航栏宽度（dp）—— Material 3 推荐紧凑值上沿。
  static const double navRailLabeledWidth = 60;

  /// 纯图标导航栏宽度（dp）—— Material 3 NavigationRail 最小宽度。
  static const double navRailIconOnlyWidth = 56;

  /// 展开态宽度低于该值时导航栏退化为“图标 + 选中指示器”，不再显示文字。
  static const double navRailLabelMinWidth = 720;

  /// 导航栏总宽（右侧面板占据后的剩余宽度）对应的宽度（dp）。
  static double navRailWidthFor(double totalWidth) =>
      totalWidth < navRailLabelMinWidth
          ? navRailIconOnlyWidth
          : navRailLabeledWidth;

  /// 导航栏是否显示文字标签。
  static bool navRailShowLabels(double totalWidth) =>
      totalWidth >= navRailLabelMinWidth;

  /// 展开态右侧常驻播放器面板宽度（dp），按总宽分档（300 → 240/260/288）。
  static double playerPanelWidthFor(double totalWidth) {
    if (totalWidth < 900) return 240;
    if (totalWidth < 1440) return 260;
    return 288;
  }

  static double getScreenWidth(BuildContext context) =>
      MediaQuery.sizeOf(context).width;

  static double getScreenHeight(BuildContext context) =>
      MediaQuery.sizeOf(context).height;

  static bool isPhone(BuildContext context) =>
      getScreenWidth(context) < foldableBreakpoint;

  static bool isFoldable(BuildContext context) =>
      getScreenWidth(context) >= foldableBreakpoint;

  /// 是否处于悬停横铰姿态（需原生检测支持，不可用时恒为 false）。
  static bool isFlex(BuildContext context) {
    try {
      return ProviderScope.containerOf(context)
          .read(foldingStateProvider)
          .isFlexPosture;
    } catch (_) {
      return false;
    }
  }

  /// 综合宽度与折叠姿态解析当前屏幕状态。
  ///
  /// [folding] 显式传入时优先使用（供 Consumer 场景避免重复读取容器）。
  static ScreenState getScreenState(BuildContext context,
      [FoldingState? folding]) {
    final state = folding ?? _readFolding(context);
    if (state.isFlexPosture) return ScreenState.flex;
    return getScreenWidth(context) >= foldableBreakpoint
        ? ScreenState.foldable
        : ScreenState.phone;
  }

  static FoldingState _readFolding(BuildContext context) {
    try {
      return ProviderScope.containerOf(context).read(foldingStateProvider);
    } catch (_) {
      return const FoldingState();
    }
  }

  /// 依据可用宽度推荐网格列数（供首页 / 音乐区 / 搜索结果复用）。
  ///
  /// 传入的是**内容区实际宽度**（已扣除导航栏、右侧面板等）。
  static int gridColumnsFor(double contentWidth) {
    if (contentWidth < 520) return 2;
    if (contentWidth < 820) return 3;
    return 4;
  }

  /// 首页横向卡片封面边长（dp），按内容区实际宽度分档，窄屏不拥挤。
  static double pickCoverWidth(double contentWidth) {
    if (contentWidth < 380) return 104;
    if (contentWidth < 520) return 124;
    if (contentWidth < 900) return 156;
    return 168;
  }

  /// 页面左右内边距（dp）：直板机 / 外屏收紧，为卡片让出宽度。
  static double pageHorizontalPadding(double totalWidth) =>
      totalWidth < 420 ? 14 : 20;

  /// 全屏播放器封面边长（dp）：同时受可用宽高约束，避免短屏溢出。
  static double playerCoverSize({
    required double width,
    required double height,
  }) {
    final byWidth = width - 88; // 左右各留 44dp 呼吸空间
    // 顶栏 / 标题信息 / 歌词区 / 控制卡片的固定开销。取值需保证 720dp 高以下
    // 的短屏仍能给歌词区留出可见高度（此前 400 会让歌词被压成 0）。
    final byHeight = height - 500;
    return math.min(byWidth, byHeight).clamp(140.0, 260.0);
  }

  /// 展开态全屏播放器中“封面 + 控制”列的宽度（dp）。
  static double playerWideColumnWidth(double totalWidth) =>
      math.min(360.0, math.max(280.0, totalWidth * 0.46));
}

/// 响应式 Builder：依据当前 [ScreenState] 构建不同布局。
class ResponsiveBuilder extends ConsumerWidget {
  final Widget Function(BuildContext context, ScreenState state) builder;

  const ResponsiveBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folding = ref.watch(foldingStateProvider);
    return builder(context, Responsive.getScreenState(context, folding));
  }
}

/// 折叠屏 Flex（悬停）模式上下分屏容器。
///
/// 处于悬停横铰姿态时，[topContent] 占上半屏、[bottomContent] 贴下半屏，
/// 并在两者之间留出铰链（hinge）高度的间隔；否则仅显示 [topContent]。
class FlexLayout extends ConsumerStatefulWidget {
  final Widget topContent;
  final Widget bottomContent;

  const FlexLayout({
    super.key,
    required this.topContent,
    required this.bottomContent,
  });

  @override
  ConsumerState<FlexLayout> createState() => _FlexLayoutState();
}

class _FlexLayoutState extends ConsumerState<FlexLayout> {
  @override
  Widget build(BuildContext context) {
    final folding = ref.watch(foldingStateProvider);
    if (!folding.isFlexPosture) {
      // 非悬停态：直接展示上半内容（等价于常规布局）。
      return widget.topContent;
    }

    // 铰链高度（物理像素 → dp），无铰链数据时为 0。
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final hingeDp = folding.hingeBounds != null
        ? (folding.hingeBounds!.height / (dpr <= 0 ? 1 : dpr)).clamp(0.0, 64.0)
        : 0.0;

    return Column(
      children: [
        Expanded(child: widget.topContent),
        SizedBox(height: hingeDp),
        widget.bottomContent,
      ],
    );
  }
}
