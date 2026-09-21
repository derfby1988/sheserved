import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'neumorphic_theme.dart';
import 'neumorphic_inset.dart';

/// ช่องกรอกรหัส OTP แบบกล่องแยกสไตล์ Neumorphic ตามดีไซน์ภาพตัวอย่าง
///
/// **คุณสมบัติ:**
/// - กล่องแต่ละช่องเป็นสไตล์ Neumorphic ยกนูน (Raised) นุ่มตา
/// - กล่องตำแหน่งที่กำลังกรอกหรือเลือกอยู่ (Active Box) จะมีขอบเรืองแสงสีฟ้า (Cyan Glow) ตามแบบในรูป
/// - รองรับ Autofill สำหรับ SMS OTP (`AutofillHints.oneTimeCode`)
/// - รองรับการแตะเพื่อ Focus หรือ Paste รหัส 6 หลักได้ทันที
///
/// **ข้อสังเกตสำหรับผู้ใช้งาน (Developer Note):**
/// - กล่อง OTP ถูกออกแบบมาให้อยู่บนพื้นหลัง `#E7EBF0` เพื่อให้เห็นเงาสองชั้น (สว่าง/มืด) ชัดเจน
/// - เมื่อผู้ใช้กรอกครบ [length] หลัก จะเรียก callback [onCompleted] ทันที
class NeumorphicOtpField extends StatefulWidget {
  final int length;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onCompleted;
  final bool autoFocus;
  final double boxWidth;
  final double boxHeight;
  final double borderRadius;
  final double spacing;

  const NeumorphicOtpField({
    super.key,
    this.length = 6,
    this.controller,
    this.focusNode,
    this.onChanged,
    this.onCompleted,
    this.autoFocus = false,
    this.boxWidth = 44.0,
    this.boxHeight = 54.0,
    this.borderRadius = 16.0,
    this.spacing = 8.0,
  });

  @override
  State<NeumorphicOtpField> createState() => _NeumorphicOtpFieldState();
}

class _NeumorphicOtpFieldState extends State<NeumorphicOtpField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = TextEditingController();
      _ownsController = true;
    }

    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
    } else {
      _focusNode = FocusNode();
      _ownsFocusNode = true;
    }

    _controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    if (_ownsController) _controller.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _controller.text;
    widget.onChanged?.call(text);
    if (text.length == widget.length) {
      widget.onCompleted?.call(text);
    }
    setState(() {});
  }

  void _onFocusChanged() {
    setState(() {});
  }

  void _focus() {
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = _controller.text;
    final isFocused = _focusNode.hasFocus;
    // หา index ของกล่องที่กำลัง active (โฟกัสอยู่และยังไม่เต็ม หรือถ้าเต็มแล้วให้กล่องสุดท้าย)
    final activeIndex = text.length >= widget.length ? widget.length - 1 : text.length;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _focus,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // คำนวณขนาดกล่องอัตโนมัติให้พอดีความกว้างที่มี (กัน RIGHT OVERFLOW บนจอ/dialog แคบ)
          double boxWidth = widget.boxWidth;
          final double totalWidth =
              widget.length * (boxWidth + widget.spacing);
          if (constraints.maxWidth.isFinite &&
              totalWidth > constraints.maxWidth) {
            boxWidth = (constraints.maxWidth / widget.length) - widget.spacing;
            boxWidth = boxWidth.clamp(28.0, widget.boxWidth);
          }

          return Stack(
            alignment: Alignment.center,
            children: [
              // แถวของกล่อง Neumorphic 6 กล่อง
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.length, (index) {
                  final bool hasValue = index < text.length;
                  final String char = hasValue ? text[index] : '';
                  final bool isActive = isFocused && index == activeIndex;

                  return Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: widget.spacing / 2),
                    child: _buildOtpBox(
                      value: char,
                      isActive: isActive,
                      hasValue: hasValue,
                      boxWidth: boxWidth,
                    ),
                  );
                }),
              ),

              // ซ่อน TextField ตัวจริงไว้รับ Keyboard / Autofill
              Positioned.fill(
                child: Align(
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: 1,
                    height: 1,
                    child: Opacity(
                      opacity: 0.01,
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        autofocus: widget.autoFocus,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        enableSuggestions: false,
                        autocorrect: false,
                        showCursor: false,
                        cursorColor: Colors.transparent,
                        maxLines: 1,
                        style: const TextStyle(
                          color: Colors.transparent,
                          fontSize: 1,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          counterText: '',
                          isCollapsed: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(widget.length),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildOtpBox({
    required String value,
    required bool isActive,
    required bool hasValue,
    required double boxWidth,
  }) {
    return NeumorphicInsetBox(
      width: boxWidth,
      height: widget.boxHeight,
      borderRadius: widget.borderRadius,
      distance: 3.5,
      blur: 5.5,
      shadowDark: const Color.fromRGBO(163, 177, 198, 0.70),
      shadowLight: const Color.fromRGBO(255, 255, 255, 0.95),
      border: isActive
          ? const BorderSide(
              color: NeumorphicTheme.accentCyan,
              width: 2.0,
            )
          : BorderSide(
              color: Colors.white.withValues(alpha: 0.6),
              width: 1.0,
            ),
      outerGlowShadows: isActive
          ? [
              BoxShadow(
                color: NeumorphicTheme.accentCyan.withValues(alpha: 0.55),
                blurRadius: 10,
                spreadRadius: 1.5,
              ),
            ]
          : null,
      child: Center(
        child: Text(
          value,
          style: TextStyle(
            color: isActive
                ? const Color(0xFF0284C7)
                : NeumorphicTheme.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.bold,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}
