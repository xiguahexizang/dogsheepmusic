/// 折叠屏（Z Fold 系列）悬停态检测
///
/// 通过 Android 端 Jetpack WindowManager 提供的
/// [MethodChannel]（一次性查询）与 [EventChannel]（持续监听）
/// 获取当前铰链（folding feature）状态，转换为 [FoldingState] 供 UI 消费。
///
/// 在不支持折叠检测的设备 / 模拟器上，通道调用会抛异常或返回空，
/// 此时保持默认（非 flex）状态，UI 层需回退到按宽度判断。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 折叠状态快照。
///
/// 坐标（[hingeBounds]）来自原生，单位为**物理像素**，
/// 使用时需除以 `devicePixelRatio` 转换为逻辑 dp。
@immutable
class FoldingState {
  /// 原生是否提供了可用的折叠检测（false 表示普通直板机 / 检测不可用）。
  final bool available;

  /// 是否处于半开（悬停）态：`HALF_OPENED`。
  final bool isHalfOpened;

  /// 铰链是否为水平方向：`HORIZONTAL`（上下分屏所需）。
  final bool isHorizontal;

  /// 铰链区域（物理像素），无铰链时为 null。
  final Rect? hingeBounds;

  const FoldingState({
    this.available = false,
    this.isHalfOpened = false,
    this.isHorizontal = false,
    this.hingeBounds,
  });

  /// 是否为「悬停横铰」姿态 —— 上半内容 / 下半控制的分屏前提。
  bool get isFlexPosture => available && isHalfOpened && isHorizontal;

  FoldingState copyWith({
    bool? available,
    bool? isHalfOpened,
    bool? isHorizontal,
    Rect? hingeBounds,
  }) {
    return FoldingState(
      available: available ?? this.available,
      isHalfOpened: isHalfOpened ?? this.isHalfOpened,
      isHorizontal: isHorizontal ?? this.isHorizontal,
      hingeBounds: hingeBounds ?? this.hingeBounds,
    );
  }

  @override
  String toString() =>
      'FoldingState(available: $available, halfOpened: $isHalfOpened, '
      'horizontal: $isHorizontal, hinge: $hingeBounds)';
}

/// 解析原生返回的 folding feature（Map 或 null）。
///
/// 约定 Map 结构：
/// ```
/// { "state": "HALF_OPENED"|"FLAT", "orientation": "HORIZONTAL"|"VERTICAL",
///   "bounds": { "top": int, "bottom": int, "left": int, "right": int } }
/// ```
FoldingState parseFoldingFeature(Map<Object?, Object?>? map) {
  // null：设备不具备折叠硬件（直板机），保持不可用。
  if (map == null || map.isEmpty) {
    // EventChannel 在完全展开（FLAT 且无铰链）时也会发送空事件，
    // 仍标记 available=true，但非 flex 姿态。
    return const FoldingState(available: false);
  }

  final state = map['state']?.toString().toUpperCase();
  final orientation = map['orientation']?.toString().toUpperCase();

  Rect? bounds;
  final rawBounds = map['bounds'];
  if (rawBounds is Map) {
    final top = (rawBounds['top'] as num?)?.toDouble();
    final bottom = (rawBounds['bottom'] as num?)?.toDouble();
    final left = (rawBounds['left'] as num?)?.toDouble();
    final right = (rawBounds['right'] as num?)?.toDouble();
    if (top != null && bottom != null && left != null && right != null) {
      bounds = Rect.fromLTRB(left, top, right, bottom);
    }
  }

  return FoldingState(
    available: true,
    isHalfOpened: state == 'HALF_OPENED',
    isHorizontal: orientation == 'HORIZONTAL',
    hingeBounds: bounds,
  );
}

/// 通过 MethodChannel / EventChannel 监听折叠状态变化。
class FoldingNotifier extends StateNotifier<FoldingState> {
  FoldingNotifier() : super(const FoldingState()) {
    _initialize();
  }

  static const MethodChannel _method =
      MethodChannel('com.dogsheep.player/folding');
  static const EventChannel _event =
      EventChannel('com.dogsheep.player/folding/events');

  StreamSubscription<dynamic>? _sub;

  Future<void> _initialize() async {
    // Web 端（Chrome / flutter run -d chrome）不存在原生插件实现，
    // 任何 MethodChannel / EventChannel 调用都会抛 MissingPluginException，
    // 且 EventChannel 的错误是异步派发的，try/catch 与 onError 都不一定能兜住，
    // 因此 Web 端直接跳过全部通道调用，保持默认（非 flex）状态，由 UI 按宽度回退。
    if (kIsWeb) return;

    // 1) 一次性查询当前状态（进入 App 时可能已处于悬停）。
    try {
      final res = await _method.invokeMethod<dynamic>('getFoldingFeature');
      if (mounted) state = parseFoldingFeature(_asMap(res));
    } on MissingPluginException {
      // 平台未注册该通道（非折叠设备 / 未实现的原生端）：保持默认状态。
    } catch (_) {
      // 其他异常同样静默降级，按宽度回退。
    }

    // 2) 持续监听变化。
    try {
      _sub = _event.receiveBroadcastStream().listen(
        (event) {
          if (!mounted) return;
          state = parseFoldingFeature(_asMap(event));
        },
        onError: (Object error, StackTrace _) {
          // 监听失败（含 MissingPluginException）时静默降级。
          debugPrint('[folding] event stream error (ignored): $error');
          _sub?.cancel();
          _sub = null;
        },
      );
    } on MissingPluginException {
      // EventChannel 未实现：直板机 / 模拟器 / 未接入原生端。
      debugPrint('[folding] event channel unavailable (ignored)');
    } catch (_) {
      // EventChannel 不可用。
    }
  }

  Map<Object?, Object?>? _asMap(dynamic value) {
    if (value is Map) return value.cast<Object?, Object?>();
    return null;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// 全局折叠状态 Provider。
final foldingStateProvider =
    StateNotifierProvider<FoldingNotifier, FoldingState>((ref) {
  return FoldingNotifier();
});
