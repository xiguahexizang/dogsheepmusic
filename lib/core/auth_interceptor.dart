/// Dio 拦截器：检测 401/403 响应自动触发重新登录
///
/// 流程：
/// 1. 捕获 401/403 响应
/// 2. 调用 [BiliAuth.autoLogin]（内部先检测 Cookie 有效性，再尝试账密登录）
/// 3. 登录成功 → 用新 Cookie 重试原请求
/// 4. 登录失败 → 透传原始错误
///
/// 注意：登录接口本身（passport.bilibili.com）不会被此拦截器处理，
/// 通过 [RequestOptions.extra] 中的 `'skipAuth'` 标志跳过。
library;

import 'dart:async';

import 'package:dio/dio.dart';

import 'package:dog_sheep_player/core/bili_api/auth.dart';

class AuthInterceptor extends Interceptor {
  final BiliAuth _auth;

  /// 并发保护：同一时刻只允许一个重新登录任务
  bool _renewing = false;
  Completer<bool>? _renewCompleter;

  AuthInterceptor(this._auth);

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final status = err.response?.statusCode;
    final skipAuth = err.requestOptions.extra['skipAuth'] == true;

    // 只处理 401/403，跳过登录接口本身
    if ((status != 401 && status != 403) || skipAuth) {
      return handler.next(err);
    }

    // 触发重新登录（防并发）
    final success = await _renewToken();

    if (success) {
      // 重新登录成功：用新 Cookie 重试原请求
      try {
        final retryResp = await _auth.dio.request(
          err.requestOptions.path,
          data: err.requestOptions.data,
          queryParameters: err.requestOptions.queryParameters,
          options: Options(
            method: err.requestOptions.method,
            headers: {
              ...err.requestOptions.headers,
              // 移除旧的 Cookie 头（CookieManager 会自动注入新 Cookie）
              'Cookie': null,
            },
            extra: {...err.requestOptions.extra, 'skipAuth': true},
          ),
        );
        // 用 resolve 代替 next，让上层拿到重试后的响应
        return handler.resolve(retryResp);
      } on DioException catch (retryErr) {
        // 重试仍失败，透传重试错误
        return handler.next(retryErr);
      }
    }

    // 重新登录失败，透传原始 401/403
    return handler.next(err);
  }

  /// 执行重新登录，返回是否成功
  Future<bool> _renewToken() async {
    if (_renewing) {
      // 等待正在进行的登录完成
      return _renewCompleter?.future ?? Future.value(false);
    }
    _renewing = true;
    _renewCompleter = Completer<bool>();

    try {
      final result = await _auth.autoLogin();
      final success = result == LoginResult.success;
      _renewCompleter!.complete(success);
      return success;
    } catch (_) {
      _renewCompleter!.complete(false);
      return false;
    } finally {
      _renewing = false;
      _renewCompleter = null;
    }
  }
}
