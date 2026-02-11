import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import 'tlz_hamburger_menu.dart';
import 'tlz_animated_search_bar.dart';
import 'tlz_notification_button.dart';
import 'tlz_cart_button.dart';

/// App Top Bar Widget
/// Reusable top navigation bar with hamburger menu, animated search bar, notification, and cart
/// รองรับหลายธีมสีเพื่อใช้งานได้ทุกหน้า
class TlzAppTopBar extends StatelessWidget {
  final VoidCallback? onMenuPressed;
  final VoidCallback? onQRTap;
  final VoidCallback? onNotificationTap;
  final VoidCallback? onCartTap;
  final String? searchHintText;
  final int notificationCount;
  final int? cartItemCount;
  
  /// ธีมสีของ Search Bar
  final TlzSearchTheme searchBarTheme;
  
  /// แสดงปุ่ม QR Scanner หรือไม่
  final bool showQRButton;
  
  /// Callback เมื่อค้นหา
  final Function(String query, List<Map<String, dynamic>> results)? onSearch;
  
  /// Callback เมื่อกดผลการค้นหา
  final Function(Map<String, dynamic> item)? onResultTap;
  
  /// ประวัติการค้นหา
  final List<String>? searchHistory;
  
  /// คำแนะนำการค้นหา
  final List<Map<String, dynamic>>? searchSuggestions;

  /// Widget ทางซ้ายสุด (ถ้าไม่กำหนดจะใช้ Hamburger Menu)
  final Widget? leading;

  /// Widget ตรงกลาง (ถ้าไม่กำหนดจะใช้ TlzAnimatedSearchBar)
  final Widget? middle;

  const TlzAppTopBar({
    super.key,
    this.onMenuPressed,
    this.onQRTap,
    this.onNotificationTap,
    this.onCartTap,
    this.searchHintText,
    this.notificationCount = 0,
    this.cartItemCount,
    this.searchBarTheme = TlzSearchTheme.onPrimary,
    this.showQRButton = true,
    this.onSearch,
    this.onResultTap,
    this.searchHistory,
    this.searchSuggestions,
    this.leading,
    this.middle,
  });

  /// สร้าง Top Bar สำหรับพื้นหลังสีเข้ม (primary)
  factory TlzAppTopBar.onPrimary({
    Key? key,
    VoidCallback? onMenuPressed,
    VoidCallback? onQRTap,
    VoidCallback? onNotificationTap,
    VoidCallback? onCartTap,
    String? searchHintText,
    int notificationCount = 0,
    int? cartItemCount,
    bool showQRButton = true,
    Function(String query, List<Map<String, dynamic>> results)? onSearch,
    Function(Map<String, dynamic> item)? onResultTap,
    List<String>? searchHistory,
    List<Map<String, dynamic>>? searchSuggestions,
    Widget? leading,
    Widget? middle,
  }) {
    return TlzAppTopBar(
      key: key,
      onMenuPressed: onMenuPressed,
      onQRTap: onQRTap,
      onNotificationTap: onNotificationTap,
      onCartTap: onCartTap,
      searchHintText: searchHintText,
      notificationCount: notificationCount,
      cartItemCount: cartItemCount,
      searchBarTheme: TlzSearchTheme.onPrimary,
      showQRButton: showQRButton,
      onSearch: onSearch,
      onResultTap: onResultTap,
      searchHistory: searchHistory,
      searchSuggestions: searchSuggestions,
      leading: leading,
      middle: middle,
    );
  }

  /// สร้าง Top Bar สำหรับพื้นหลังสีอ่อน (light/white)
  factory TlzAppTopBar.onLight({
    Key? key,
    VoidCallback? onMenuPressed,
    VoidCallback? onQRTap,
    VoidCallback? onNotificationTap,
    VoidCallback? onCartTap,
    String? searchHintText,
    int notificationCount = 0,
    int? cartItemCount,
    bool showQRButton = true,
    Function(String query, List<Map<String, dynamic>> results)? onSearch,
    Function(Map<String, dynamic> item)? onResultTap,
    List<String>? searchHistory,
    List<Map<String, dynamic>>? searchSuggestions,
    Widget? leading,
    Widget? middle,
  }) {
    return TlzAppTopBar(
      key: key,
      onMenuPressed: onMenuPressed,
      onQRTap: onQRTap,
      onNotificationTap: onNotificationTap,
      onCartTap: onCartTap,
      searchHintText: searchHintText,
      notificationCount: notificationCount,
      cartItemCount: cartItemCount,
      searchBarTheme: TlzSearchTheme.onLight,
      showQRButton: showQRButton,
      onSearch: onSearch,
      onResultTap: onResultTap,
      searchHistory: searchHistory,
      searchSuggestions: searchSuggestions,
      leading: leading,
      middle: middle,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Leading Widget (Hamburger Menu or Custom)
        leading ?? TlzHamburgerMenu(
          onPressed: onMenuPressed,
        ),
        
        const SizedBox(width: 12),
        
        // Animated Search Bar or Custom Middle Widget
        Expanded(
          child: middle ?? TlzAnimatedSearchBar(
            hintText: searchHintText,
            theme: searchBarTheme,
            onQRTap: onQRTap,
            showQRButton: showQRButton,
            searchHistory: searchHistory,
            suggestions: searchSuggestions,
            onSearch: onSearch,
            onResultTap: onResultTap,
          ),
        ),
        
        const SizedBox(width: 12),
        
        // Notification Button
        TlzNotificationButton(
          badgeCount: notificationCount,
          onPressed: onNotificationTap,
        ),
        
        const SizedBox(width: 8),
        
        // Cart Button
        TlzCartButton(
          itemCount: cartItemCount,
          onPressed: onCartTap,
        ),
      ],
    );
  }
}
