
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:dog_sheep_player/app/theme.dart';
import 'package:dog_sheep_player/core/bili_api/auth.dart';
import 'package:dog_sheep_player/core/providers.dart';

/// 首次启动密码输入页
///
/// 当 [SecureBox.hasPassword()] 返回 false 时，路由跳转至本页面。
/// 用户输入 Bilibili 账号密码后，调用 [BiliAuth.loginWithPassword] 登录，
/// 成功后将密码存入 SecureBox，并跳转首页。
class PasswordSetupPage extends ConsumerStatefulWidget {
  const PasswordSetupPage({super.key});

  @override
  ConsumerState<PasswordSetupPage> createState() => _PasswordSetupPageState();
}

class _PasswordSetupPageState extends ConsumerState<PasswordSetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;
  String? _errorMsg;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  /// 手机号脱敏显示
  String get _maskedPhone {
    const phone = BiliAuth.phone;
    return '${phone.substring(0, 3)}****${phone.substring(7)}';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _errorMsg = null;
    });

    final password = _passwordCtrl.text;
    final auth = ref.read(biliAuthProvider);
    final secureBox = ref.read(secureBoxProvider);

    final result = await auth.loginWithPassword(password);

    if (!mounted) return;

    if (result == LoginResult.success) {
      // 登录成功：持久化密码和 Cookie
      await secureBox.savePassword(password);
      final cookies = auth.cookies;
      if (cookies.isNotEmpty) {
        await secureBox.saveCookies(cookies);
      }
      // 更新登录状态
      ref.read(loginStatusProvider.notifier).state = LoginStatus.loggedIn;

      if (!mounted) return;
      // 跳转首页，替换掉密码设置页（不可返回）
      context.go('/');
    } else {
      setState(() {
        _submitting = false;
        _errorMsg = switch (result) {
          LoginResult.wrongPassword => '密码错误，请重新输入',
          LoginResult.needCaptcha => '需要验证码，请在浏览器中登录后手动导入 Cookie',
          LoginResult.networkError => '网络错误，请检查网络后重试',
          LoginResult.cookieExpired => 'Cookie 已过期，请重试',
          LoginResult.success => '',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo
                _buildLogo(),
                const SizedBox(height: 32),

                // 标题
                Text(
                  'DogSheep音乐',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  '请输入 Bilibili 账号密码',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textSub,
                      ),
                ),
                const SizedBox(height: 6),

                // 脱敏手机号
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.bgCard,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.divider),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.phone_rounded,
                          size: 16, color: AppTheme.textSub),
                      const SizedBox(width: 8),
                      Text(
                        _maskedPhone,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.textMain,
                          letterSpacing: 1.0,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // 密码表单
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _passwordCtrl,
                        obscureText: _obscure,
                        autofocus: true,
                        style: const TextStyle(fontSize: 16),
                        decoration: InputDecoration(
                          labelText: '账号密码',
                          hintText: '请输入 Bilibili 登录密码',
                          prefixIcon:
                              const Icon(Icons.lock_outline_rounded, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 20,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                          errorText: _errorMsg,
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return '密码不能为空';
                          if (v.length < 4) return '密码长度不足';
                          return null;
                        },
                        onFieldSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: _submitting ? null : _submit,
                          icon: _submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.login_rounded, size: 20),
                          label: Text(
                            _submitting ? '登录中...' : '确认登录',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.accent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radius),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // 提示文字
                Text(
                  '首次登录后密码将被安全加密存储，下次启动自动登录。\n手机号已内置，只需输入对应密码即可。',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSub,
                        height: 1.6,
                      ),
                ),

                // 手动导入 Cookie 入口
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () {
                    // 跳转设置页的 Cookie 导入区（通过路由传参）
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('请先完成首次登录后，在「设置 → 调试」中手动导入 Cookie'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  icon: const Icon(Icons.cookie_rounded, size: 16),
                  label: const Text('无法登录？尝试手动导入 Cookie'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.textSub,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.accent, width: 2),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accent.withValues(alpha: 0.2),
            blurRadius: 32,
            spreadRadius: 4,
          ),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/logo.png',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const _FallbackLogo(),
        ),
      ),
    );
  }
}

class _FallbackLogo extends StatelessWidget {
  const _FallbackLogo();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '🐕🐑',
        style: TextStyle(fontSize: 40),
      ),
    );
  }
}
