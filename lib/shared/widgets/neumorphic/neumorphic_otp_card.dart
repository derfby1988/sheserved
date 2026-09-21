import 'package:flutter/material.dart';
import 'neumorphic_theme.dart';
import 'neumorphic_container.dart';
import 'neumorphic_lock_badge.dart';
import 'neumorphic_button.dart';
import 'neumorphic_otp_field.dart';

/// การ์ดยืนยันรหัส OTP สไตล์ Neumorphism แบบประณีตตามภาพตัวอย่าง 100%
///
/// **ข้อสังเกตสำหรับผู้ใช้งาน (Developer Notes & Best Practices):**
/// 1. **สีพื้นหลัง:** คอนเซปต์ Neumorphism จำเป็นต้องมีสีพื้นหลังของหน้าจอเป็น `#E7EBF0`
///    เพื่อให้มิติเงาสองชั้น (สว่างบนซ้าย + มืดล่างขวา) เชื่อมต่อกับพื้นหลังอย่างไร้รอยต่อ
///    หากใช้ในหน้าจอทั่วไป แนะนำให้ใช้ [NeumorphicOtpCard.page] หรือตั้งค่า
///    `scaffoldBackgroundColor: NeumorphicTheme.baseColor`
/// 2. **ความยืดหยุ่น (Flexible Widget):**
///    - สามารถใช้เป็น Widget เดี่ยวๆ ไปวางใน `SingleChildScrollView` หรือ `Center`
///    - สามารถเปิดเป็น Dialog ผ่าน [NeumorphicOtpCard.showAsDialog]
///    - หรือเปิดเป็นหน้าเต็มจอพร้อมวงกลมลอยพื้นหลังผ่าน [NeumorphicOtpCard.page]
/// 3. **UI ล้วน (Pure UI with Callbacks):**
///    - สามารถส่ง `onVerify`, `onCompleted`, `onResendRequested` เพื่อผูกกับ Service ใดก็ได้
class NeumorphicOtpCard extends StatefulWidget {
  /// เบอร์โทรศัพท์หรืออีเมลปลายทางที่จะแสดง (เช่น "+66 8X XXX 1234")
  final String destinationText;

  /// หัวข้อหลัก (ค่าเริ่มต้น: "ยืนยันรหัส OTP" หรือกำหนดเอง เช่น "Verify Your OTP")
  final String title;

  /// ข้อความอธิบายก่อนเบอร์โทร (ค่าเริ่มต้น: "เราได้ส่งรหัสยืนยัน 6 หลักไปที่")
  final String subtitle;

  /// ข้อความบนปุ่ม (ค่าเริ่มต้น: "VERIFY OTP")
  final String buttonText;

  /// ข้อความเวลานับถอยหลัง (ฟอร์แมต '%s' จะถูกแทนด้วยเวลา เช่น "ส่งรหัสใหม่อีกครั้งใน %s")
  final String resendCountdownText;

  /// ข้อความเมื่อสามารถกดส่งรหัสใหม่ได้แล้ว
  final String resendAvailableText;

  /// จำนวนวินาทีที่เหลือสำหรับการนับถอยหลังส่งใหม่
  final int resendRemainingSeconds;

  /// ข้อความ Error เมื่อกรอกผิดหรือเกิดข้อผิดพลาด
  final String? errorMessage;

  /// สถานะกำลังโหลด / ตรวจสอบ
  final bool isLoading;

  /// จำนวนหลักของ OTP (ค่าเริ่มต้น 6 หลัก)
  final int otpLength;

  /// Callback เมื่อผู้ใช้กดปุ่ม Verify OTP
  final void Function(String otpCode)? onVerify;

  /// Callback เมื่อกรอกรหัสครบทุกหลักอัตโนมัติ
  final void Function(String otpCode)? onCompleted;

  /// Callback เมื่อผู้ใช้กดขอรหัสใหม่ (Resend OTP)
  final VoidCallback? onResendRequested;

  /// Callback เมื่อรหัส OTP มีการเปลี่ยนแปลง
  final ValueChanged<String>? onOtpChanged;

