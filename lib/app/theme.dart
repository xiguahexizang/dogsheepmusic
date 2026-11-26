import 'package:flutter/material.dart';

/// 狗羊播放器 - Material 3 浅色（白色卡片式）主题
/// 色调：浅灰底 + 纯白卡片 + 深色文字 + 暖金强调
class AppTheme {
  AppTheme._();

  // ── 色板 ──────────────────────────────────────────────
  static const Color bgPrimary = Color(0xFFF5F6FA); // 浅灰页面背景
  static const Color bgCard = Color(0xFFFFFFFF); // 纯白卡片
  static const Color textMain = Color(0xFF1A1A2E); // 深色主文字
  static const Color textSub = Color(0xFF666666); // 次要文字
  static const Color accent = Color(0xFFF5A623); // 暖金强调
  static const Color accentDim = Color(0xFFD4891A); // 深一档金
  static const Color surface = Color(0xFFFFFFFF); // 白色次级背景
  static const Color divider = Color(0xFFEEEEEE); // 分割线

  /// 半透明金（选中底色一类）
  static const Color accentSoft = Color(0x1AF5A623);

  /// 卡片阴影色（10% 黑）
  static const Color cardShadow = Color(0x1A000000);

  /// 危险 / 破坏性操作色（浅色主题下可读的红）
  static const Color danger = Color(0xFFD93025);

  /// 成功 / 在线状态色
  static const Color success = Color(0xFF1A9E5C);

  /// 信息 / 网络状态色
  static const Color info = Color(0xFF2E7CD6);

  // ── 圆角 ──────────────────────────────────────────────
  static const double radius = 16.0;
  static const BorderRadius borderRadius =
      BorderRadius.all(Radius.circular(radius));

  /// 卡片通用阴影装饰（白色底 + 16px 圆角 + elevation 2 观感）
  static BoxDecoration cardDecoration({Color? color}) => BoxDecoration(
        color: color ?? bgCard,
        borderRadius: borderRadius,
        boxShadow: const [
          BoxShadow(
            color: cardShadow,
            blurRadius: 12,
            offset: Offset(0, 4),
            spreadRadius: 0,
          ),
        ],
      );

