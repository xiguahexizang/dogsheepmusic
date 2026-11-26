import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'theme.dart';
import '../features/favorites/favorites_page.dart';
import '../features/home/home_page.dart';
import '../features/login/qr_login_page.dart';
import '../features/music/music_page.dart';
import '../features/search/search_page.dart';
import '../features/player/player_page.dart';
import '../features/player/player_provider.dart';
import '../features/queue/queue_page.dart';
import '../features/settings/password_setup_page.dart';
import '../features/settings/settings_page.dart';
import '../shared/folding_provider.dart';
import '../shared/flex_bottom_controls.dart';
import '../shared/mini_player.dart';
import '../shared/player_panel.dart';
import '../shared/responsive.dart';

/// 路由名称常量
class RouteNames {
  RouteNames._();
  static const home = '/';
  static const music = '/music';
  static const search = '/search';
  static const player = '/player';
  static const queue = '/queue';
  static const settings = '/settings';
  static const favorites = '/favorites';
  static const password = '/password-setup';
  static const login = '/login';
}

/// GoRouter Provider，需在 main() 中 overrideWithValue
/// 使用 [createAppRouter] 创建实例
final appRouterProvider = Provider<GoRouter>((ref) {
  throw UnimplementedError('appRouterProvider must be overridden in main()');
});

/// 创建 GoRouter 实例
/// [initialLocation] 为 null 时默认跳转首页，否则跳转密码设置页
GoRouter createAppRouter({String? initialLocation}) {
  return GoRouter(
    initialLocation: initialLocation ?? RouteNames.home,
    routes: [
      // 扫码登录页（独立全屏，无 Shell 导航）
      GoRoute(
        path: RouteNames.login,
        name: 'login',
        builder: (_, __) => const QrLoginPage(),
      ),

      // 密码设置页（旧版入口，保留兼容；不再作为首屏）
      GoRoute(
        path: RouteNames.password,
        name: 'password-setup',
        builder: (_, __) => const PasswordSetupPage(),
      ),

      // ── 主 Shell（含底部导航 + MiniPlayer）─────────────────────────────
      ShellRoute(
        builder: (context, state, child) {
          return _MainShell(currentPath: state.uri.path, child: child);
        },
        routes: [
          GoRoute(
            path: RouteNames.home,
            name: 'home',
            builder: (_, __) => const HomePage(),
          ),
          GoRoute(
            path: RouteNames.music,
            name: 'music',
            builder: (_, __) => const MusicPage(),
          ),
          GoRoute(
            path: RouteNames.search,
            name: 'search',
            builder: (_, __) => const SearchPage(),
          ),
          GoRoute(
            path: RouteNames.favorites,
            name: 'favorites',
            builder: (_, __) => const FavoritesPage(),
          ),
          GoRoute(
            path: RouteNames.settings,
            name: 'settings',
            builder: (_, __) => const SettingsPage(),
          ),
        ],
      ),

      // ── 全屏页面（无底部导航 / MiniPlayer）─────────────────────────────
      GoRoute(
        path: RouteNames.player,
        name: 'player',
        builder: (_, __) => const PlayerPage(),
      ),
      GoRoute(
        path: RouteNames.queue,
        name: 'queue',
        // 从播放器页进入（?from=player）时不重复显示 MiniPlayer
        builder: (_, state) => QueuePage(
          showMiniPlayer: state.uri.queryParameters['from'] != 'player',
        ),
      ),

      // 推荐歌单入口已移除（/playlist）；playlist_detail_page.dart 保留，
      // 待未来重新接入时在此注册路由即可。
    ],
  );
}

/// 主 Shell —— Z Fold 三态布局
///
/// - **phone**（外屏 / < 600dp）：内容 + MiniPlayer + 底部 NavigationBar（默认，保持既有布局）
/// - **foldable**（内屏展开 / >= 600dp）：
///   左侧 NavigationRail + 中间内容 + 右侧常驻 [PlayerPanel]（有播放内容时）；
///   MiniPlayer 隐藏（右侧已有完整播放控制）
/// - **flex**（悬停横铰）：上半屏内容 + 铰链间隔 + 下半屏 [FlexBottomControls] 与导航
class _MainShell extends ConsumerWidget {
  final String currentPath;
  final Widget child;

  const _MainShell({required this.currentPath, required this.child});

