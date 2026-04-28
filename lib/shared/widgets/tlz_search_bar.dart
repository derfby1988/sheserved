import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// Search Bar Color Theme - กำหนดสีตามธีมของหน้า
enum TlzSearchBarColorTheme {
  /// ธีมสำหรับพื้นหลังสีเข้ม (เช่น primary green) - ใช้สีขาว
  onPrimary,
  /// ธีมสำหรับพื้นหลังสีอ่อน (เช่น white, cream) - ใช้สีเทา/ดำ
  onLight,
  /// ธีมแบบกำหนดเอง
  custom,
}

/// Search Bar Widget with QR Code Scanner
/// Rounded search bar with search icon and QR code scanner
/// รองรับหลายธีมสีเพื่อใช้งานได้ทุกหน้า
class TlzSearchBar extends StatelessWidget {
  final String? hintText;
  final VoidCallback? onSearchTap;
  final VoidCallback? onQRTap;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool enabled;
  final bool autofocus;
  final bool showQRButton;
  final bool showSearchIcon;
  
  /// ธีมสีของ Search Bar
  final TlzSearchBarColorTheme theme;
  
  /// สีแบบกำหนดเอง (ใช้เมื่อ theme = custom)
  final Color? backgroundColor;
  final Color? iconColor;
  final Color? textColor;
  final Color? hintColor;
  final Color? borderColor;

  const TlzSearchBar({
    super.key,
    this.hintText,
    this.onSearchTap,
    this.onQRTap,
    this.onChanged,
    this.onSubmitted,
    this.controller,
    this.focusNode,
    this.enabled = true,
    this.autofocus = false,
    this.showQRButton = true,
    this.showSearchIcon = true,
    this.theme = TlzSearchBarColorTheme.onPrimary,
    this.backgroundColor,
    this.iconColor,
    this.textColor,
    this.hintColor,
    this.borderColor,
  });

  /// สร้าง Search Bar สำหรับพื้นหลังสีเข้ม (primary)
  factory TlzSearchBar.onPrimary({
    Key? key,
    String? hintText,
    VoidCallback? onSearchTap,
    VoidCallback? onQRTap,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
    TextEditingController? controller,
    FocusNode? focusNode,
    bool enabled = true,
    bool autofocus = false,
    bool showQRButton = true,
    bool showSearchIcon = true,
  }) {
    return TlzSearchBar(
      key: key,
      hintText: hintText,
      onSearchTap: onSearchTap,
      onQRTap: onQRTap,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      autofocus: autofocus,
      showQRButton: showQRButton,
      showSearchIcon: showSearchIcon,
      theme: TlzSearchBarColorTheme.onPrimary,
    );
  }

  /// สร้าง Search Bar สำหรับพื้นหลังสีอ่อน (light/white)
  factory TlzSearchBar.onLight({
    Key? key,
    String? hintText,
    VoidCallback? onSearchTap,
    VoidCallback? onQRTap,
    ValueChanged<String>? onChanged,
    ValueChanged<String>? onSubmitted,
    TextEditingController? controller,
    FocusNode? focusNode,
    bool enabled = true,
    bool autofocus = false,
    bool showQRButton = true,
    bool showSearchIcon = true,
  }) {
    return TlzSearchBar(
      key: key,
      hintText: hintText,
      onSearchTap: onSearchTap,
      onQRTap: onQRTap,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      autofocus: autofocus,
      showQRButton: showQRButton,
      showSearchIcon: showSearchIcon,
      theme: TlzSearchBarColorTheme.onLight,
    );
  }

  // === Color Getters ===
  
  Color get _backgroundColor {
    if (backgroundColor != null) return backgroundColor!;
    switch (theme) {
      case TlzSearchBarColorTheme.onPrimary:
        return AppColors.primaryLight.withOpacity(0.3);
      case TlzSearchBarColorTheme.onLight:
        return AppColors.surface;
      case TlzSearchBarColorTheme.custom:
        return AppColors.surface;
    }
  }

  Color get _iconColor {
    if (iconColor != null) return iconColor!;
    switch (theme) {
      case TlzSearchBarColorTheme.onPrimary:
        return AppColors.textOnPrimary;
      case TlzSearchBarColorTheme.onLight:
        return AppColors.textSecondary;
      case TlzSearchBarColorTheme.custom:
        return AppColors.textSecondary;
    }
  }

  Color get _textColor {
    if (textColor != null) return textColor!;
    switch (theme) {
      case TlzSearchBarColorTheme.onPrimary:
        return AppColors.textOnPrimary;
      case TlzSearchBarColorTheme.onLight:
        return AppColors.textPrimary;
      case TlzSearchBarColorTheme.custom:
        return AppColors.textPrimary;
    }
  }

  Color get _hintColor {
    if (hintColor != null) return hintColor!;
    switch (theme) {
      case TlzSearchBarColorTheme.onPrimary:
        return AppColors.textOnPrimary.withOpacity(0.6);
      case TlzSearchBarColorTheme.onLight:
        return AppColors.textHint;
      case TlzSearchBarColorTheme.custom:
        return AppColors.textHint;
    }
  }

  Color get _borderColor {
    if (borderColor != null) return borderColor!;
    switch (theme) {
      case TlzSearchBarColorTheme.onPrimary:
        return AppColors.textOnPrimary.withOpacity(0.1);
      case TlzSearchBarColorTheme.onLight:
        return AppColors.border;
      case TlzSearchBarColorTheme.custom:
        return AppColors.border;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? null : onSearchTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: _backgroundColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: _borderColor,
            width: 1,
          ),
          boxShadow: theme == TlzSearchBarColorTheme.onLight
              ? [
                  BoxShadow(
                    color: AppColors.shadow,
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            
            // Search Icon
            if (showSearchIcon)
              GestureDetector(
                onTap: onSearchTap,
                child: Icon(
                  Icons.search,
                  color: _iconColor,
                  size: 20,
                ),
              ),
            
            // TextField or Hint
            if (enabled && (controller != null || onChanged != null)) ...[
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  autofocus: autofocus,
                  enabled: enabled,
                  style: TextStyle(
                    color: _textColor,
                    fontSize: 14,
                  ),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: hintText ?? 'ค้นหา...',
                    hintStyle: TextStyle(
                      color: _hintColor,
                      fontSize: 14,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  hintText ?? 'ค้นหา...',
                  style: TextStyle(
                    color: _hintColor,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
            
            // QR Code Button
            if (showQRButton)
              GestureDetector(
                onTap: onQRTap,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Icon(
                    Icons.qr_code_scanner,
                    color: _iconColor,
                    size: 20,
                  ),
                ),
              ),
            
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
