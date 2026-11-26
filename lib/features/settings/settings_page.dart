import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import 'package:dog_sheep_player/app/theme.dart';
import 'package:dog_sheep_player/core/bili_api/auth.dart';
import 'package:dog_sheep_player/core/providers.dart';
import 'package:dog_sheep_player/shared/cover_image.dart';

// ─── 设置页 Provider（账号信息缓存）────────────────────────────────────────

/// 账号信息数据
class AccountInfo {
  final bool isLoggedIn;
  final bool isVip;
  final String? nickname;
  final String? avatarUrl;

  const AccountInfo({
    this.isLoggedIn = false,
    this.isVip = false,
    this.nickname,
    this.avatarUrl,
  });
}

/// 缓存账号信息 Provider（每次进入设置页刷新）
final _accountInfoProvider = FutureProvider<AccountInfo>((ref) async {
  final auth = ref.watch(biliAuthProvider);
  final loggedIn = await auth.checkLoginStatus();
  final vip = loggedIn && await auth.checkVipStatus();
  return AccountInfo(
    isLoggedIn: loggedIn,
    isVip: vip,
    nickname: ref.watch(userNicknameProvider),
    avatarUrl: ref.watch(userAvatarProvider),
  );
});

/// Hi-Res 默认开关持久化 Provider
final _defaultHiResProvider = StateProvider<bool>((ref) => true);

// ─── 设置页主组件 ────────────────────────────────────────────────────────────

/// 设置页 — 账号、安全、播放、存储、关于、调试
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountAsync = ref.watch(_accountInfoProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        // 浅灰底 + 白色卡片分组
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // 账号信息区
          accountAsync.when(
            loading: () => const _AccountSectionLoading(),
            error: (_, __) => _AccountSectionError(),
            data: (info) => _AccountSection(info: info),
          ),

          const SizedBox(height: 18),

          // 安全
          const _SectionTitle(label: '安全'),
          _SecuritySection(ref: ref),
          const SizedBox(height: 18),

          // 播放
          const _SectionTitle(label: '播放'),
          _PlaybackSection(ref: ref),
          const SizedBox(height: 18),

          // 存储
          const _SectionTitle(label: '存储'),
          _StorageSection(ref: ref),
          const SizedBox(height: 18),

          // 关于
          const _SectionTitle(label: '关于'),
          const _AboutSection(),
          const SizedBox(height: 18),

          // 调试
          const _SectionTitle(label: '调试'),
          _DebugSection(ref: ref),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ─── 账号信息区 ──────────────────────────────────────────────────────────────

class _AccountSectionLoading extends StatelessWidget {
  const _AccountSectionLoading();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.cardDecoration(),
      padding: const EdgeInsets.all(20),
      child: const Row(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppTheme.accent),
              ),
            ),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Text('加载账号信息...', style: TextStyle(color: AppTheme.textSub)),
          ),
        ],
      ),
    );
  }
}

class _AccountSectionError extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _AccountSection extends StatelessWidget {
  final AccountInfo info;
  const _AccountSection({required this.info});

  /// 手机号脱敏：13468676878 → 134****6878
  String get _maskedPhone {
    const phone = BiliAuth.phone;
    if (phone.length != 11) return phone;
    return '${phone.substring(0, 3)}****${phone.substring(7)}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.cardDecoration(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(
        children: [
          // 头像
          Container(
            width: 60,
            height: 60,
            // Border.all 是普通工厂（非 const），因此整体不能声明为 const
            decoration: BoxDecoration(
              color: AppTheme.bgPrimary,
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.divider),
            ),
            child: ClipOval(
              child: info.avatarUrl != null && info.avatarUrl!.isNotEmpty
                  ? Image.network(
                      // Web 端必须走 dev_proxy 改写地址，否则头像被 CORS/防盗链拦下
                      CoverImage.normalize(info.avatarUrl!) ?? '',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const _DefaultAvatar(),
                    )
                  : const _DefaultAvatar(),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.nickname?.isNotEmpty == true
                      ? info.nickname!
                      : 'DogSheep音乐用户',
                  style: Theme.of(context).textTheme.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  _maskedPhone,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppTheme.textSub),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _StatusChip(
                      label: info.isLoggedIn ? '已登录' : '未登录',
                      positive: info.isLoggedIn,
                    ),
                    _StatusChip(
                      label: info.isVip ? '大会员 ✓' : '大会员 ✗',
                      positive: info.isVip,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DefaultAvatar extends StatelessWidget {
  const _DefaultAvatar();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/logo.png',
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const Icon(
        Icons.person_rounded,
        size: 32,
        color: AppTheme.textSub,
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final bool positive;
  const _StatusChip({required this.label, required this.positive});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: positive ? const Color(0xFFE6F4EC) : const Color(0xFFFDECEA),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: positive ? const Color(0xFFB7E0C8) : const Color(0xFFF3C4BE),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: positive ? AppTheme.success : AppTheme.danger,
        ),
      ),
    );
  }
}

// ─── 安全区 ──────────────────────────────────────────────────────────────────

class _SecuritySection extends StatelessWidget {
  final WidgetRef ref;
  const _SecuritySection({required this.ref});

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      children: [
        _SettingsTile(
          icon: Icons.qr_code_2_rounded,
          title: '重新扫码登录',
          subtitle: '清除当前 Cookie，重新通过 Bilibili App 扫码',
          onTap: () => _showReLoginDialog(context, ref),
        ),
      ],
    );
  }

  Future<void> _showReLoginDialog(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.divider),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.accent, size: 22),
            SizedBox(width: 10),
            Text('重新登录',
                style: TextStyle(
                    color: AppTheme.textMain,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
          ],
        ),
        content: const Text(
          '将清除当前登录的 Cookie 信息，\n'
          '跳转至扫码页面重新登录。\n\n'
          '确定继续？',
          style: TextStyle(color: AppTheme.textSub, fontSize: 14, height: 1.7),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消',
                style: TextStyle(color: AppTheme.textSub, fontSize: 14)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('确定并重新登录', style: TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    // 清除 Cookie 并跳转扫码登录页
    final auth = ref.read(biliAuthProvider);
    await auth.logout();
    if (!context.mounted) return;

    ref.read(loginStatusProvider.notifier).state = LoginStatus.loggedOut;
    context.go('/login');
  }
}

