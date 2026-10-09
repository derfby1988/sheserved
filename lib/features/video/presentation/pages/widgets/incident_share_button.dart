import 'package:flutter/material.dart';
import '../../../../../shared/widgets/glass/glass_primitives.dart';

/// ปุ่มแชร์เหตุการณ์ (Incident Share Button) สไตล์ Lit Glassmorphism ผสาน Neumorphic Tactile Physics
///
/// ดีไซน์:
/// - ใช้ [LitGlassSurface] ถอดแบบความงามจาก `lib/shared/widgets/glass/glass_primitives.dart`
///   (มีทั้ง Rim lighting, Specular hotspots, Bevel, Drop shadow, และ Glint แสงสะท้อนขอบบน)
/// - ทรงกลมไอคอนล้วน (34×34dp, radius 17dp) ไม่มีข้อความ — ไอคอนสีส้ม
///   `0xFFFF6B35` โทนเดียวกับพื้นหลังป้าย "ยอดนิยม"
/// - Neumorphic Tactile Bounce: ยุบตัวนุ่มนวลด้วย [AnimatedScale] (0.96) เมื่อกดสัมผัส
/// - Dynamic Visual State: เมื่อ [isPhotoFocused] เป็นจริง จะเปล่งแสงสะท้อนขอบฟ้า (Cyan glow)
///   และสลับไอคอนเป็น `Icons.image_outlined` เพื่อสื่อว่าระบบกำลังเตรียมลิงก์รูปภาพ
class IncidentShareButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isPhotoFocused;
  final String? customLabel;

  const IncidentShareButton({
    super.key,
    required this.onPressed,
    this.isLoading = false,
    this.isPhotoFocused = false,
    this.customLabel,
  });

  @override
  State<IncidentShareButton> createState() => _IncidentShareButtonState();
}

class _IncidentShareButtonState extends State<IncidentShareButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final bool isEnabled = widget.onPressed != null && !widget.isLoading;
    final String label =
        widget.customLabel ??
        (widget.isPhotoFocused ? 'แชร์ภาพนี้' : 'แชร์เหตุการณ์');

    return Semantics(
      button: true,
      enabled: isEnabled,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: isEnabled ? widget.onPressed : null,
        onTapDown: isEnabled ? (_) => setState(() => _isPressed = true) : null,
        onTapUp: isEnabled ? (_) => setState(() => _isPressed = false) : null,
        onTapCancel: isEnabled
            ? () => setState(() => _isPressed = false)
            : null,
        child: AnimatedScale(
          scale: _isPressed ? 0.96 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: isEnabled ? 1.0 : 0.6,
            duration: const Duration(milliseconds: 150),
            child: Align(
              // Column ผู้ใช้ใช้ stretch — บังคับให้กระจกคงขนาดวงกลม 34dp
              alignment: Alignment.center,
              child: LitGlassSurface(
                borderRadius: 17,
                blurSigma: 10,
                fillOpacity: widget.isPhotoFocused ? 0.14 : 0.09,
                rimWidth: 1.2,
                rimBoost: 1.1,
                shadowOpacity: 0.25,
                accentColor: widget.isPhotoFocused
                    ? const Color(0xFF38BDF8)
                    : null,
                accentStrength: widget.isPhotoFocused ? 0.6 : 0,
                glowOpacity: widget.isPhotoFocused ? 0.35 : 0,
                selected: widget.isPhotoFocused,
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: Center(
                    child: widget.isLoading
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.0,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Color(0xFFFF6B35),
                              ),
                            ),
                          )
                        : Icon(
                            widget.isPhotoFocused
                                ? Icons.image_outlined
                                : Icons.share_rounded,
                            size: 17,
                            color: widget.isPhotoFocused
                                ? const Color(0xFFE0F2FE)
                                : const Color(0xFFFF6B35),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
