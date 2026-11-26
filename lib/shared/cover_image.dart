import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:dog_sheep_player/app/theme.dart';
import 'package:dog_sheep_player/core/web_proxy.dart';

/// 统一封面图组件：网络加载 + 占位 + 错误回退
///
/// 自动为首个无 scheme 的 URL 补 `https:`（Bilibili 图片常以 `//` 开头）；
/// Web 调试构建下再改写为 dev_proxy 地址（见 [WebProxy.imageUrl]），
/// 否则 `<img>` 直连 hdslb CDN 会被 CORS 拦，所有封面只能显示占位图标。
class CoverImage extends StatelessWidget {
  final String? url;
  final double size;
  final double radius;
  final BoxFit fit;
  final IconData fallbackIcon;

  const CoverImage({
    super.key,
    required this.url,
    this.size = 48,
    this.radius = 8,
    this.fit = BoxFit.cover,
    this.fallbackIcon = Icons.music_note,
  });

  static String? normalize(String? url) {
    if (url == null || url.isEmpty) return null;
    final src = url.startsWith('//') ? 'https:$url' : url;
    return kIsWeb ? WebProxy.imageUrl(src) : src;
  }

  @override
  Widget build(BuildContext context) {
    final src = normalize(url);
    Widget placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppTheme.bgPrimary,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(fallbackIcon, size: size * 0.42, color: AppTheme.textSub),
    );

    if (src == null) return placeholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: CachedNetworkImage(
          imageUrl: src,
          fit: fit,
          fadeInDuration: const Duration(milliseconds: 200),
          placeholder: (_, __) => Container(
            color: AppTheme.bgPrimary,
            child: const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppTheme.accent),
              ),
            ),
          ),
          errorWidget: (_, __, ___) => placeholder,
        ),
      ),
    );
  }
}
