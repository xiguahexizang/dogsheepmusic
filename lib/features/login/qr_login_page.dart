import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/theme.dart';
import '../../core/bili_api/auth.dart';
import '../../core/providers.dart';

// ─── 内部页面状态 ────────────────────────────────────────────────────────────

enum _QrPageState { loading, waiting, scanned, confirmed, expired, error }

// ─── 扫码登录页 ──────────────────────────────────────────────────────────────

/// Bilibili 扫码登录页
///
/// 功能：
/// - 调用 [BiliAuth.generateQrCode] 获取二维码 URL，使用 qr_flutter 渲染
/// - 每 2 秒调用 [BiliAuth.pollQrStatus] 轮询状态
/// - 支持 waiting → scanned → confirmed / expired 状态流转
/// - 登录成功自动存储 Cookie 并跳转首页
/// - 底部提供"手动输入 Cookie"备选入口
class QrLoginPage extends ConsumerStatefulWidget {
  const QrLoginPage({super.key});

  @override
  ConsumerState<QrLoginPage> createState() => _QrLoginPageState();
}

class _QrLoginPageState extends ConsumerState<QrLoginPage>
    with TickerProviderStateMixin {
  _QrPageState _state = _QrPageState.loading;
  String? _qrUrl;
  String? _qrcodeKey;
  Timer? _pollTimer;

  // 扫描线动画（0.0 → 1.0 → 0.0，持续 2.2 秒）
  late final AnimationController _scanCtrl;
  // 卡片外发光呼吸动画
  late final AnimationController _glowCtrl;

  @override
  void initState() {
    super.initState();
    _scanCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _generate());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _scanCtrl.dispose();
    _glowCtrl.dispose();
    super.dispose();
  }

  // ── 生成二维码 ────────────────────────────────────────────────────────────

  Future<void> _generate() async {
    _stopScan();
    setState(() {
      _state = _QrPageState.loading;
      _qrUrl = null;
      _qrcodeKey = null;
    });

    final auth = ref.read(biliAuthProvider);
    final result = await auth.generateQrCode();

    if (!mounted) return;

    if (result == null) {
      setState(() => _state = _QrPageState.error);
      return;
    }

    setState(() {
      _qrUrl = result.url;
      _qrcodeKey = result.qrcodeKey;
      _state = _QrPageState.waiting;
    });

    _startScan();
    _startPolling();
  }

  // ── 扫描线 + 发光控制 ──────────────────────────────────────────────────────

  void _startScan() {
    _scanCtrl.repeat(reverse: true);
    _glowCtrl.repeat(reverse: true);
  }

  void _stopScan() {
    _scanCtrl.stop();
    _glowCtrl.stop();
    _scanCtrl.value = 0.0;
    _glowCtrl.value = 0.0;
  }

  // ── 轮询 ──────────────────────────────────────────────────────────────────

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _poll() async {
    if (_qrcodeKey == null) return;
    final auth = ref.read(biliAuthProvider);
    final result = await auth.pollQrStatus(_qrcodeKey!);
    if (!mounted) return;

    switch (result.status) {
      case QrPollStatus.waiting:
        if (_state != _QrPageState.waiting) {
          setState(() => _state = _QrPageState.waiting);
        }
      case QrPollStatus.scanned:
        _stopScan();
        _stopPolling();
        setState(() => _state = _QrPageState.scanned);
        // scanned 状态继续轮询确认（重启定时器）
        _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
      case QrPollStatus.confirmed:
        _stopScan();
        _stopPolling();
        setState(() => _state = _QrPageState.confirmed);
        await _onLoginSuccess();
      case QrPollStatus.expired:
        _stopScan();
        _stopPolling();
        setState(() => _state = _QrPageState.expired);
    }
  }

  // ── 登录成功处理 ──────────────────────────────────────────────────────────

  Future<void> _onLoginSuccess() async {
    final auth = ref.read(biliAuthProvider);
    final isVip = await auth.checkVipStatus();
    final profile = await auth.fetchProfile();
    if (!mounted) return;

    // 登录态变化：丢弃 WBI 密钥缓存，首页接口用最新密钥重新签名取数；
    // 首页 Hi-Res 候选池同步失效（音质探测结论保留，避免重发 playurl）
    ref.read(biliRecommendProvider).clearWbiCache();
    ref.read(musicRecommendProvider).resetForNewSession();

    ref.read(loginStatusProvider.notifier).state = LoginStatus.loggedIn;
    ref.read(vipStatusProvider.notifier).state = isVip;

    // 昵称 / 头像：首页问候与设置页账号卡片依赖这两个 Provider
    if (profile.isLoggedIn) {
      ref.read(userNicknameProvider.notifier).state = profile.nickname;
      ref.read(userAvatarProvider.notifier).state = profile.avatarUrl;
    }

    // 短暂展示"登录成功"后跳转
    await Future.delayed(const Duration(milliseconds: 900));
    if (mounted) context.go('/');
  }

  // ── 手动导入 Cookie ────────────────────────────────────────────────────────

  void _showManualCookieDialog() {
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: AppTheme.bgCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppTheme.divider),
          ),
          title: const Row(
            children: [
              Icon(Icons.cookie_outlined, color: AppTheme.accent, size: 20),
              SizedBox(width: 10),
              Text('手动输入 Cookie',
                  style: TextStyle(
                      color: AppTheme.textMain,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '请粘贴包含 SESSDATA 的 Bilibili Cookie 字符串',
                style: TextStyle(
                    color: AppTheme.textSub, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                maxLines: 4,
                minLines: 2,
                style: const TextStyle(
                    color: AppTheme.textMain,
                    fontSize: 12,
                    fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  hintText: 'SESSDATA=xxx; bili_jct=yyy; DedeUserID=zzz',
                  hintStyle: TextStyle(color: AppTheme.textSub, fontSize: 11),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消',
                  style: TextStyle(color: AppTheme.textSub, fontSize: 14)),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _importCookies(ctrl.text.trim());
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
              ),
              child: const Text('导入', style: TextStyle(fontSize: 14)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _importCookies(String raw) async {
    if (raw.isEmpty) return;
    final auth = ref.read(biliAuthProvider);
    final ok = await auth.importCookies(raw);
    if (!mounted) return;

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_outline, color: AppTheme.accent, size: 18),
            SizedBox(width: 8),
            Text('Cookie 导入成功，正在登录…',
                style: TextStyle(color: AppTheme.textMain)),
          ],
        ),
        backgroundColor: AppTheme.bgCard,
        duration: Duration(milliseconds: 600),
      ));
      await _onLoginSuccess();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Row(
          children: [
            Icon(Icons.error_outline, color: AppTheme.danger, size: 18),
            SizedBox(width: 8),
            Text('Cookie 无效或已过期，请重试',
                style: TextStyle(color: AppTheme.textMain)),
          ],
        ),
        backgroundColor: AppTheme.bgCard,
      ));
    }
  }

  // ── 构建 UI ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        // 浅渐变底（白色中 → 浅灰）
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.0, -0.45),
            radius: 1.4,
            colors: [Color(0xFFFFFFFF), Color(0xFFF5F6FA), Color(0xFFEBEDF3)],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              children: [
                const SizedBox(height: 16),
                _buildLogo(),
                const SizedBox(height: 24),
                _buildTitle(),
                const SizedBox(height: 32),
                _buildQrCard(),
                const SizedBox(height: 20),
                _buildStatusArea(),
                const SizedBox(height: 44),
                _buildOrDivider(),
                const SizedBox(height: 16),
                _buildManualCookieButton(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Logo ──────────────────────────────────────────────────────────────────

  Widget _buildLogo() {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.accentSoft, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accent.withValues(alpha: 0.12),
            blurRadius: 20,
            spreadRadius: 3,
          ),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/logo.png',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Center(
            child: Text('🐕🐑', style: TextStyle(fontSize: 28)),
          ),
        ),
      ),
    );
  }

  // ── 标题区域 ──────────────────────────────────────────────────────────────

  Widget _buildTitle() {
    return const Column(
      children: [
        Text(
          'DogSheep音乐',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppTheme.textMain,
            letterSpacing: 0.5,
          ),
        ),
        SizedBox(height: 6),
        Text(
          '请使用 Bilibili 手机 App 扫码登录',
          style: TextStyle(
            fontSize: 13,
            color: AppTheme.textSub,
            height: 1.5,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  // ── 二维码卡片（视觉主角）────────────────────────────────────────────────

  Widget _buildQrCard() {
    return AnimatedBuilder(
      animation: _glowCtrl,
      builder: (context, child) {
        final glowIntensity = _state == _QrPageState.waiting
            ? 0.25 + _glowCtrl.value * 0.2
            : 0.15;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.divider),
            boxShadow: [
              BoxShadow(
                color: AppTheme.accent.withValues(alpha: glowIntensity * 0.7),
                blurRadius: 32,
                spreadRadius: 6,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // 角落装饰括框
              Positioned(
                top: -2,
                left: -2,
                right: -2,
                bottom: -2,
                child: CustomPaint(painter: _CornerBracketPainter()),
              ),
              // QR 码或占位符
              SizedBox(
                width: 200,
                height: 200,
                child: _buildQrContent(),
              ),
              // 扫描线（仅 waiting 状态）——使用 Align 定位，避免嵌套 Positioned
              if (_state == _QrPageState.waiting)
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: AnimatedBuilder(
                        animation: _scanCtrl,
                        builder: (context, _) {
                          // _scanCtrl: 0.0(顶部) → 1.0(底部)，reverse:true 往复
                          final alignY = _scanCtrl.value * 2.0 - 1.0;
                          return Align(
                            alignment: Alignment(0.0, alignY),
                            child: Container(
                              height: 2,
                              width: double.infinity,
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.transparent,
                                    AppTheme.accent.withValues(alpha: 0.9),
                                    Colors.transparent,
                                  ],
                                  stops: const [0.0, 0.5, 1.0],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        AppTheme.accent.withValues(alpha: 0.7),
                                    blurRadius: 14,
                                    spreadRadius: 3,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              // 已扫描覆盖层
              if (_state == _QrPageState.scanned) _buildScannedOverlay(),
              // 已过期覆盖层
              if (_state == _QrPageState.expired) _buildExpiredOverlay(),
              // 成功覆盖层
              if (_state == _QrPageState.confirmed) _buildConfirmedOverlay(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQrContent() {
    switch (_state) {
      case _QrPageState.loading:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppTheme.accent.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '加载中…',
                style: TextStyle(color: AppTheme.textSub, fontSize: 13),
              ),
            ],
          ),
        );
      case _QrPageState.error:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded,
                  size: 40, color: AppTheme.textSub),
              const SizedBox(height: 10),
              const Text(
                '网络异常\n请检查连接后重试',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppTheme.textSub, fontSize: 13, height: 1.6),
              ),
              const SizedBox(height: 14),
              TextButton(
                onPressed: _generate,
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.accent,
                  backgroundColor: const Color(0x18F5A623),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text('重新加载', style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
        );
      default:
        if (_qrUrl == null) return const SizedBox(width: 200, height: 200);
        return QrImageView(
          data: _qrUrl!,
          version: QrVersions.auto,
          size: 200,
          backgroundColor: Colors.white,
          eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: Color(0xFF1A1A2E),
          ),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: Color(0xFF1A1A2E),
          ),
          padding: EdgeInsets.zero,
          errorStateBuilder: (ctx, err) => const Center(
            child: Icon(Icons.error_outline, color: AppTheme.textSub, size: 36),
          ),
        );
    }
  }

  Widget _buildScannedOverlay() {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFE8F9EF).withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF00B578).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  size: 36, color: Color(0xFF00A86B)),
            ),
            const SizedBox(height: 12),
            const Text(
              '已扫码\n请在手机上确认登录',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF1A7A4A),
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpiredOverlay() {
    return Positioned.fill(
      child: GestureDetector(
        onTap: _generate,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.refresh_rounded,
                    size: 36, color: AppTheme.accentDim),
              ),
              const SizedBox(height: 12),
              const Text(
                '二维码已过期',
                style: TextStyle(
                  color: AppTheme.textMain,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '点击刷新',
                style: TextStyle(
                  color: AppTheme.accentDim,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConfirmedOverlay() {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFE0FFF0).withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF00C853).withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.verified_rounded,
                  size: 44, color: Color(0xFF00A86B)),
            ),
            const SizedBox(height: 14),
            const Text(
              '登录成功！',
              style: TextStyle(
                color: Color(0xFF00A86B),
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 状态文字区域（轮询状态提示 / 刷新按钮）────────────────────────────────

  Widget _buildStatusArea() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeIn,
      switchOutCurve: Curves.easeOut,
      child: switch (_state) {
        _QrPageState.waiting => const _StatusHint(
            key: ValueKey('waiting'),
            icon: Icons.qr_code_scanner_rounded,
            color: AppTheme.textSub,
            text: '等待扫码…',
          ),
        _QrPageState.scanned => const _StatusHint(
            key: ValueKey('scanned'),
            icon: Icons.phone_android_rounded,
            color: Color(0xFF00A86B),
            text: '已扫码，请在手机上确认',
          ),
        _QrPageState.confirmed => const _StatusHint(
            key: ValueKey('confirmed'),
            icon: Icons.check_circle_rounded,
            color: Color(0xFF00A86B),
            text: '登录成功，正在跳转…',
          ),
        _QrPageState.expired => _ExpiredStatus(
            key: const ValueKey('expired'),
            onRefresh: _generate,
          ),
        _QrPageState.error => const _StatusHint(
            key: ValueKey('error'),
            icon: Icons.error_outline_rounded,
            color: AppTheme.danger,
            text: '获取二维码失败，请重试',
          ),
        _QrPageState.loading => const SizedBox.shrink(key: ValueKey('loading')),
      },
    );
  }

  // ── "── 或 ──" 分割线 ─────────────────────────────────────────────────────

  Widget _buildOrDivider() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1,
            color: AppTheme.divider,
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            '或',
            style: TextStyle(
              color: AppTheme.textSub,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 1,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 1,
            color: AppTheme.divider,
          ),
        ),
      ],
    );
  }

  // ── 手动输入 Cookie 按钮 ──────────────────────────────────────────────────

  Widget _buildManualCookieButton() {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: OutlinedButton.icon(
        onPressed: _showManualCookieDialog,
        icon: const Icon(Icons.edit_note_rounded, size: 18),
        label: const Text(
          '无法扫码？手动输入 Cookie',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.textSub,
          side: const BorderSide(color: AppTheme.divider),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radius),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
        ),
      ),
    );
  }
}

