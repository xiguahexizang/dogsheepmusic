import 'package:flutter/material.dart';

/// 淡入 + 轻微上移的进场动画容器
///
/// 用于列表项 / 区块的 staggered 出场效果。
class FadeIn extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Duration delay;
  final double offset;

  const FadeIn({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 380),
    this.delay = Duration.zero,
    this.offset = 16,
  });

  @override
  State<FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<FadeIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _fade =
      CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween(
    begin: Offset(0, widget.offset / 100),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
