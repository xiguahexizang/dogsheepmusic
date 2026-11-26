import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'theme.dart';
import '../core/providers.dart';
import '../shared/error_boundary.dart';

/// 狗羊播放器 MaterialApp
class DogSheepApp extends ConsumerStatefulWidget {
  const DogSheepApp({super.key});

  @override
  ConsumerState<DogSheepApp> createState() => _DogSheepAppState();
}

class _DogSheepAppState extends ConsumerState<DogSheepApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 启动后立即拉一次账号信息（昵称/头像/VIP），
    // 首页问候与设置页依赖这些全局状态。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkLoginOnResume();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 应用进入后台时保持音频服务运行（audio_service 自行处理）
    // 回到前台时刷新登录状态（Cookie 可能在后台过期）
    if (state == AppLifecycleState.resumed) {
      _onAppResumed();
    }
  }

  Future<void> _onAppResumed() async {
    // 延迟 500ms 避免与系统动画冲突
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    // 异步检测登录状态，不阻塞 UI
    // ignore: unawaited_futures
    _checkLoginOnResume();
  }

  Future<void> _checkLoginOnResume() async {
    try {
      final auth = ref.read(biliAuthProvider);
      // nav 一次请求同时拿到登录态、VIP 与昵称/头像
      final profile = await auth.fetchProfile();
      final vip = profile.isLoggedIn && await auth.checkVipStatus();
      if (!mounted) return;
      ref.read(loginStatusProvider.notifier).state =
          profile.isLoggedIn ? LoginStatus.loggedIn : LoginStatus.loggedOut;
      ref.read(vipStatusProvider.notifier).state = vip;
      if (profile.isLoggedIn) {
        ref.read(userNicknameProvider.notifier).state = profile.nickname;
        ref.read(userAvatarProvider.notifier).state = profile.avatarUrl;
      }
    } catch (_) {
      // 检测失败静默忽略
    }
  }

  @override
  Widget build(BuildContext context) {
    // 状态栏 / 导航栏样式：浅色背景 + 深色图标
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: AppTheme.surface,
      systemNavigationBarIconBrightness: Brightness.dark,
    ));

    return ErrorBoundary(
      child: MaterialApp.router(
        title: 'DogSheep音乐',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: ref.watch(appRouterProvider),
      ),
    );
  }
}