// ─── 状态提示组件 ────────────────────────────────────────────────────────────

class _StatusHint extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _StatusHint({
    super.key,
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

class _ExpiredStatus extends StatelessWidget {
  final VoidCallback onRefresh;

  const _ExpiredStatus({super.key, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton.icon(
        onPressed: onRefresh,
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: const Text('二维码已过期，点击刷新'),
        style: TextButton.styleFrom(
          foregroundColor: AppTheme.accent,
          backgroundColor: AppTheme.accent.withValues(alpha: 0.08),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: AppTheme.accent.withValues(alpha: 0.3)),
          ),
        ),
      ),
    );
  }
}

// ─── 角落装饰括框 Painter ────────────────────────────────────────────────────

/// 在二维码卡片四角绘制扫描框风格的 L 形装饰线
class _CornerBracketPainter extends CustomPainter {
  static const double _bracketLen = 20.0;
  static const double _strokeW = 2.5;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.accent.withValues(alpha: 0.6)
      ..strokeWidth = _strokeW
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;

    // ── 左上
    canvas.drawLine(const Offset(0, _bracketLen), const Offset(0, 0), paint);
    canvas.drawLine(const Offset(0, 0), const Offset(_bracketLen, 0), paint);

    // ── 右上
    canvas.drawLine(Offset(w - _bracketLen, 0), Offset(w, 0), paint);
    canvas.drawLine(Offset(w, 0), Offset(w, _bracketLen), paint);

    // ── 左下
    canvas.drawLine(Offset(0, h - _bracketLen), Offset(0, h), paint);
    canvas.drawLine(Offset(0, h), Offset(_bracketLen, h), paint);

    // ── 右下
    canvas.drawLine(Offset(w - _bracketLen, h), Offset(w, h), paint);
    canvas.drawLine(Offset(w, h - _bracketLen), Offset(w, h), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