// ─── 播放区 ──────────────────────────────────────────────────────────────────

class _PlaybackSection extends ConsumerWidget {
  final WidgetRef ref;
  const _PlaybackSection({required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hiResEnabled = ref.watch(hiResEnabledProvider);
    final defaultHiRes = ref.watch(_defaultHiResProvider);
    final secureBox = ref.read(secureBoxProvider);

    return _SettingsCard(
      children: [
        // Hi-Res 当前状态（只读）
        _SettingsTile(
          icon: Icons.high_quality_rounded,
          title: 'Hi-Res 音质',
          subtitle: hiResEnabled ? '当前已开启（Hi-Res 无损音质）' : '当前已关闭（标准音质）',
          trailing: Icon(
            hiResEnabled ? Icons.check_circle : Icons.radio_button_unchecked,
            color: hiResEnabled ? AppTheme.accent : AppTheme.textSub,
          ),
          onTap: () => context.push('/player'),
        ),
        // 默认开启 Hi-Res 开关
        _SettingsTile(
          icon: Icons.tune_rounded,
          title: '默认开启 Hi-Res',
          subtitle: '启动后自动使用 Hi-Res 音质',
          trailing: Switch(
            value: defaultHiRes,
            onChanged: (val) async {
              ref.read(_defaultHiResProvider.notifier).state = val;
              await secureBox.saveHiResEnabled(val);
              ref.read(hiResEnabledProvider.notifier).state = val;
            },
          ),
        ),
      ],
    );
  }
}

// ─── 存储区 ──────────────────────────────────────────────────────────────────

class _StorageSection extends ConsumerStatefulWidget {
  final WidgetRef ref;
  const _StorageSection({required this.ref});

  @override
  ConsumerState<_StorageSection> createState() => _StorageSectionState();
}

class _StorageSectionState extends ConsumerState<_StorageSection> {
  String _cacheSize = '计算中...';
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _calcCacheSize();
  }

  Future<void> _calcCacheSize() async {
    try {
      final dir = await _getCacheDir();
      final bytes = await _getDirSize(dir);
      if (!mounted) return;
      setState(() {
        _cacheSize = bytes == 0 ? '无缓存' : _formatSize(bytes);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cacheSize = '未知');
    }
  }

  Future<Directory> _getCacheDir() async {
    // 使用临时目录作为缓存估算目录
    final dir = await getTemporaryDirectory();
    return dir;
  }

  Future<int> _getDirSize(Directory dir) async {
    int size = 0;
    try {
      await for (final entity
          in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          size += await entity.length();
        }
      }
    } catch (_) {}
    return size;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1073741824) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    return '${(bytes / 1073741824).toStringAsFixed(2)} GB';
  }

  Future<void> _clearCache() async {
    setState(() => _clearing = true);
    try {
      // 清除临时目录（包含图片缓存）
      final dir = await _getCacheDir();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
      }

      if (!mounted) return;
      setState(() => _cacheSize = '无缓存');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('缓存已清除'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('清除失败: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppTheme.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      children: [
        _SettingsTile(
          icon: Icons.storage_rounded,
          title: '缓存大小',
          subtitle: _cacheSize,
        ),
        _SettingsTile(
          icon: Icons.delete_outline_rounded,
          title: '清除缓存',
          subtitle: '清除图片缓存与临时数据',
          trailing: _clearing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          onTap: _clearing ? null : _clearCache,
        ),
      ],
    );
  }
}

