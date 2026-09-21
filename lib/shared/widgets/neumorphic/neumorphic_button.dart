import 'package:flutter/material.dart';
import 'neumorphic_theme.dart';

/// ปุ่มกดแบบ Vibrant Gradient Pill Button พร้อมเงาเรืองแสงสีฟ้า (Cyan Glow) ตามดีไซน์รูปภาพ
///
/// **ข้อสังเกตสำหรับผู้ใช้งาน (Developer Note):**
/// - ในงานดีไซน์ Neumorphic ปุ่ม Call-to-Action (CTA) มักจะใช้สี Gradient สดใสเพื่อดึงดูดสายตา
///   แทนที่จะใช้เงาปูนสีเดียวกับพื้นหลัง
/// - ปุ่มนี้มีเงาสีฟ้าสะท้อน [NeumorphicTheme.glowShadows] ด้านล่าง เพื่อให้ดูนูนลอยขึ้นมาจากการ์ด
class NeumorphicVerifyButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final String text;
  final bool isLoading;
  final bool isEnabled;
  final double height;
  final double? width;
  final Widget? icon;

  const NeumorphicVerifyButton({
    super.key,
    required this.onPressed,
    this.text = 'VERIFY OTP',
    this.isLoading = false,
    this.isEnabled = true,
    this.height = 54.0,
    this.width = double.infinity,
    this.icon,
  });

  @override
  State<NeumorphicVerifyButton> createState() => _NeumorphicVerifyButtonState();
}

class _NeumorphicVerifyButtonState extends State<NeumorphicVerifyButton> {
  bool _isHoveredOrPressed = false;

  @override
  Widget build(BuildContext context) {
    final bool active = widget.isEnabled && !widget.isLoading && widget.onPressed != null;

    return AnimatedScale(
      scale: _isHoveredOrPressed ? 0.98 : 1.0,
      duration: const Duration(milliseconds: 100),
      child: AnimatedOpacity(
        opacity: active ? 1.0 : 0.6,
        duration: const Duration(milliseconds: 150),
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.height / 2),
            gradient: NeumorphicTheme.buttonGradient,
            boxShadow: active
                ? [
                    // เงามืดเบาๆ
                    BoxShadow(
                      color: const Color(0xFF1E40AF).withValues(alpha: 0.35),
                      offset: const Offset(0, 10),
                      blurRadius: 20,
                    ),
                    // แสงเรืองฟ้าสดใส (Cyan Glow)
                    BoxShadow(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.5),
                      offset: const Offset(0, 4),
                      blurRadius: 14,
                    ),
                  ]
                : [],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: active ? widget.onPressed : null,
              onTapDown: active ? (_) => setState(() => _isHoveredOrPressed = true) : null,
              onTapUp: active ? (_) => setState(() => _isHoveredOrPressed = false) : null,
              onTapCancel: active ? () => setState(() => _isHoveredOrPressed = false) : null,
              borderRadius: BorderRadius.circular(widget.height / 2),
              splashColor: Colors.white.withValues(alpha: 0.2),
              highlightColor: Colors.white.withValues(alpha: 0.1),
              child: Center(
                child: widget.isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            widget.text,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(width: 8),
                          widget.icon ??
                              const Icon(
                                Icons.arrow_forward,
                                color: Colors.white,
                                size: 20,
                              ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