  /// Controller สำหรับควบคุมข้อความ OTP จากภายนอก
  final TextEditingController? controller;

  /// ความกว้างสูงสุดของการ์ด
  final double maxWidth;

  const NeumorphicOtpCard({
    super.key,
    required this.destinationText,
    this.title = 'ยืนยันรหัส OTP',
    this.subtitle = 'เราได้ส่งรหัสยืนยัน 6 หลักไปที่',
    this.buttonText = 'VERIFY OTP',
    this.resendCountdownText = 'ส่งรหัสใหม่อีกครั้งใน %s',
    this.resendAvailableText = 'ส่งรหัสใหม่อีกครั้ง',
    this.resendRemainingSeconds = 0,
    this.errorMessage,
    this.isLoading = false,
    this.otpLength = 6,
    this.onVerify,
    this.onCompleted,
    this.onResendRequested,
    this.onOtpChanged,
    this.controller,
    this.maxWidth = 420.0,
  });

  /// แสดงการ์ด OTP นี้ในรูปแบบ Dialog
  static Future<T?> showAsDialog<T>({
    required BuildContext context,
    required String destinationText,
    String title = 'ยืนยันรหัส OTP',
    String subtitle = 'เราได้ส่งรหัสยืนยัน 6 หลักไปที่',
    String buttonText = 'VERIFY OTP',
    int resendRemainingSeconds = 0,
    String? errorMessage,
    bool isLoading = false,
    void Function(String otpCode)? onVerify,
    void Function(String otpCode)? onCompleted,
    VoidCallback? onResendRequested,
    TextEditingController? controller,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: NeumorphicOtpCard(
          destinationText: destinationText,
          title: title,
          subtitle: subtitle,
          buttonText: buttonText,
          resendRemainingSeconds: resendRemainingSeconds,
          errorMessage: errorMessage,
          isLoading: isLoading,
          onVerify: onVerify,
          onCompleted: onCompleted,
          onResendRequested: onResendRequested,
          controller: controller,
        ),
      ),
    );
  }

  /// แสดงเป็นหน้าจอเต็มจอ (Full Page Scaffold) พร้อมวงกลมลอยพื้นหลังแบบ Neumorphic เหมือนรูปต้นฉบับ
  static Widget page({
    required String destinationText,
    String title = 'Verify Your OTP',
    String subtitle = "We've sent a 6-digit verification code to",
    String buttonText = 'VERIFY OTP',
    int resendRemainingSeconds = 25,
    String? errorMessage,
    bool isLoading = false,
    void Function(String otpCode)? onVerify,
    void Function(String otpCode)? onCompleted,
    VoidCallback? onResendRequested,
    TextEditingController? controller,
    PreferredSizeWidget? appBar,
  }) {
    return Scaffold(
      backgroundColor: NeumorphicTheme.baseColor,
      appBar: appBar,
      body: Stack(
        children: [
          // วงกลม Neumorphic ลอยเป็นพื้นหลังตาม CSS .bg-circle ในรูป
          Positioned(
            top: -60,
            left: -60,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: NeumorphicTheme.baseColor,
                boxShadow: [
                  BoxShadow(
                    color: NeumorphicTheme.shadowDark.withValues(alpha: 0.55),
                    offset: const Offset(15, 15),
                    blurRadius: 30,
                  ),
                  BoxShadow(
                    color: NeumorphicTheme.shadowLight,
                    offset: const Offset(-15, -15),
                    blurRadius: 30,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: -80,
            right: -80,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: NeumorphicTheme.baseColor,
                boxShadow: [
                  BoxShadow(
                    color: NeumorphicTheme.shadowDark.withValues(alpha: 0.55),
                    offset: const Offset(15, 15),
                    blurRadius: 30,
                  ),
                  BoxShadow(
                    color: NeumorphicTheme.shadowLight,
                    offset: const Offset(-15, -15),
                    blurRadius: 30,
                  ),
                ],
              ),
            ),
          ),

          // การ์ดตรงกลาง
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
              child: NeumorphicOtpCard(
                destinationText: destinationText,
                title: title,
                subtitle: subtitle,
                buttonText: buttonText,
                resendRemainingSeconds: resendRemainingSeconds,
                errorMessage: errorMessage,
                isLoading: isLoading,
                onVerify: onVerify,
                onCompleted: onCompleted,
                onResendRequested: onResendRequested,
                controller: controller,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  State<NeumorphicOtpCard> createState() => _NeumorphicOtpCardState();
}

class _NeumorphicOtpCardState extends State<NeumorphicOtpCard> {
  late TextEditingController _otpController;
  bool _ownsController = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _otpController = widget.controller!;
    } else {
      _otpController = TextEditingController();
      _ownsController = true;
    }
  }

  @override
  void dispose() {
    if (_ownsController) {
      _otpController.dispose();
    }
    super.dispose();
  }

  void _handleVerify() {
    final code = _otpController.text.trim();
    widget.onVerify?.call(code);
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: widget.maxWidth),
      child: NeumorphicContainer(
        // ค่าตรงตาม CSS ในภาพ: padding: 40px 38px; border-radius: 35px;
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
        borderRadius: 35.0,
        depth: 20.0,
        blur: 40.0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 1. ไอคอนแม่กุญแจ Neumorphic Lock Badge ด้านบน
            const NeumorphicLockBadge(
              size: 78,
              iconSize: 36,
            ),
            const SizedBox(height: 24),

            // 2. หัวข้อ "Verify Your OTP" / "ยืนยันรหัส OTP"
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: NeumorphicTheme.textPrimary,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 10),

            // 3. ข้อความรอง "We've sent a 6-digit verification code to"
            Text(
              widget.subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: NeumorphicTheme.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 4),

            // เบอร์โทรศัพท์ / ปลายทาง
            Text(
              widget.destinationText,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: NeumorphicTheme.textPrimary,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 28),

            // 4. ช่องกรอกรหัส 6 ช่อง Neumorphic Otp Field พร้อม Active Cyan Glow
            NeumorphicOtpField(
              length: widget.otpLength,
              controller: _otpController,
              onChanged: widget.onOtpChanged,
              onCompleted: (code) {
                widget.onCompleted?.call(code);
              },
            ),

            // แสดงข้อความแจ้งเตือน Error (ถ้ามี)
            if (widget.errorMessage != null && widget.errorMessage!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 16, color: Colors.red.shade700),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        widget.errorMessage!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade800,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 28),

            // 5. ปุ่ม VERIFY OTP Gradient พร้อมเงาเรืองแสงสีฟ้า
            NeumorphicVerifyButton(
              text: widget.buttonText,
              isLoading: widget.isLoading,
              isEnabled: !widget.isLoading,
              onPressed: _handleVerify,
            ),
            const SizedBox(height: 24),

            // 6. ข้อความนับถอยหลังส่งรหัสใหม่ Resend OTP Countdown
            _buildResendSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildResendSection() {
    if (widget.resendRemainingSeconds > 0) {
      final secondsText = '${widget.resendRemainingSeconds} seconds';
      final textTemplate = widget.resendCountdownText;

      if (textTemplate.contains('%s')) {
        final parts = textTemplate.split('%s');
        return Text.rich(
          TextSpan(
            text: parts[0],
            style: const TextStyle(
              fontSize: 13,
              color: NeumorphicTheme.textSecondary,
              fontWeight: FontWeight.w400,
            ),
            children: [
              TextSpan(
                text: secondsText,
                style: const TextStyle(
                  color: Color(0xFF0284C7), // Bright Cyan/Blue ตามรูป
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (parts.length > 1)
                TextSpan(
                  text: parts[1],
                  style: const TextStyle(
                    fontSize: 13,
                    color: NeumorphicTheme.textSecondary,
                  ),
                ),
            ],
          ),
          textAlign: TextAlign.center,
        );
      }

      return Text(
        '$textTemplate $secondsText',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 13,
          color: NeumorphicTheme.textSecondary,
        ),
      );
    }

    // สามารถกดขอรหัสใหม่ได้แล้ว
    return TextButton(
      onPressed: widget.isLoading ? null : widget.onResendRequested,
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF0284C7),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        widget.resendAvailableText,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
