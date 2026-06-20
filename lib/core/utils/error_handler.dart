import 'package:flutter/material.dart';

/// Utility class สำหรับแปลง technical error เป็นภาษาผู้ใช้
/// และแสดง SnackBar พร้อม action retry ที่ใช้ซ้ำได้ทั้งแอป
class ErrorHandler {
  ErrorHandler._();

  /// แปลง Exception/Error เป็นข้อความที่ผู้ใช้เข้าใจ
  static String getUserFriendlyMessage(Object error) {
    final msg = error.toString().toLowerCase();

    if (msg.contains('socketexception') ||
        msg.contains('connection refused') ||
        msg.contains('connection reset') ||
        msg.contains('no route to host') ||
        msg.contains('clientexception')) {
      return 'ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้ กรุณาตรวจสอบว่าระบบ backend กำลังทำงานอยู่ และลองใหม่อีกครั้ง';
    }

    if (msg.contains('timeout') || msg.contains('timed out')) {
      return 'การเชื่อมต่อใช้เวลานานเกินไป กรุณาลองใหม่อีกครั้ง';
    }

    if (msg.contains('unauthorized') || msg.contains('401')) {
      return 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่';
    }

    if (msg.contains('failed to submit') || msg.contains('consultation')) {
      return 'ไม่สามารถส่งคำปรึกษาได้ กรุณาลองใหม่อีกครั้ง';
    }

    if (msg.contains('กรุณาเลือกเข้าสู่ระบบ')) {
      return 'กรุณาเข้าสู่ระบบก่อนดำเนินการ';
    }

    // Fallback สำหรับ error อื่น ๆ
    return 'เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้ง';
  }

  /// แสดง SnackBar แจ้ง error พร้อมปุ่ม retry
  ///
  /// [context] — BuildContext สำหรับ show SnackBar
  /// [error] — Exception หรือ Error ที่เกิดขึ้น
  /// [onRetry] — callback เมื่อผู้ใช้กด "ลองใหม่" (null = ไม่แสดงปุ่ม)
  /// [duration] — ระยะเวลาแสดง SnackBar (default 6 วินาที)
  static void showErrorSnackBar(
    BuildContext context,
    Object error, {
    VoidCallback? onRetry,
    Duration duration = const Duration(seconds: 6),
  }) {
    final message = getUserFriendlyMessage(error);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFB00020),
        duration: duration,
        behavior: SnackBarBehavior.floating,
        action: onRetry != null
            ? SnackBarAction(
                label: 'ลองใหม่',
                textColor: Colors.white,
                onPressed: onRetry,
              )
            : null,
      ),
    );
  }

  /// ปิด loading dialog ที่เปิดด้วย showDialog(useRootNavigator: true)
  static void dismissLoadingDialog(BuildContext context) {
    if (Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }
}
