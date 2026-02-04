import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// App Text Styles for Sheserved
/// ใช้ฟอนต์ Sarabun สำหรับภาษาไทย
class AppTextStyles {
  AppTextStyles._();

  // Base font family
  static String get fontFamily => 'Sarabun';

  // Headings
  static TextStyle get heading1 => GoogleFonts.sarabun(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
        height: 1.3,
      );

  static TextStyle get heading2 => GoogleFonts.sarabun(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
        height: 1.3,
      );

  static TextStyle get heading3 => GoogleFonts.sarabun(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        height: 1.3,
      );

  static TextStyle get heading4 => GoogleFonts.sarabun(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        height: 1.3,
      );

  static TextStyle get heading5 => GoogleFonts.sarabun(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        height: 1.3,
      );

  // Body
  static TextStyle get bodyLarge => GoogleFonts.sarabun(
        fontSize: 16,
        fontWeight: FontWeight.normal,
        color: AppColors.textPrimary,
        height: 1.5,
      );

  static TextStyle get bodyMedium => GoogleFonts.sarabun(
        fontSize: 14,
        fontWeight: FontWeight.normal,
        color: AppColors.textPrimary,
        height: 1.5,
      );

  static TextStyle get bodySmall => GoogleFonts.sarabun(
        fontSize: 12,
        fontWeight: FontWeight.normal,
        color: AppColors.textSecondary,
        height: 1.5,
      );

  // Labels
  static TextStyle get labelLarge => GoogleFonts.sarabun(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
        height: 1.4,
      );

  static TextStyle get labelMedium => GoogleFonts.sarabun(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
        height: 1.4,
      );

  static TextStyle get labelSmall => GoogleFonts.sarabun(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
        height: 1.4,
      );

  // Button
  static TextStyle get button => GoogleFonts.sarabun(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.textOnPrimary,
        height: 1.2,
      );

  static TextStyle get buttonSmall => GoogleFonts.sarabun(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textOnPrimary,
        height: 1.2,
      );

  // Caption
  static TextStyle get caption => GoogleFonts.sarabun(
        fontSize: 12,
        fontWeight: FontWeight.normal,
        color: AppColors.textHint,
        height: 1.4,
      );

  // Price
  static TextStyle get price => GoogleFonts.sarabun(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: AppColors.primary,
        height: 1.2,
      );

  static TextStyle get priceSmall => GoogleFonts.sarabun(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.primary,
        height: 1.2,
      );

  // Logo/Brand
  static TextStyle get brand => GoogleFonts.sarabun(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: AppColors.primary,
        letterSpacing: 1.2,
        height: 1.2,
      );

  static TextStyle get brandSubtitle => GoogleFonts.sarabun(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.valley,
        letterSpacing: 2,
        height: 1.2,
      );
}
