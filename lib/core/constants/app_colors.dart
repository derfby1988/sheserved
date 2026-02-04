import 'package:flutter/material.dart';

/// App Colors for Sheserved
/// โทนสีธรรมชาติ - ป่า ต้นไม้ น้ำตก
class AppColors {
  AppColors._();

  // Primary Colors - Green จาก Figma Design
  static const Color primary = Color(0xFF71BE0A); // Green สำหรับ header (#71BE0A)
  static const Color primaryLight = Color(0xFFA7E062); // Bright lime green สำหรับ dotted border (#A7E062 หรือ #A9E267)
  static const Color primaryDark = Color(0xFF6AA84F); // Darker saturated green สำหรับจุดเล็กๆ

  // Secondary Colors - น้ำตาลธรรมชาติ
  static const Color secondary = Color(0xFF795548);
  static const Color secondaryLight = Color(0xFFA98274);
  static const Color secondaryDark = Color(0xFF4B2C20);

  // Accent Colors - สำหรับ notification badge และ hamburger menu (จาก Med Design)
  static const Color accent = Color(0xFFFFB74D); // Light orange-yellow สำหรับ notification และ hamburger menu
  static const Color accentLight = Color(0xFFFFE082);
  static const Color accentDark = Color(0xFFFFA000);
  
  // Cart Icon Color
  static const Color cartIcon = Color(0xFF9E9E9E); // Light grey-purple สำหรับ cart icon

  // Valley Blue - สำหรับ "valley" theme (น้ำตก/ลำธาร)
  static const Color valley = Color(0xFF0288D1);
  static const Color valleyLight = Color(0xFF4FC3F7);
  static const Color valleyDark = Color(0xFF01579B);

  // Background Colors - Very Pale Mint Green (จาก Med Design)
  static const Color background = Color(0xFFEBF5E0); // Very pale mint green background (#EBF5E0 หรือ #F0F9E8)
  static const Color backgroundWhite = Color(0xFFFFFFFF);
  static const Color backgroundCream = Color(0xFFF0F9E8); // Alternative pale mint

  // Surface Colors
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF5F5F5);

  // Text Colors
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
  static const Color textHint = Color(0xFF9E9E9E);
  static const Color textOnPrimary = Color(0xFFFFFFFF);
  static const Color textOnSecondary = Color(0xFFFFFFFF);

  // Status Colors
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFF9800);
  static const Color error = Color(0xFFF44336);
  static const Color info = Color(0xFF2196F3);

  // Queue Status Colors
  static const Color queueCooking = Color(0xFFFF9800);   // ปรุง - ส้ม
  static const Color queueServing = Color(0xFF2196F3);  // เสริฟ - ฟ้า
  static const Color queueCompleted = Color(0xFF4CAF50); // เสร็จ - เขียว

  // Divider & Border
  static const Color divider = Color(0xFFE0E0E0);
  static const Color border = Color(0xFFBDBDBD);

  // Shadow
  static const Color shadow = Color(0x1A000000);

  // Gradient
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primaryLight],
  );

  static const LinearGradient valleyGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [valleyLight, valley],
  );

  static const LinearGradient goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accentLight, accent],
  );
}
