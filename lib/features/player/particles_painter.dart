/// Hi-Res 开关粒子爆发效果绘制器
///
/// 用户从 OFF → ON 触发时，从开关中心向外发射 5-8 颗暖金色小圆点，
/// 逐渐减速 + 淡出，形成一次华丽的爆发效果。
library;

import 'dart:math';
import 'dart:ui';

import 'package:flutter/rendering.dart' show CustomPainter;

/// 单个粒子数据（不可变）
class Particle {
  /// 发射角度（弧度，0..2π）
  final double angle;

  /// 初速度（像素/单位动画时间，代表满寿命时的总位移）
  final double speed;

  /// 粒子半径（像素，1..6 视觉范围）
  final double size;

  /// 粒子颜色（暖金色系）
  final Color color;

  /// 生命周期归一化比例（0..1）；<1 表示提前淡出
  final double life;

  const Particle({
    required this.angle,
    required this.speed,
    required this.size,
    required this.color,
    required this.life,
  });
}

/// 粒子爆发绘制器
///
/// 使用 `animationValue`（0..1）驱动整体进度，粒子当前位置由公式
/// `distance = speed * t * (1 - 0.5 * t)` 计算，模拟初快后慢的物理感。
/// 粒子的半径随寿命缩小，透明度线性衰减至 0，尾部带柔光模糊。
class ParticlesPainter extends CustomPainter {
  final List<Particle> particles;

  /// 动画归一化进度：0 → 1
  final double animationValue;

  /// 粒子发射中心（相对于画布左上角）
  final Offset origin;

  const ParticlesPainter({
    required this.particles,
    required this.animationValue,
    required this.origin,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (particles.isEmpty) return;
    final t = animationValue.clamp(0.0, 1.0);
    if (t >= 1.0) return;

    for (final p in particles) {
      // 每颗粒子按自身 life 拥有独立的相对寿命
      final lt = (t / p.life).clamp(0.0, 1.0);
      if (lt >= 1.0) continue;

      // 距离 = speed * t * (1 - 0.5 * t) —— 二次缓出
      final distance = p.speed * lt * (1 - 0.5 * lt);
      final dx = origin.dx + cos(p.angle) * distance;
      final dy = origin.dy + sin(p.angle) * distance;

      // 半径随寿命收缩（保留 60% 尾径）
      final radius = p.size * (1.0 - 0.4 * lt);
      // 透明度线性淡出
      final opacity = (1.0 - lt).clamp(0.0, 1.0);

      final paint = Paint()
        ..color = p.color.withValues(alpha: opacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.55)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(dx, dy), radius, paint);

      // 核心亮点：不透明小圆，增强"火花"感
      if (lt < 0.4) {
        final corePaint = Paint()
          ..color = Color.lerp(const Color(0xFFFFFFFF), p.color, lt / 0.4)!
              .withValues(alpha: (1.0 - lt / 0.4) * 0.9);
        canvas.drawCircle(Offset(dx, dy), radius * 0.4, corePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant ParticlesPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        !identical(oldDelegate.particles, particles) ||
        oldDelegate.origin != origin;
  }
}
