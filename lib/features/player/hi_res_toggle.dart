/// Hi-Res 炫酷音质开关
///
/// 完全自定义胶囊开关，串联多段动画：
/// - OFF：浅灰底 + 灰字 + 呼吸（opacity 0.6~0.8，周期 3s）
/// - ON：暖金渐变底 + 深色金属字 + 循环光泽扫描
/// - OFF→ON：粒子爆发 + 光环脉冲 + 中震反馈
/// - ON→OFF：粒子不播放，淡出回灰 + 轻震反馈
/// 状态经 [hiResEnabledProvider] 读写，同步 [DogSheepAudioHandler] 无缝续播，
/// 并持久化到 [SecureBox]。非大会员或该曲目无 Hi-Res 轨时进入禁用态。
library;

import 'dart:math';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dog_sheep_player/core/providers.dart';
import 'package:dog_sheep_player/features/player/hi_res_available_provider.dart';
import 'package:dog_sheep_player/features/player/particles_painter.dart';

/// Hi-Res 音质开关组件
class HiResToggle extends ConsumerStatefulWidget {
  const HiResToggle({super.key});

  @override
  ConsumerState<HiResToggle> createState() => _HiResToggleState();
}

class _HiResToggleState extends ConsumerState<HiResToggle>
    with TickerProviderStateMixin {
  static const double _capsuleW = 120;
  static const double _capsuleH = 40;
  static const double _radius = 20;

  // 布局预留区，为粒子爆发与光环阴影留出溢出空间
  static const double _fieldW = 210;
  static const double _fieldH = 104;

  static const Color _offBg = Color(0xFFE8E8E8);
  static const Color _offText = Color(0xFF9A9AA5);
  static const Color _onText = Color(0xFF1A1A2E);
  static const Color _gold = Color(0xFFF5A623);
  static const Color _goldBright = Color(0xFFFFD700);

  // OFF 呼吸：1.5s 单程（去 + 回 = 3s 周期）
  late final AnimationController _breath;
  // ON 持续：金属光泽循环扫描，3s 周期（约前 1s 扫过，后 2s 间隔）
  late final AnimationController _shine;
  // 触发式：粒子爆发（600ms，仅 ON 触发时播放一次）
  late final AnimationController _particles;
  // 触发式：光环脉冲（2 次，共约 800ms）
  late final AnimationController _halo;
  // 状态过渡：0=OFF 1=ON，驱动底色与文字色插值
  late final AnimationController _state;

  final Random _rng = Random();
  List<Particle> _burst = const [];

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _shine = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    _particles = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _halo = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _state = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      value: ref.read(hiResEnabledProvider) ? 1 : 0,
    );

    _applyLoops(_state.value > 0.5);
    // 粒子爆发结束后清除覆盖层，避免常驻重绘
    _particles.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _burst = const [];
        if (mounted) setState(() {});
      }
    });
    _restorePersisted();
  }

  /// 初始化时从加密箱读取上次状态
  Future<void> _restorePersisted() async {
    final secure = ref.read(secureBoxProvider);
    final stored = await secure.getHiResEnabled();
    if (!mounted) return;
    // 始终以持久化结果为准，同步音频处理器（切换时自动无缝续播）
    ref.read(audioHandlerProvider).hiResEnabled = stored;
    if (stored != ref.read(hiResEnabledProvider)) {
      ref.read(hiResEnabledProvider.notifier).state = stored;
      _state.value = stored ? 1 : 0;
      _applyLoops(stored);
      setState(() {});
    }
  }

  /// 依据开关状态管理常驻动画（呼吸 vs 光泽）
  void _applyLoops(bool on) {
    if (on) {
      if (_breath.isAnimating) _breath.stop();
      if (!_shine.isAnimating) _shine.repeat();
    } else {
      _shine.stop();
      if (!_breath.isAnimating) _breath.repeat(reverse: true);
    }
  }

  void _toggle() {
    final enabled = ref.read(hiResEnabledProvider);
    final next = !enabled;

    ref.read(hiResEnabledProvider.notifier).state = next;
    // 无缝续播 + 持久化（各自 fire-and-forget，内部已容错）
    ref.read(audioHandlerProvider).hiResEnabled = next;
    // ignore: unawaited_futures, discarded_futures
    ref.read(secureBoxProvider).saveHiResEnabled(next);

    if (next) {
      _startOnEffects();
    } else {
      _startOffEffects();
    }
  }

  void _startOnEffects() {
    // c) 震感反馈：中震
    HapticFeedback.mediumImpact();
    // a) 粒子爆发 + d) 光环脉冲
    _burst = _generateBurst();
    _particles.forward(from: 0);
    _halo.forward(from: 0);
    // b) 金属光泽：从头开始循环（前 1s 扫过，后 2s 间隔，周期 3s）
    _breath.stop();
    _shine
      ..value = 0
      ..repeat();
    _state.forward();
  }

  void _startOffEffects() {
    // 轻震
    HapticFeedback.lightImpact();
    // OFF 触发：不播放粒子，仅淡出
    _particles.stop();
    _halo.stop();
    _shine.stop();
    _burst = const [];
    _state.reverse().then((_) {
      if (mounted && !ref.read(hiResEnabledProvider)) {
        _breath.repeat(reverse: true);
      }
    });
  }

  /// 生成 5-8 颗暖金色粒子
  List<Particle> _generateBurst() {
    const palette = <Color>[_gold, _goldBright, Color(0xFFFFA500)];
    final count = 5 + _rng.nextInt(4); // 5..8
    return List.generate(count, (_) {
      return Particle(
        angle: _rng.nextDouble() * pi * 2,
        speed: 34 + _rng.nextDouble() * 42, // 34..76 → 最大位移 ~38px
        size: 3 + _rng.nextDouble() * 3, // 3..6
        color: palette[_rng.nextInt(palette.length)],
        life: 0.7 + _rng.nextDouble() * 0.3,
      );
    });
  }

  @override
  void dispose() {
    _breath.dispose();
    _shine.dispose();
    _particles.dispose();
    _halo.dispose();
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final available = ref.watch(hiResAvailableProvider);

    return Opacity(
      opacity: available ? 1 : 0.4,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: _fieldW,
            height: _fieldH,
            child: _buildField(available),
          ),
          if (!available) ...[
            const SizedBox(height: 2),
            const Text(
              '需要大会员',
              style: TextStyle(
                fontSize: 11,
                color: _offText,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildField(bool available) {
    return AnimatedBuilder(
      animation: Listenable.merge([_state, _breath, _shine, _particles, _halo]),
      builder: (context, _) {
        final t = _state.value; // 0 OFF .. 1 ON
        final breathing = 0.6 + 0.2 * Curves.easeInOut.transform(_breath.value);
        final capsuleOpacity = lerpDouble(breathing, 1.0, t)!.clamp(0.0, 1.0);

        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // d) 光环脉冲阴影层
            _buildHalo(t),
            // 开关本体
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: available ? _toggle : null,
              child: Opacity(
                opacity: capsuleOpacity,
                child: _buildCapsule(t),
              ),
            ),
            // a) 粒子爆发覆盖层（仅触发时运行）
            if (_particles.isAnimating || _burst.isNotEmpty)
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: ParticlesPainter(
                        particles: _burst,
                        animationValue: _particles.value,
                        origin: const Offset(_fieldW / 2, _fieldH / 2),
                      ),
                      size: Size.zero,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// 光环脉冲：0→25→0 两次脉冲，叠加 ON 常驻微光
  Widget _buildHalo(double t) {
    final pulse = _halo.isAnimating ? _halo.value : 0.0;
    // 双脉冲包络：sin 半波两次（周期 400ms，共 800ms）
    final env = sin(pulse * pi * 2).abs();
    final steady = t * 6.0; // ON 常驻微弱阴影
    final blur = steady + 25 * env;
    if (blur < 1) return const SizedBox.shrink();
    return SizedBox(
      width: _capsuleW,
      height: _capsuleH,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_radius),
          boxShadow: [
            BoxShadow(
              color: _gold.withValues(alpha: 0.35 + 0.45 * env),
              blurRadius: blur,
              spreadRadius: 1 + 2 * env,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCapsule(double t) {
    final textColor = Color.lerp(_offText, _onText, t) ?? _offText;

    return SizedBox(
      width: _capsuleW,
      height: _capsuleH,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // OFF 浅灰底
          Positioned.fill(
            child: Opacity(
              opacity: (1 - t).clamp(0.0, 1.0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _offBg,
                  borderRadius: BorderRadius.circular(_radius),
                ),
              ),
            ),
          ),
          // ON 暖金渐变底
          Positioned.fill(
            child: Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(_radius),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_gold, _goldBright, _gold],
                    stops: [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
          ),
          // Hi-Res 文字（含金属光泽叠加）
          _buildLabel(textColor, t),
        ],
      ),
    );
  }

  /// "Hi-Res" 居中文字 + ON 态 ShaderMask 金属光泽扫描
  Widget _buildLabel(Color textColor, double t) {
    const labelStyle = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.2,
      height: 1.0,
    );
    final base = Text(
      'Hi-Res',
      style: labelStyle.copyWith(color: textColor),
    );
    if (t < 0.02) return base;

    // 光泽扫描：前 1/3 周期内高光中心由 -1.3 平移到 1.3（约 1s），
    // 其余 2/3 周期将高光移出文字区形成约 2s 的间隔。
    final s = _shine.value;
    final center = s < 1 / 3 ? -1.3 + 2.6 * (s * 3) : 3.0;
    return Stack(
      alignment: Alignment.center,
      children: [
        base,
        Opacity(
          opacity: t, // 仅在 ON 态显现
          child: ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (rect) {
              return LinearGradient(
                begin: Alignment(center - 0.34, -0.4),
                end: Alignment(center + 0.34, 0.4),
                colors: const [
                  Color(0x00FFFFFF),
                  Color(0x99FFFFFF),
                  Color(0x00FFFFFF),
                ],
                stops: const [0.0, 0.5, 1.0],
              ).createShader(rect);
            },
            child: Text(
              'Hi-Res',
              style: labelStyle.copyWith(color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