// ─── 关于区 ──────────────────────────────────────────────────────────────────

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    return const _SettingsCard(
      children: [
        _SettingsTile(
          icon: Icons.apps_rounded,
          title: '应用名称',
          subtitle: 'DogSheep音乐',
        ),
        _SettingsTile(
          icon: Icons.info_outline_rounded,
          title: '版本',
          subtitle: '1.0.0',
        ),
        _SettingsTile(
          icon: Icons.account_circle_outlined,
          title: '账号类型',
          subtitle: '基于 Bilibili 大会员账号（仅供个人使用）',
        ),
      ],
    );
  }
}

// ─── 调试区（手动导入 Cookie）────────────────────────────────────────────────

class _DebugSection extends ConsumerStatefulWidget {
  final WidgetRef ref;
  const _DebugSection({required this.ref});

  @override
  ConsumerState<_DebugSection> createState() => _DebugSectionState();
}

class _DebugSectionState extends ConsumerState<_DebugSection> {
  bool _showCookieImport = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingsCard(
          children: [
            _SettingsTile(
              icon: Icons.cookie_rounded,
              title: '手动导入 Cookie',
              subtitle: '当账密登录被验证码拦截时的备选方案',
              trailing: Icon(
                _showCookieImport
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                color: AppTheme.textSub,
              ),
              onTap: () =>
                  setState(() => _showCookieImport = !_showCookieImport),
            ),
          ],
        ),
        if (_showCookieImport)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _CookieImportPanel(ref: widget.ref),
          ),
      ],
    );
  }
}

class _CookieImportPanel extends ConsumerStatefulWidget {
  final WidgetRef ref;
  const _CookieImportPanel({required this.ref});

  @override
  ConsumerState<_CookieImportPanel> createState() => _CookieImportPanelState();
}

class _CookieImportPanelState extends ConsumerState<_CookieImportPanel> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _result;
  bool _success = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final cookieStr = _ctrl.text.trim();
    if (cookieStr.isEmpty) {
      setState(() {
        _result = '请输入 Cookie 字符串';
        _success = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _result = null;
    });

    final auth = widget.ref.read(biliAuthProvider);
    final ok = await auth.importCookies(cookieStr);

    if (!mounted) return;
    setState(() {
      _loading = false;
      _success = ok;
      _result = ok ? '✓ Cookie 导入成功，登录状态已更新' : '✗ Cookie 无效或已过期，导入失败';
    });
    // 导入成功后失效账号信息，让设置页重新拉取 nav
    if (ok) {
      widget.ref.invalidate(_accountInfoProvider);
      // 首页 Hi-Res 推荐也需要用新会话重新取数（保留已探测的音质结论）
      widget.ref.read(musicRecommendProvider).resetForNewSession();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.cardDecoration(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '粘贴 Cookie 字符串\n格式：SESSDATA=xxx; bili_jct=yyy; DedeUserID=zzz',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _ctrl,
            maxLines: 4,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: AppTheme.textMain,
            ),
            decoration: const InputDecoration(
              hintText: 'SESSDATA=...',
              hintStyle: TextStyle(color: AppTheme.textSub, fontSize: 12),
              filled: true,
              fillColor: AppTheme.bgPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _loading ? null : _import,
                icon: _loading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.upload_rounded, size: 16),
                label: Text(_loading ? '导入中...' : '导入 Cookie'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (data?.text != null) {
                    _ctrl.text = data!.text!;
                  }
                },
                icon: const Icon(Icons.paste_rounded, size: 16),
                label: const Text('粘贴'),
              ),
            ],
          ),
          if (_result != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _success
                    ? const Color(0xFFE6F4EC)
                    : const Color(0xFFFDECEA),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _result!,
                style: TextStyle(
                  fontSize: 13,
                  color: _success ? AppTheme.success : AppTheme.danger,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── 通用 Tile 组件 ──────────────────────────────────────────────────────────

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.textSub, size: 22),
      title: Text(title),
      subtitle: subtitle != null
          ? Text(subtitle!,
              style: const TextStyle(fontSize: 12, color: AppTheme.textSub))
          : null,
      trailing: trailing ??
          (onTap != null
              ? const Icon(Icons.chevron_right_rounded,
                  color: Color(0xFFC0C4CC))
              : null),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String label;
  const _SectionTitle({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AppTheme.textMain,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
      ),
    );
  }
}

/// 设置分组卡片：白色圆角 + 阴影，子项之间用浅灰分割线
class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.cardDecoration(),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              const Divider(height: 1, indent: 14, endIndent: 14),
          ],
        ],
      ),
    );
  }
}
