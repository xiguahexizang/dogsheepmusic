/// 全局异常处理与错误映射
///
/// 职责：
/// - 将 DioException 映射为用户友好的中文提示
/// - 播放错误自动重试 / 跳过策略
/// - 登录错误分类
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'package:dog_sheep_player/core/bili_api/auth.dart';

// ─── 错误码枚举 ─────────────────────────────────────────────────────────────

/// 内部错误分类（供 UI 层按类型选择展示方式）
enum AppErrorType {
  network,
  timeout,
  auth,
  playback,
  unknown,
}

/// 应用级错误描述，包含友好文案与原始错误
class AppError {
  final AppErrorType type;
  final String message;
  final Object? original;

  const AppError({
    required this.type,
    required this.message,
    this.original,
  });

  @override
  String toString() => 'AppError($type): $message';
}

// ─── 全局错误处理器 ──────────────────────────────────────────────────────────

class GlobalErrorHandler {
  GlobalErrorHandler._();

  // ─── 网络错误 → 友好文案 ────────────────────────────────────────────────

  /// 将 [DioException] 转换为用户可读的中文提示
  static String networkErrorMessage(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return '网络连接超时，请检查网络';
      case DioExceptionType.connectionError:
        return '无法连接到服务器，请检查网络';
      case DioExceptionType.badCertificate:
        return 'SSL 证书验证失败';
      case DioExceptionType.cancel:
        return '请求已取消';
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        if (code == 401 || code == 403) {
          return '登录已过期，正在重新登录...';
        }
        if (code == 404) {
          return '请求的资源不存在';
        }
        if (code != null && code >= 500) {
          return '服务器异常，请稍后重试';
        }
        return '网络异常: ${e.message ?? 'HTTP $code'}';
      case DioExceptionType.unknown:
        if (e.error is Exception) {
          return '网络异常: ${e.message ?? '未知错误'}';
        }
        return '网络异常，请检查网络连接';
    }
  }

  /// 将 [DioException] 映射为 [AppError]
  static AppError toAppError(DioException e) {
    final msg = networkErrorMessage(e);
    final type = _inferType(e);
    return AppError(type: type, message: msg, original: e);
  }

  static AppErrorType _inferType(DioException e) {
    if (e.type == DioExceptionType.badResponse) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) return AppErrorType.auth;
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return AppErrorType.timeout;
    }
    return AppErrorType.network;
  }

  // ─── 播放错误处理 ─────────────────────────────────────────────────────────

  /// 播放错误处理策略：
  /// - 403（音频流 Cookie 过期）→ 刷新 Cookie 后重试一次
  /// - 404（音频流不存在）→ 跳过该曲目，播放下一首
  /// - 其他 → 显示 SnackBar 错误提示
  ///
  /// [error] — 原始错误对象
  /// [context] — BuildContext，用于显示 SnackBar
  /// [onRetry] — 重试回调（刷新 Cookie 后重新播放当前曲目）
  /// [onSkip] — 跳过回调（播放下一首）
  static void handlePlaybackError(
    Object error, {
    required BuildContext context,
    VoidCallback? onRetry,
    VoidCallback? onSkip,
  }) {
    final errStr = error.toString();

    if (errStr.contains('403') || errStr.contains('Forbidden')) {
      // Cookie 过期：提示正在刷新，然后重试
      _showSnackBar(context, '音频流已过期，正在刷新...', duration: 1500);
      onRetry?.call();
      return;
    }

    if (errStr.contains('404') || errStr.contains('Not Found')) {
      // 音频流不存在：跳过该曲目
      _showSnackBar(context, '该曲目暂时无法播放，已跳过', duration: 2000);
      onSkip?.call();
      return;
    }

    // 其他播放错误
    _showSnackBar(context, '播放出错: ${error.toString()}', duration: 3000);
  }

  // ─── 登录错误映射 ─────────────────────────────────────────────────────────

  /// 将 [DioException] 映射为 [LoginResult]
  static LoginResult mapLoginError(DioException e) {
    if (e.type == DioExceptionType.badResponse) {
      final code = e.response?.statusCode;
      if (code == 412) return LoginResult.needCaptcha;
      if (code == 403 || code == 401) return LoginResult.cookieExpired;
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return LoginResult.networkError;
    }
    return LoginResult.networkError;
  }

  // ─── SnackBar 辅助 ────────────────────────────────────────────────────────

  static void _showSnackBar(
    BuildContext context,
    String message, {
    int duration = 2000,
  }) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(milliseconds: duration),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  /// 在任意位置安全显示 SnackBar（需有 ScaffoldMessenger）
  static void showInfo(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    _showSnackBar(context, message, duration: isError ? 3000 : 2000);
  }
}
