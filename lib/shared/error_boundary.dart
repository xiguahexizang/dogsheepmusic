import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:dog_sheep_player/app/theme.dart';

/// 全局错误边界 Widget
///
/// 通过替换 [FlutterError.onError] 和 [ErrorWidget.builder] 捕获
/// 子树中未处理的 Widget 构建异常，防止单个组件崩溃导致整个应用白屏。
///
/// 用法（在 [MaterialApp] 外层）：
/// ```dart
/// ErrorBoundary(child: MaterialApp(...))
/// ```
class ErrorBoundary extends StatefulWidget {
  final Widget child;

  /// 自定义错误 UI（为 null 时使用内置默认错误页）
  final Widget Function(
      BuildContext context, Object error, StackTrace? stackTrace)? errorBuilder;

  const ErrorBoundary({
    super.key,
    required this.child,
    this.errorBuilder,
  });

  @override
  State<ErrorBoundary> createState() => ErrorBoundaryState();

  /// 从 BuildContext 获取最近的 [ErrorBoundaryState] 并重置错误状态
  static void reset(BuildContext context) {
    final state = context.findAncestorStateOfType<ErrorBoundaryState>();
    state?._reset();
  }
}

class ErrorBoundaryState extends State<ErrorBoundary> {
  Object? _error;
  StackTrace? _stackTrace;

  // 保存原始 handler，以便 dispose 时恢复
  void Function(FlutterErrorDetails)? _savedOnError;
  Widget Function(FlutterErrorDetails)? _savedErrorWidgetBuilder;

  @override
  void initState() {
    super.initState();
    _install();
  }

  @override
  void dispose() {
    _uninstall();
    super.dispose();
  }

  void _install() {
    _savedOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      // 开发模式下仍打印到控制台
      if (kDebugMode) {
        _savedOnError?.call(details);
      }
      // 捕获异常，触发 UI 重建显示错误页
      if (mounted) {
        setState(() {
          _error = details.exception;
          _stackTrace = details.stack;
        });
      }
    };

    _savedErrorWidgetBuilder = ErrorWidget.builder;
    ErrorWidget.builder = (FlutterErrorDetails details) {
      // 返回一个透明占位，实际错误展示由本 State 处理
      return const SizedBox.shrink();
    };
  }

  void _uninstall() {
    if (_savedOnError != null) {
      FlutterError.onError = _savedOnError;
    }
    if (_savedErrorWidgetBuilder != null) {
      ErrorWidget.builder = _savedErrorWidgetBuilder!;
    }
  }

  void _reset() {
    setState(() {
      _error = null;
      _stackTrace = null;
    });
  }

  /// 手动上报错误（供外部调用）
  void reportError(Object error, [StackTrace? stack]) {
    if (!mounted) return;
    setState(() {
      _error = error;
      _stackTrace = stack;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      // 优先使用调用方传入的自定义 errorBuilder
      if (widget.errorBuilder != null) {
        return widget.errorBuilder!(context, _error!, _stackTrace);
      }
      // 默认内置错误页
      return _DefaultErrorPage(
        error: _error!,
        stackTrace: _stackTrace,
        onRetry: _reset,
      );
    }

    return widget.child;
  }
}

// ─── 内置默认错误页 ──────────────────────────────────────────────────────────

class _DefaultErrorPage extends StatelessWidget {
  final Object error;
  final StackTrace? stackTrace;
  final VoidCallback onRetry;

  const _DefaultErrorPage({
    required this.error,
    required this.stackTrace,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final errStr = error.toString();
    final isNetwork = errStr.contains('SocketException') ||
        errStr.contains('DioException') ||
        errStr.contains('network');

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: AppTheme.bgPrimary,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppTheme.accent,
          brightness: Brightness.light,
        ),
      ),
      home: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
                child: Column(
                  children: [
                    // 图标
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: isNetwork
                            ? const Color(0xFFEAF2FB)
                            : const Color(0xFFFDECEA),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isNetwork
                              ? const Color(0xFFC3DAF2)
                              : const Color(0xFFF3C4BE),
                        ),
                      ),
                      child: Icon(
                        isNetwork
                            ? Icons.cloud_off_rounded
                            : Icons.bug_report_rounded,
                        size: 44,
                        color: isNetwork ? AppTheme.info : AppTheme.danger,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // 标题
                    Text(
                      isNetwork ? '网络连接问题' : '应用出现了异常',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textMain,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 错误信息（最多 3 行）
                    Text(
                      errStr,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSub,
                        height: 1.6,
                      ),
                    ),

                    // 开发模式下显示部分堆栈
                    if (kDebugMode && stackTrace != null) ...[
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(maxHeight: 140),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.bgCard,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.divider),
                        ),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            stackTrace!
                                .toString()
                                .split('\n')
                                .where((l) => l.trim().isNotEmpty)
                                .take(6)
                                .join('\n'),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              color: AppTheme.textSub,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 36),

                    // 操作按钮
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 重试按钮
                        FilledButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('重新加载'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 14,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    Text(
                      '若问题持续，请尝试重启应用',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textSub,
                          ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