  static const _tabs = [
    (
      path: RouteNames.home,
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      label: '首页'
    ),
    (
      path: RouteNames.music,
      icon: Icons.music_note_outlined,
      activeIcon: Icons.music_note,
      label: '音乐'
    ),
    (
      path: RouteNames.search,
      icon: Icons.search,
      activeIcon: Icons.search,
      label: '搜索'
    ),
    (
      path: RouteNames.favorites,
      icon: Icons.favorite_border_rounded,
      activeIcon: Icons.favorite_rounded,
      label: '收藏'
    ),
    (
      path: RouteNames.settings,
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings,
      label: '设置'
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folding = ref.watch(foldingStateProvider);
    final screenState = Responsive.getScreenState(context, folding);

    switch (screenState) {
      case ScreenState.phone:
        return _buildPhone(context);
      case ScreenState.foldable:
        return _buildFoldable(context, ref);
      case ScreenState.flex:
        return _buildFlex(context);
    }
  }

  // ── phone：保持既有默认布局 ────────────────────────────────────────────
  Widget _buildPhone(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // MiniPlayer：无播放内容时自身收缩为 0 高度
          const MiniPlayer(),
          _bottomNav(context),
        ],
      ),
    );
  }

  // ── foldable：左导航 / 中内容 / 右常驻播放器 ──────────────────────────
  Widget _buildFoldable(BuildContext context, WidgetRef ref) {
    final hasPlayback = ref.watch(currentItemProvider).valueOrNull != null;
    final totalWidth = Responsive.getScreenWidth(context);
    // 面板宽度按总宽分档，保证中间内容区拿到最大空间
    final panelWidth =
        hasPlayback ? Responsive.playerPanelWidthFor(totalWidth) : 0.0;
    final contentWidth = totalWidth - panelWidth;

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            _navRail(context, contentWidth),
            const SizedBox(width: 1),
            // 中间主内容区
            Expanded(child: child),
            // 右侧常驻播放器面板（仅在有播放内容时占据宽度）
            if (hasPlayback)
              SizedBox(
                width: panelWidth,
                child: const PlayerPanel(),
              ),
          ],
        ),
      ),
    );
  }

  // ── flex：上半内容 / 下半播放控制 + 导航 ──────────────────────────────
  Widget _buildFlex(BuildContext context) {
    return Scaffold(
      body: FlexLayout(
        topContent: child,
        bottomContent: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Divider(height: 1),
            const FlexBottomControls(),
            _bottomNav(context),
          ],
        ),
      ),
    );
  }

  int get _selectedIndex {
    final i = _tabs.indexWhere((t) => t.path == currentPath);
    return i < 0 ? 0 : i;
  }

  /// 底部导航栏（phone / flex 共用）
  Widget _bottomNav(BuildContext context) {
    return NavigationBar(
      selectedIndex: _selectedIndex,
      onDestinationSelected: (i) => context.go(_tabs[i].path),
      destinations: _tabs
          .map((t) => NavigationDestination(
                icon: Icon(t.icon),
                selectedIcon: Icon(t.activeIcon),
                label: t.label,
              ))
          .toList(),
    );
  }

  /// 侧边导航栏（foldable）—— 紧凑模式
  ///
  /// 宽度从 80dp 收到 56-60dp：展开态宽度不足 720dp 时退化为
  /// 「纯图标 + 选中指示器」（Material 3 导航栏最小宽度），仅靠 Tooltip 提示；
  /// 更宽的内屏保留当前项文字标签，其余项仍只显示图标。
  Widget _navRail(BuildContext context, double contentWidth) {
    final showLabel = Responsive.navRailShowLabels(contentWidth);
    return NavigationRail(
      // 注意：不能传 elevation: 0，NavigationRail 断言要求 elevation == null 或 > 0，
      // 传 0 会在 debug 模式下直接抛异常（Web / 折叠屏宽屏布局首当其冲）。
      minWidth: showLabel
          ? Responsive.navRailLabeledWidth
          : Responsive.navRailIconOnlyWidth,
      backgroundColor: AppTheme.surface,
      indicatorColor: AppTheme.accentSoft,
      selectedIndex: _selectedIndex,
      onDestinationSelected: (i) => context.go(_tabs[i].path),
      labelType: showLabel
          ? NavigationRailLabelType.selected
          : NavigationRailLabelType.none,
      selectedIconTheme: const IconThemeData(color: AppTheme.accent, size: 24),
      unselectedIconTheme:
          const IconThemeData(color: AppTheme.textSub, size: 22),
      selectedLabelTextStyle: const TextStyle(
        color: AppTheme.accent,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelTextStyle: const TextStyle(
        color: AppTheme.textSub,
        fontSize: 11,
      ),
      destinations: _tabs
          .map((t) => NavigationRailDestination(
                icon: Tooltip(
                  message: t.label,
                  child: Icon(t.icon),
                ),
                selectedIcon: Icon(t.activeIcon),
                label: Text(t.label),
              ))
          .toList(),
    );
  }
}
