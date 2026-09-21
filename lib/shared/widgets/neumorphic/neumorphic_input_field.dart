import 'package:flutter/material.dart';
import 'neumorphic_theme.dart';
import 'neumorphic_inset.dart';

/// ช่องกรอกข้อความสไตล์ Neumorphic Inset (ร่องลึกสมจริง)
///
/// **ข้อสังเกตและบทเรียนสำคัญ (Developer Notes & Gotchas):**
/// 1. **การป้องกัน Theme กลบทับเงา Inset:**
///    - ใน Flutter หากแอปมีการตั้งค่า Global `inputDecorationTheme` เช่น `fillColor: Colors.white`
///      ตัว `TextField` จะดึงค่าสีขาวมาเททับระนาบ Canvas ของเราโดยอัตโนมัติ
///    - Widget นี้จึงตั้งค่า `filled: true` และ `fillColor: Colors.transparent` เสมอ
///      เพื่อให้มองทะลุเห็นเงาจมด้านใน (True Inset Shadow) ที่วาดด้วย [NeumorphicInsetPainter] 100%
/// 2. **มิติร่องลึก (Sunken Illusion):**
///    - ใช้ Base Gradient ไล่เฉดจากมุมบน-ซ้ายมืด `#D2D8E2` สู่ล่าง-ขวาสว่าง `#EBF0F6`
///    - ซ้อนเงามืดขอบบน-ซ้าย (`rgba(163, 177, 198, 0.90)`) และแสงสะท้อนขอบล่าง-ขวา
/// 3. **Active Cyan Glow:**
///    - เมื่อผู้ใช้แตะ Focus จะแสดงเส้นขอบสีฟ้าสว่าง (`NeumorphicTheme.accentCyan`)
///      พร้อมแสงสะท้อนรอบกล่อง (Cyan Glow) เลียนแบบดีไซน์ต้นฉบับ
class NeumorphicInputField extends StatefulWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String hintText;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool obscureText;
  final double height;
  final double borderRadius;
  final Color activeColor;

  const NeumorphicInputField({
    super.key,
    this.controller,
    this.focusNode,
    required this.hintText,
    this.prefixIcon,
    this.suffixIcon,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
    this.obscureText = false,
    this.height = 52.0,
    this.borderRadius = 16.0,
    this.activeColor = NeumorphicTheme.accentCyan,
  });

  @override
  State<NeumorphicInputField> createState() => _NeumorphicInputFieldState();
}

class _NeumorphicInputFieldState extends State<NeumorphicInputField> {
  late FocusNode _focusNode;
  bool _ownsFocusNode = false;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
    } else {
      _focusNode = FocusNode();
      _ownsFocusNode = true;
    }
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _handleFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isFocused = _focusNode.hasFocus;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        boxShadow: isFocused
            ? [
                BoxShadow(
                  color: widget.activeColor.withValues(alpha: 0.5),
                  blurRadius: 12,
                  spreadRadius: 1.5,
                ),
              ]
            : null,
      ),
      child: CustomPaint(
        painter: NeumorphicInsetPainter(
          borderRadius: widget.borderRadius,
          distance: 4.0,
          blur: 6.0,
          shadowDark: const Color.fromRGBO(163, 177, 198, 0.90),
          shadowLight: const Color.fromRGBO(255, 255, 255, 0.95),
          border: isFocused
              ? BorderSide(
                  color: widget.activeColor,
                  width: 2.0,
                )
              : BorderSide(
                  color: Colors.white.withValues(alpha: 0.7),
                  width: 1.0,
                ),
        ),
        child: SizedBox(
          height: widget.height,
          child: Center(
            child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              keyboardType: widget.keyboardType,
              textInputAction: widget.textInputAction,
              onSubmitted: widget.onSubmitted,
              onChanged: widget.onChanged,
              obscureText: widget.obscureText,
              style: const TextStyle(
                color: NeumorphicTheme.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                // ป้องกัน Theme จากการกลบทับเงา Inset ด้วยสีขาว
                filled: true,
                fillColor: Colors.transparent,
                hintText: widget.hintText,
                hintStyle: TextStyle(
                  color: NeumorphicTheme.textSecondary.withValues(alpha: 0.65),
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
                prefixIcon: widget.prefixIcon != null
                    ? Icon(
                        widget.prefixIcon,
                        color: isFocused
                            ? widget.activeColor
                            : NeumorphicTheme.textSecondary,
                        size: 22,
                      )
                    : null,
                suffixIcon: widget.suffixIcon,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