  // ── 文本主题 ──────────────────────────────────────────
  static final TextTheme _textTheme = const TextTheme().copyWith(
    displayLarge: const TextStyle(
      fontSize: 36,
      fontWeight: FontWeight.bold,
      color: textMain,
      letterSpacing: -0.5,
    ),
    displayMedium: const TextStyle(
      fontSize: 30,
      fontWeight: FontWeight.bold,
      color: textMain,
    ),
    displaySmall: const TextStyle(
      fontSize: 26,
      fontWeight: FontWeight.w700,
      color: textMain,
    ),
    headlineLarge: const TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w600,
      color: textMain,
    ),
    headlineMedium: const TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: textMain,
    ),
    headlineSmall: const TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      color: textMain,
    ),
    titleLarge: const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: textMain,
    ),
    titleMedium: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: textMain,
    ),
    titleSmall: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: textSub,
    ),
    bodyLarge: const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.normal,
      color: textMain,
      height: 1.5,
    ),
    bodyMedium: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.normal,
      color: textMain,
      height: 1.5,
    ),
    bodySmall: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.normal,
      color: textSub,
      height: 1.4,
    ),
    labelLarge: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: accent,
      letterSpacing: 0.3,
    ),
    labelMedium: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: textSub,
    ),
    labelSmall: const TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w500,
      color: textSub,
    ),
  );

  // ── 颜色方案 ──────────────────────────────────────────
  static const ColorScheme _colorScheme = ColorScheme.light(
    primary: accent,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFFFF3D6),
    onPrimaryContainer: Color(0xFF7A5100),
    secondary: bgCard,
    onSecondary: textMain,
    secondaryContainer: Color(0xFFF0F1F5),
    onSecondaryContainer: textMain,
    tertiary: accentDim,
    onTertiary: Colors.white,
    surface: bgCard,
    onSurface: textMain,
    surfaceContainerHighest: Color(0xFFF0F1F5),
    onSurfaceVariant: textSub,
    error: Color(0xFFD93025),
    onError: Colors.white,
    outline: divider,
    outlineVariant: Color(0xFFE5E6EB),
    inverseSurface: Color(0xFF333344),
    onInverseSurface: Color(0xFFF5F5F7),
  );

  // ── 主主题 ────────────────────────────────────────────
  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: _colorScheme,
      scaffoldBackgroundColor: bgPrimary,
      canvasColor: bgCard,
      textTheme: _textTheme,

      // AppBar：透明背景 + 深色文字 + 无阴影
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: textMain,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: textMain,
          letterSpacing: 0.3,
        ),
        iconTheme: IconThemeData(color: textMain),
      ),

      // Card：白色，16px 圆角，elevation 2
      cardTheme: const CardThemeData(
        elevation: 2,
        color: bgCard,
        shadowColor: cardShadow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
        margin: EdgeInsets.zero,
      ),

      // BottomNavigationBar
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: bgCard,
        selectedItemColor: accent,
        unselectedItemColor: textSub,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      // NavigationBar (M3)：白色背景，选中项金色
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: bgCard,
        indicatorColor: accentSoft,
        elevation: 0,
        shadowColor: cardShadow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected ? accent : textSub,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: accent);
          }
          return const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w400, color: textSub);
        }),
      ),

      // NavigationRail
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: bgCard,
        selectedIconTheme: IconThemeData(color: accent),
        unselectedIconTheme: IconThemeData(color: textSub),
        selectedLabelTextStyle:
            TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: accent),
        unselectedLabelTextStyle: TextStyle(fontSize: 11, color: textSub),
      ),

      // FloatingActionButton
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 4,
      ),

      // ElevatedButton
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: const RoundedRectangleBorder(borderRadius: borderRadius),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),

      // FilledButton
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          shape: const RoundedRectangleBorder(borderRadius: borderRadius),
        ),
      ),

      // TextButton
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),

      // IconButton
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: textMain),
      ),

      // TextField：白色圆角卡片输入框
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: bgCard,
        contentPadding:
            EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide(color: divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: borderRadius,
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        hintStyle: TextStyle(color: textSub, fontSize: 14),
        labelStyle: TextStyle(color: textSub, fontSize: 13),
      ),

      // Slider：细线 + 圆点
      sliderTheme: const SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: Color(0xFFE3E5EB),
        thumbColor: accent,
        overlayColor: Color(0x33F5A623),
        trackHeight: 3,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
      ),

      // Divider
      dividerTheme: const DividerThemeData(
        color: divider,
        thickness: 1,
        space: 1,
      ),

      // SnackBar
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF333344),
        contentTextStyle: const TextStyle(color: Colors.white),
        actionTextColor: accent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      // ListTile：文字深色，图标次要色
      listTileTheme: const ListTileThemeData(
        iconColor: textSub,
        textColor: textMain,
        titleTextStyle: TextStyle(
            fontSize: 15, fontWeight: FontWeight.w500, color: textMain),
        subtitleTextStyle: TextStyle(fontSize: 13, color: textSub),
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
      ),

      // Chip：圆角胶囊
      chipTheme: const ChipThemeData(
        backgroundColor: bgCard,
        selectedColor: accentSoft,
        side: BorderSide(color: divider),
        labelStyle: TextStyle(color: textMain, fontSize: 13),
        shape: StadiumBorder(),
      ),

      // TabBar：白色背景
      tabBarTheme: const TabBarThemeData(
        labelColor: accent,
        unselectedLabelColor: textSub,
        indicatorColor: accent,
        dividerColor: divider,
        labelStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        unselectedLabelStyle:
            TextStyle(fontSize: 15, fontWeight: FontWeight.w400),
      ),

      // ProgressIndicator
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: Color(0xFFE3E5EB),
        circularTrackColor: Color(0xFFE3E5EB),
      ),

      // BottomSheet
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: bgCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),

      // Dialog
      dialogTheme: const DialogThemeData(
        backgroundColor: bgCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
      ),

      // Switch
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) => Colors.white),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent;
          return const Color(0xFFD8DAE0);
        }),
      ),
    );
  }

  /// 兼容旧调用点：项目已切换为浅色主题，[dark] 与 [light] 等价。
  static ThemeData get dark => light;
}
