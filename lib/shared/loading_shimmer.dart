import 'package:flutter/material.dart';

import 'package:dog_sheep_player/app/theme.dart';

/// 加载骨架屏：微光扫过的占位块
///
/// 通过线性渐变在占位矩形上往复移动模拟 shimmer 效果，
/// 无需引入额外依赖。
class LoadingShimmer extends StatefulWidget {
  /// 单个骨架块高度
  final double height;

  /// 单个骨架块宽度；null 表示填满父容器
  final double? width;

  /// 圆角
  final double radius;

  /// 纵向堆叠的骨架块数量（[itemCount] > 1 时按列排布）
  final int itemCount;

  /// 是否为方形（封面）骨架
  final bool square;

  const LoadingShimmer({
    super.key,
    this.height = 16,
    this.width,
    this.radius = AppTheme.radius,
    this.itemCount = 1,
    this.square = false,
  });

  /// 快捷：曲目列表骨架（[count] 行「封面 + 两行文字」）
  const LoadingShimmer.trackList({super.key, int count = 6})
      : height = 56,
        width = null,
        radius = AppTheme.radius,
        itemCount = count,
        square = true;

  @override
  State<LoadingShimmer> createState() => _LoadingShimmerState();
}

class _LoadingShimmerState extends State<LoadingShimmer>
    with SingleTickerProviderStateMixin {
  /// 浅灰骨架底色（适配白色卡片）
  static const Color _base = Color(0xFFEEF0F4);

  /// 扫光高光色（白色）
  static const Color _highlight = Color(0xFFFFFFFF);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _block(BuildContext context, double? w, double h, double r) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: const [
                _base,
                _highlight,
                _base,
              ],
              stops: const [0.0, 0.5, 1.0],
              begin: Alignment(t * 3 - 1.5, -0.3),
              end: Alignment(t * 3 - 0.5, 0.3),
            ).createShader(bounds);
          },
          child: Container(
            width: w,
            height: h,
            decoration: BoxDecoration(
              color: _base,
              borderRadius: BorderRadius.circular(r),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.square && widget.itemCount > 1) {
      return _trackList();
    }
    if (widget.square) {
      return _block(context, widget.width ?? 96, widget.height, widget.radius);
    }
    if (widget.itemCount > 1) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < widget.itemCount; i++) ...[
            _block(context, widget.width, widget.height, widget.radius),
            if (i != widget.itemCount - 1) const SizedBox(height: 12),
          ],
        ],
      );
    }
    return _block(context, widget.width, widget.height, widget.radius);
  }

  Widget _trackList() {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: widget.itemCount,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, _) {
        return Row(
          children: [
            _block(context, 48, 48, 8),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _block(context, null, 14, 6),
                  const SizedBox(height: 8),
                  _block(context, 120, 12, 6),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
