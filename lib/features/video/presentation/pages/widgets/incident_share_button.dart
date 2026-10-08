import 'package:flutter/material.dart';
import '../../../../../shared/widgets/glass/glass_primitives.dart';

/// ปุ่มแชร์เหตุการณ์ (Incident Share Button) สไตล์ Lit Glassmorphism ผสาน Neumorphic Tactile Physics
///
/// ดีไซน์:
/// - ใช้ [LitGlassSurface] ถอดแบบความงามจาก `lib/shared/widgets/glass/glass_primitives.dart`
///   (มีทั้ง Rim lighting, Specular hotspots, Bevel, Drop shadow, และ Glint แสงสะท้อนขอบบน)
/// - ทรง Glass Capsule กะทัดรัด (สูง 34dp, radius 17dp)
/// - Neumorphic Tactile Bounce: ยุบตัวนุ่มนวลด้วย [AnimatedScale] (0.96) เมื่อกดสัมผัส
/// - Dynamic Visual State: เมื่อ [isPhotoFocused] เป็นจริง จะเปล่งแสงสะท้อนขอบฟ้า (Cyan glow)
///   และเปลี่ยนไอคอน/ข้อความเป็น "แชร์ภาพนี้" เพื่อสื่อให้ผู้ใช้เห็นว่าระบบกำลังเตรียมลิงก์รูปภาพ
/// - ป้องกัน Text Overflow บนหน้าจอแคบ (320dp) ด้วย [FittedBox]
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
    final String label = widget.customLabel ??
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
        onTapCancel: isEnabled ? () => setState(() => _isPressed = false) : null,
        child: AnimatedScale(
          scale: _isPressed ? 0.96 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: isEnabled ? 1.0 : 0.6,
            duration: const Duration(milliseconds: 150),
            child: LitGlassSurface(
              borderRadius: 17,
              blurSigma: 10,
              fillOpacity: widget.isPhotoFocused ? 0.14 : 0.09,
              rimWidth: 1.2,
              rimBoost: 1.1,
              shadowOpacity: 0.25,
              accentColor:
                  widget.isPhotoFocused ? const Color(0xFF38BDF8) : null,
              accentStrength: widget.isPhotoFocused ? 0.6 : 0,
              glowOpacity: widget.isPhotoFocused ? 0.35 : 0,
              selected: widget.isPhotoFocused,
              child: Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                child: widget.isLoading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.0,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              widget.isPhotoFocused
                                  ? Icons.image_outlined
                                  : Icons.share_rounded,
                              size: 15,
                              color: widget.isPhotoFocused
                                  ? const Color(0xFFE0F2FE)
                                  : Colors.white.withValues(alpha: 0.92),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              label,
                              style: TextStyle(
                                fontFamily: 'SukhumvitSet',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: widget.isPhotoFocused
                                    ? const Color(0xFFF0F9FF)
                                    : Colors.white.withValues(alpha: 0.95),
                                shadows: widget.isPhotoFocused
                                    ? [
                                        BoxShadow(
                                          color: const Color(0xFF38BDF8)
                                              .withValues(alpha: 0.5),
                                          blurRadius: 6,
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                          ],
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
