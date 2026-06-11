import 'dart:ui' show Color;
import 'package:flutter/material.dart' show Colors;

import 'theme_preset.dart';

/// Glass section enum สำหรับแยก opacity ตามส่วน
enum GlassSection { sidebar, card, dialog }

/// Model สำหรับ user dashboard theme (รวม preset + custom + glassmorphism)
class DashboardTheme {
  final bool isDarkMode;
  final String themePreset;
  final String? customPrimary;
  final String? customAccent;
  final String? customSurface;
  final String? customTextPrimary;
  final String? customTextSecondary;
  final String? customError;
  final double glassOpacitySidebar;
  final double glassOpacityCards;
  final double glassOpacityDialog;
  final int glassBlurLevel;
  final ThemePreset? resolvedPreset;

  const DashboardTheme({
    this.isDarkMode = false,
    this.themePreset = 'sheserved_default',
    this.customPrimary,
    this.customAccent,
    this.customSurface,
    this.customTextPrimary,
    this.customTextSecondary,
    this.customError,
    this.glassOpacitySidebar = 0.12,
    this.glassOpacityCards = 0.12,
    this.glassOpacityDialog = 0.12,
    this.glassBlurLevel = 12,
    this.resolvedPreset,
  });

  factory DashboardTheme.fromJson(Map<String, dynamic> json) {
    final resolved = json['resolved_preset'] as Map<String, dynamic>?;
    return DashboardTheme(
      isDarkMode: json['is_dark_mode'] as bool? ?? false,
      themePreset: json['theme_preset'] as String? ?? 'sheserved_default',
      customPrimary: json['custom_primary'] as String?,
      customAccent: json['custom_accent'] as String?,
      customSurface: json['custom_surface'] as String?,
      customTextPrimary: json['custom_text_primary'] as String?,
      customTextSecondary: json['custom_text_secondary'] as String?,
      customError: json['custom_error'] as String?,
      glassOpacitySidebar: _toDouble(json['glass_opacity_sidebar']),
      glassOpacityCards: _toDouble(json['glass_opacity_cards']),
      glassOpacityDialog: _toDouble(json['glass_opacity_dialog']),
      glassBlurLevel: json['glass_blur_level'] as int? ?? 12,
      resolvedPreset: resolved != null ? ThemePreset.fromJson(resolved) : null,
    );
  }

  static double _toDouble(dynamic value) {
    if (value == null) return 0.12;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.12;
    return 0.12;
  }

  /// สี primary (sidebar bg / app bar)
  Color get primaryColor => _hexToColor(resolvedPreset?.primaryColor ?? customPrimary ?? '#00695C');

  /// สี accent (toggle, badge, highlight)
  Color get accentColor => _hexToColor(resolvedPreset?.accentColor ?? customAccent ?? '#FFC107');

  /// สี surface (active item bg / card bg)
  Color get surfaceColor => _hexToColor(resolvedPreset?.surfaceColor ?? customSurface ?? '#FFFFFF');

  /// สี text หลัก
  Color get textPrimaryColor => _hexToColor(resolvedPreset?.textPrimary ?? customTextPrimary ?? '#FFFFFF');

  /// สี text รอง
  Color get textSecondaryColor {
    final raw = resolvedPreset?.textSecondary ?? customTextSecondary ?? 'rgba(255,255,255,0.7)';
    return _parseRgba(raw);
  }

  /// สี error
  Color get errorColor => _hexToColor(resolvedPreset?.errorColor ?? customError ?? '#F85149');

  /// สี card bg
  Color get cardBgColor => _hexToColor(resolvedPreset?.cardBg ?? '#FFFFFF');

  /// สี card text
  Color get cardTextColor => _hexToColor(resolvedPreset?.cardText ?? '#1F2937');

  /// ดึง opacity ตาม section
  double getOpacityFor(GlassSection section) {
    switch (section) {
      case GlassSection.sidebar: return glassOpacitySidebar;
      case GlassSection.card: return glassOpacityCards;
      case GlassSection.dialog: return glassOpacityDialog;
    }
  }

  /// สร้าง copy ใหม่
  DashboardTheme copyWith({
    bool? isDarkMode,
    String? themePreset,
    String? customPrimary,
    String? customAccent,
    String? customSurface,
    String? customTextPrimary,
    String? customTextSecondary,
    String? customError,
    double? glassOpacitySidebar,
    double? glassOpacityCards,
    double? glassOpacityDialog,
    int? glassBlurLevel,
    ThemePreset? resolvedPreset,
  }) {
    return DashboardTheme(
      isDarkMode: isDarkMode ?? this.isDarkMode,
      themePreset: themePreset ?? this.themePreset,
      customPrimary: customPrimary ?? this.customPrimary,
      customAccent: customAccent ?? this.customAccent,
      customSurface: customSurface ?? this.customSurface,
      customTextPrimary: customTextPrimary ?? this.customTextPrimary,
      customTextSecondary: customTextSecondary ?? this.customTextSecondary,
      customError: customError ?? this.customError,
      glassOpacitySidebar: glassOpacitySidebar ?? this.glassOpacitySidebar,
      glassOpacityCards: glassOpacityCards ?? this.glassOpacityCards,
      glassOpacityDialog: glassOpacityDialog ?? this.glassOpacityDialog,
      glassBlurLevel: glassBlurLevel ?? this.glassBlurLevel,
      resolvedPreset: resolvedPreset ?? this.resolvedPreset,
    );
  }

  static Color _hexToColor(String hex) {
    hex = hex.replaceFirst('#', '');
    if (hex.length == 6) {
      return Color(int.parse('FF$hex', radix: 16));
    }
    if (hex.length == 8) {
      return Color(int.parse(hex, radix: 16));
    }
    return Colors.grey;
  }

  static Color _parseRgba(String rgba) {
    // รองรับรูปแบบ rgba(r,g,b,a) หรือ hex
    if (rgba.startsWith('rgba(')) {
      final parts = rgba.replaceAll('rgba(', '').replaceAll(')', '').split(',');
      if (parts.length == 4) {
        final r = int.tryParse(parts[0].trim()) ?? 255;
        final g = int.tryParse(parts[1].trim()) ?? 255;
        final b = int.tryParse(parts[2].trim()) ?? 255;
        final a = double.tryParse(parts[3].trim()) ?? 1.0;
        return Color.fromRGBO(r, g, b, a);
      }
    }
    if (rgba.startsWith('#')) return _hexToColor(rgba);
    return Colors.white70;
  }
}
