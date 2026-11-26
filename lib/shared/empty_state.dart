import 'package:flutter/material.dart';

import 'package:dog_sheep_player/app/theme.dart';

/// 空状态占位：图标 + 主标题 + 副标题 + 可选操作按钮
///
/// 内容会依据父级给出的最大高度自适应收缩（图标尺寸、间距、
/// 是否在极矮空间内隐藏副标题），避免在 `SizedBox(height: 100)`
/// 之类的紧约束里出现 RenderFlex overflow。
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    this.icon = Icons.music_off_outlined,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxH = constraints.maxHeight;
        // 高度未知（无界）时按完整尺寸渲染
        final bounded = maxH.isFinite;
        // 0 = 完整；1 = 紧凑（小图标小间距）；2 = 极简（仅标题）
        final level = !bounded ? 0 : (maxH >= 240 ? 0 : (maxH >= 96 ? 1 : 2));

        final iconSize = level == 0 ? 88.0 : (level == 1 ? 44.0 : 0.0);
        final glyphSize = level == 0 ? 40.0 : 22.0;
        final gap1 = level == 0 ? 20.0 : (level == 1 ? 10.0 : 6.0);
        final vertical = level == 0 ? 24.0 : (level == 1 ? 12.0 : 8.0);
        final showMessage =
            level == 0 || (level == 1 && (!bounded || maxH >= 165));
        final showAction =
            level == 0 && actionLabel != null && onAction != null;

        return Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: vertical),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (iconSize > 0)
                  Container(
                    width: iconSize,
                    height: iconSize,
                    decoration: BoxDecoration(
                      color: AppTheme.bgPrimary,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.divider),
                    ),
                    child: Icon(icon, size: glyphSize, color: AppTheme.textSub),
                  ),
                SizedBox(height: gap1),
                Flexible(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (message != null && showMessage) ...[
                  const SizedBox(height: 8),
                  Text(
                    message!,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (showAction) ...[
                  const SizedBox(height: 20),
                  ElevatedButton(
                      onPressed: onAction, child: Text(actionLabel!)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
