import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/dashboard_theme.dart';
import '../providers/dashboard_theme_provider.dart';
import 'glass_card.dart';

/// แสดง Dialog แบบ Glassmorphism
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetRef ref,
  required WidgetBuilder builder,
}) {
  final theme = ref.read(dashboardThemeProvider).theme;
  final opacity = theme?.glassOpacityDialog ?? 0.20;
  final blur = theme?.glassBlurLevel.toDouble() ?? 8.0;
  final isDark = theme?.isDarkMode ?? false;

  return showDialog<T>(
    context: context,
    barrierColor: Colors.black.withOpacity(isDark ? 0.6 : 0.4),
    builder: (ctx) => BackdropFilter(
      filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: GlassCard(
          section: GlassSection.dialog,
          borderRadius: 20,
          padding: const EdgeInsets.all(24),
          child: builder(ctx),
        ),
      ),
    ),
  );
}
