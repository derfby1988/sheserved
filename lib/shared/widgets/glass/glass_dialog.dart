import 'dart:ui';

import 'package:flutter/material.dart';

import 'glass_primitives.dart';

typedef GlassDialogPanelBuilder =
    Widget Function(BuildContext context, Widget child);

class GlassDialog {
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
    Color barrierColor = const Color(0x4D000000),
    double backdropBlur = 6,
    double panelBorderRadius = 24,
    double panelBlurSigma = 18,
    double panelFillOpacity = 0.10,
    Color panelSurfaceColor = Colors.white,
    Color? panelAccentColor,
    double panelAccentStrength = 0.12,
    double panelGlowOpacity = 0.14,
    double panelRimWidth = 2.4,
    double panelShadowOpacity = 0.30,
    EdgeInsetsGeometry contentPadding = const EdgeInsets.all(24),
    EdgeInsets? insetPadding,
    GlassDialogPanelBuilder? panelBuilder,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: barrierColor,
      builder: (_) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: backdropBlur, sigmaY: backdropBlur),
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: insetPadding,
          child: Builder(
            builder: (panelContext) {
              final content = Padding(
                padding: contentPadding,
                child: builder(panelContext),
              );
              final customPanel = panelBuilder;
              if (customPanel != null) {
                return customPanel(panelContext, content);
              }
              return LitGlassSurface(
                borderRadius: panelBorderRadius,
                blurSigma: panelBlurSigma,
                fillOpacity: panelFillOpacity,
                surfaceColor: panelSurfaceColor,
                accentColor: panelAccentColor,
                accentStrength: panelAccentStrength,
                glowOpacity: panelGlowOpacity,
                rimWidth: panelRimWidth,
                shadowOpacity: panelShadowOpacity,
                child: content,
              );
            },
          ),
        ),
      ),
    );
  }
}
