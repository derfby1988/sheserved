import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sheserved/shared/widgets/glass/glass_dialog.dart';

import '../providers/dashboard_theme_provider.dart';

Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetRef ref,
  required WidgetBuilder builder,
}) {
  final theme = ref.read(dashboardThemeProvider).theme;
  final opacity = (theme?.glassOpacityDialog ?? 0.25)
      .clamp(0.15, 0.50)
      .toDouble();
  final blur = theme?.glassBlurLevel.toDouble() ?? 8.0;
  final isDark = theme?.isDarkMode ?? false;

  return GlassDialog.show<T>(
    context: context,
    builder: builder,
    barrierColor: Colors.black.withValues(alpha: isDark ? 0.6 : 0.4),
    backdropBlur: blur,
    panelBorderRadius: 20,
    panelBlurSigma: theme?.glassBlurLevel.toDouble() ?? 12.0,
    panelFillOpacity: opacity,
    panelSurfaceColor: isDark ? Colors.black : Colors.white,
    panelRimWidth: 1.5,
    panelShadowOpacity: isDark ? 0.5 : 0.12,
  );
}
