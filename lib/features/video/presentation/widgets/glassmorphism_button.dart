import 'dart:ui';
import 'package:flutter/material.dart';

/// ปุ่มแบบ Glassmorphism (กระจกฝ้าโปร่งแสง)
class GlassmorphismButton extends StatelessWidget {
  final String label;
  final String? value;
  final VoidCallback? onTap;
  final Color textColor;
  final Color? valueColor;
  final IconData? icon;
  final double borderRadius;

  const GlassmorphismButton({
    super.key,
    required this.label,
    this.value,
    this.onTap,
    this.textColor = const Color(0xFFFF6B35),
    this.valueColor,
    this.icon,
    this.borderRadius = 12,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.25),
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (value != null) ...[
                  Text(
                    value!,
                    style: TextStyle(
                      fontFamily: 'SukhumvitSet',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: valueColor ?? Colors.black87,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                if (icon != null) ...[
                  Icon(icon, size: 16, color: textColor),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'SukhumvitSet',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ปุ่ม Tab ด้านล่าง (Live, ความสัมพันธ์, แจ้งเหตุ)
class GlassTabButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  const GlassTabButton({
    super.key,
    required this.label,
    this.isActive = false,
    this.leading,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isActive
                  ? Colors.white.withOpacity(0.85)
                  : Colors.white.withOpacity(0.55),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withOpacity(0.4),
                width: 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(height: 2),
                ],
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'SukhumvitSet',
                    fontSize: 12,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: isActive ? Colors.black87 : Colors.black54,
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(height: 2),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
