import 'package:flutter/material.dart';
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
  final int? notificationCount;
  final String? notificationCategory;
  final int? cartItemCount;
  
  /// ธีมสีของ Search Bar
  final TlzSearchTheme searchBarTheme;
  
  /// แสดงปุ่ม QR Scanner หรือไม่
  final bool showQRButton;
  
  /// Callback เมื่อค้นหา
  final Function(String query, List<Map<String, dynamic>> results)? onSearch;

  /// Callback เมื่อกดผลการค้นหา
  final Function(Map<String, dynamic> item)? onResultTap;
  
  /// Callback เมื่อค้นหาแบบ submit
  final Function(String query)? onSearchSubmit;
  
  /// ประวัติการค้นหา
  final List<String>? searchHistory;
  
  /// คำแนะนำการค้นหา
  final List<Map<String, dynamic>>? searchSuggestions;

  /// Widget ทางซ้ายสุด (ถ้าไม่กำหนดจะใช้ Hamburger Menu)
  final Widget? leading;

  /// Widget ตรงกลาง (ถ้าไม่กำหนดจะใช้ TlzAnimatedSearchBar)
  final Widget? middle;

  /// Custom action widgets
  final List<Widget>? actions;

  const TlzAppTopBar({
    super.key,
    this.onMenuPressed,
    this.onQRTap,
    this.onNotificationTap,
    this.onCartTap,
    this.searchHintText,
    this.notificationCount,
    this.notificationCategory,
    this.cartItemCount,
    this.searchBarTheme = TlzSearchTheme.onPrimary,
    this.showQRButton = true,
    this.onSearch,
    this.onResultTap,
    this.onSearchSubmit,
    this.searchHistory,
    this.searchSuggestions,
    this.leading,
    this.middle,
    this.actions,
  });

  /// สร้าง Top Bar สำหรับพื้นหลังสีเข้ม (primary)
  factory TlzAppTopBar.onPrimary({
    Key? key,
    VoidCallback? onMenuPressed,
    VoidCallback? onQRTap,
    VoidCallback? onNotificationTap,
    VoidCallback? onCartTap,
    String? searchHintText,
    int? notificationCount,
    String? notificationCategory,
    int? cartItemCount,
    bool showQRButton = true,
    Function(String query, List<Map<String, dynamic>> results)? onSearch,
    Function(Map<String, dynamic> item)? onResultTap,
    Function(String query)? onSearchSubmit,
    List<String>? searchHistory,
    List<Map<String, dynamic>>? searchSuggestions,
    Widget? leading,
    Widget? middle,
    List<Widget>? actions,
  }) {
    return TlzAppTopBar(
      key: key,
      onMenuPressed: onMenuPressed,
      onQRTap: onQRTap,
      onNotificationTap: onNotificationTap,
      onCartTap: onCartTap,
      searchHintText: searchHintText,
      notificationCount: notificationCount,
      notificationCategory: notificationCategory,
      cartItemCount: cartItemCount,
      searchBarTheme: TlzSearchTheme.onPrimary,
      showQRButton: showQRButton,
      onSearch: onSearch,
      onResultTap: onResultTap,
      onSearchSubmit: onSearchSubmit,
      searchHistory: searchHistory,
      searchSuggestions: searchSuggestions,
      leading: leading,
      middle: middle,
      actions: actions,
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
    int? notificationCount,
    String? notificationCategory,
    int? cartItemCount,
    bool showQRButton = true,
    Function(String query, List<Map<String, dynamic>> results)? onSearch,
    Function(Map<String, dynamic> item)? onResultTap,
    Function(String query)? onSearchSubmit,
    List<String>? searchHistory,
    List<Map<String, dynamic>>? searchSuggestions,
    Widget? leading,
    Widget? middle,
    List<Widget>? actions,
  }) {
    return TlzAppTopBar(
      key: key,
      onMenuPressed: onMenuPressed,
      onQRTap: onQRTap,
      onNotificationTap: onNotificationTap,
      onCartTap: onCartTap,
      searchHintText: searchHintText,
      notificationCount: notificationCount,
      notificationCategory: notificationCategory,
      cartItemCount: cartItemCount,
      searchBarTheme: TlzSearchTheme.onLight,
      showQRButton: showQRButton,
      onSearch: onSearch,
      onResultTap: onResultTap,
      onSearchSubmit: onSearchSubmit,
      searchHistory: searchHistory,
      searchSuggestions: searchSuggestions,
      leading: leading,
      middle: middle,
      actions: actions,
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
        
        const SizedBox(width: 4),
        
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
            onSearchSubmit: onSearchSubmit,
          ),
        ),
        
        if (actions != null) ...[
          const SizedBox(width: 8),
          ...actions!,
        ],

        const SizedBox(width: 12),
        
        // Notification Button
        TlzNotificationButton(
          badgeCount: notificationCount,
          onPressed: onNotificationTap,
          category: notificationCategory,
        ),
        
        const SizedBox(width: 8),
        
        // Cart Button
        TlzCartButton(
          itemCount: cartItemCount,
          onPressed: onCartTap ?? () {
            Navigator.pushNamed(context, '/cart');
          },
        ),
      ],
    );
  }
}
