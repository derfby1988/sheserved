import 'package:flutter/material.dart';

import 'neumorphic_container.dart';
import 'neumorphic_inset.dart';
import 'neumorphic_theme.dart';

/// ชุดโครงและคอนโทรลสำหรับ bottom sheet สไตล์ Neumorphic
///
/// **หลักการออกแบบ (Design Notes):**
/// - ทุก sheet ใช้โครงเดียวกันผ่าน [NeumorphicSheetShell]: drag handle, header
///   ที่มี badge ไอคอนนูน, เนื้อหาในแผงนูน (Raised Panel) และ footer ปุ่มกด
/// - ต้องตั้งค่า `backgroundColor: NeumorphicTheme.baseColor` ให้ `showModalBottomSheet`
///   เสมอ เพื่อให้เงาสองทิศทางของ Neumorphic เนียนตาตามคำแนะนำใน [NeumorphicTheme]
/// - คอนโทรลทั้งหมด (ชิป, สวิตช์, ปุ่ม) ใช้มิติจาก [NeumorphicContainer] และ
///   [NeumorphicInsetBox] โดยไม่แตะสีพื้นหลังของเนื้อหาข้างใน

/// โครง bottom sheet สไตล์ Neumorphic: drag handle, header (badge ไอคอน +
/// หัวข้อ + ปุ่มล้างทั้งหมด/ปิด) และแผงเนื้อหาแบบนูน.
class NeumorphicSheetShell extends StatelessWidget {
  const NeumorphicSheetShell({
    super.key,
    required this.title,
    this.icon = Icons.tune_rounded,
    this.onClearAll,
    this.clearAllLabel = 'ล้างทั้งหมด',
    this.onClose,
    this.children = const <Widget>[],
    this.footer,
    this.heightFactor = 0.9,
  });

  final String title;
  final IconData icon;
  final VoidCallback? onClearAll;
  final String clearAllLabel;
  final VoidCallback? onClose;
  final List<Widget> children;
  final Widget? footer;
  final double heightFactor;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: heightFactor,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        ),
        child: Column(
          children: [
            const NeumorphicSheetDragHandle(),
            const SizedBox(height: 12),
            _header,
            const SizedBox(height: 12),
            Expanded(
              child: NeumorphicContainer(
                borderRadius: 20,
                depth: 4,
                blur: 8,
                padding: const EdgeInsets.all(14),
                child: Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: Theme.of(context).colorScheme.copyWith(
                      primary: NeumorphicTheme.primaryBlue,
                    ),
                    sliderTheme: Theme.of(context).sliderTheme.copyWith(
                      activeTrackColor: NeumorphicTheme.primaryBlue,
                      thumbColor: NeumorphicTheme.primaryBlue,
                    ),
                  ),
                  child: ListView(padding: EdgeInsets.zero, children: children),
                ),
              ),
            ),
            if (footer != null) ...[const SizedBox(height: 12), footer!],
          ],
        ),
      ),
    );
  }

  Widget get _header {
    return Row(
      children: [
        NeumorphicContainer(
          width: 36,
          height: 36,
          shape: BoxShape.circle,
          depth: 3,
          blur: 6,
          child: Icon(icon, size: 18, color: NeumorphicTheme.primaryBlue),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: NeumorphicTheme.textPrimary,
            ),
          ),
        ),
        if (onClearAll != null)
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: NeumorphicTheme.primaryBlue,
            ),
            onPressed: onClearAll,
            child: Text(clearAllLabel),
          ),
        if (onClose != null) ...[
          const SizedBox(width: 4),
          NeumorphicSheetCloseButton(onPressed: onClose!),
        ],
      ],
    );
  }
}

/// แถบจับลาก (drag handle) มาตรฐานของ bottom sheet ในระบบ Neumorphic.
class NeumorphicSheetDragHandle extends StatelessWidget {
  const NeumorphicSheetDragHandle({
    super.key,
    this.width = 44,
    this.height = 5,
  });

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFD4DAE3),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(color: Colors.white, offset: Offset(0, 1), blurRadius: 1),
        ],
      ),
    );
  }
}

/// โครง bottom sheet สำหรับฟอร์มสั้น: สูงตามเนื้อหาและขยับหนีคีย์บอร์ด
///
/// ต่างจาก [NeumorphicSheetShell] ตรงที่ไม่ได้ล็อกความสูงที่ [NeumorphicSheetShell.heightFactor]
/// และไม่ครอบเนื้อหาด้วยแผงนูนทั้งก้อน — เหมาะกับ sheet ที่มีคอนโทรลไม่กี่กลุ่ม
/// (เช่น ฟอร์มขอนัด) โดยยังใช้ drag handle, badge ไอคอนนูน และปุ่มในระบบเดียวกัน
class NeumorphicFormSheetShell extends StatelessWidget {
  const NeumorphicFormSheetShell({
    super.key,
    required this.title,
    this.icon = Icons.tune_rounded,
    this.subtitle,
    this.onClose,
    this.children = const <Widget>[],
    this.footer,
  });

  final String title;
  final IconData icon;
  final String? subtitle;
  final VoidCallback? onClose;
  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(child: NeumorphicSheetDragHandle()),
            const SizedBox(height: 16),
            Row(
              children: [
                NeumorphicContainer(
                  width: 40,
                  height: 40,
                  shape: BoxShape.circle,
                  depth: 3,
                  blur: 6,
                  child: Icon(
                    icon,
                    size: 20,
                    color: NeumorphicTheme.primaryBlue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.2,
                          color: NeumorphicTheme.textPrimary,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: NeumorphicTheme.primaryBlue,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (onClose != null) ...[
                  const SizedBox(width: 8),
                  NeumorphicSheetCloseButton(onPressed: onClose!),
                ],
              ],
            ),
            const SizedBox(height: 16),
            ...children,
            if (footer != null) ...[const SizedBox(height: 16), footer!],
          ],
        ),
      ),
    );
  }
}

/// ปุ่มไอคอนวงกลมนูน (Raised) พร้อม tooltip — ใช้กับ action ใน header ของ sheet.
class NeumorphicIconButton extends StatelessWidget {
  const NeumorphicIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 36,
    this.iconSize = 18,
    this.color = NeumorphicTheme.textSecondary,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final double size;
  final double iconSize;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(size / 2),
        child: NeumorphicContainer(
          width: size,
          height: size,
          shape: BoxShape.circle,
          depth: 3,
          blur: 6,
          child: Icon(icon, size: iconSize, color: color),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// ปุ่มปิด sheet แบบวงกลมนูน พร้อม tooltip (ค่าเริ่มต้น "ปิด").
class NeumorphicSheetCloseButton extends StatelessWidget {
  const NeumorphicSheetCloseButton({
    super.key,
    required this.onPressed,
    this.tooltip = 'ปิด',
    this.size = 36,
  });

  final VoidCallback onPressed;
  final String tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    return NeumorphicIconButton(
      icon: Icons.close_rounded,
      tooltip: tooltip,
      size: size,
      onPressed: onPressed,
    );
  }
}

/// ชิปเลือกได้แบบนูน: ยกขึ้นเมื่อยังไม่เลือก และจมเป็นราง (Inset) เมื่อเลือก
///
/// **ข้อกำหนดด้านเลย์เอาต์:** เนื้อหา (ไอคอน + ข้อความ) เหมือนกันทั้งสองสถานะ
/// และไม่มีการเพิ่มเครื่องหมายถูกหรือเปลี่ยนน้ำหนักตัวอักษร เพื่อให้ความกว้าง
/// และความสูงของชิปเท่าเดิมเมื่อเลือก ชิปอื่นในแถวจึงไม่ถูกดันให้ขยับ
class NeumorphicChoiceChip extends StatelessWidget {
  const NeumorphicChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final accent = NeumorphicTheme.primaryBlue;
    const padding = EdgeInsets.symmetric(horizontal: 14, vertical: 9);
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(
            icon,
            size: 15,
            color: selected ? accent : NeumorphicTheme.textSecondary,
          ),
          const SizedBox(width: 6),
        ],
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? accent : NeumorphicTheme.textPrimary,
          ),
        ),
      ],
    );

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onSelected(!selected),
          borderRadius: BorderRadius.circular(14),
          child: selected
              ? NeumorphicInsetBox(
                  height: null,
                  borderRadius: 14,
                  padding: padding,
                  child: content,
                )
              : NeumorphicContainer(
                  borderRadius: 14,
                  depth: 5,
                  blur: 10,
                  padding: padding,
                  child: content,
                ),
        ),
      ),
    );
  }
}

/// ป้าย (tag) แบบนูนสำหรับค่าที่เพิ่มแล้ว พร้อมปุ่มลบได้.
class NeumorphicTagChip extends StatelessWidget {
  const NeumorphicTagChip({super.key, required this.label, this.onDeleted});

  final String label;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: NeumorphicContainer(
        borderRadius: 14,
        depth: 4,
        blur: 8,
        padding: EdgeInsets.only(
          left: 14,
          right: onDeleted == null ? 14 : 8,
          top: 6,
          bottom: 6,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: NeumorphicTheme.textPrimary,
              ),
            ),
            if (onDeleted != null) ...[
              const SizedBox(width: 4),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onDeleted,
                  borderRadius: BorderRadius.circular(10),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(
                      Icons.close_rounded,
                      size: 15,
                      color: NeumorphicTheme.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// สวิตช์เปิด/ปิดแบบนูน: รางจม (Inset) และปุ่มเลื่อนนูนที่เปลี่ยนเป็นสีฟ้าเมื่อเปิด.
class NeumorphicSwitchTile extends StatelessWidget {
  const NeumorphicSwitchTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return Semantics(
      container: true,
      toggled: value,
      enabled: enabled,
      label: title,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? () => onChanged!(!value) : null,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: enabled
                              ? NeumorphicTheme.textPrimary
                              : NeumorphicTheme.textSecondary.withValues(
                                  alpha: 0.7,
                                ),
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: NeumorphicTheme.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _toggle,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget get _toggle {
    return SizedBox(
      width: 54,
      height: 32,
      child: NeumorphicInsetBox(
        width: 54,
        height: 32,
        borderRadius: 16,
        padding: EdgeInsets.zero,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: NeumorphicContainer(
                  width: 24,
                  height: 24,
                  shape: BoxShape.circle,
                  depth: 2,
                  blur: 4,
                  color: value
                      ? NeumorphicTheme.primaryBlue
                      : NeumorphicTheme.baseColor,
                  child: value
                      ? const Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: Colors.white,
                        )
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ปุ่มทรงแคปซูลแบบนูน (รอง) สำหรับยกเลิกหรือปุ่มตัวเลือก เช่น วันที่/เวลา.
///
/// **กันข้อความล้น:** ป้ายในปุ่มย่อขนาดอัตโนมัติ (FittedBox) และความกว้างของ
/// แคปซูลถูกจำกัดไว้ไม่เกิน [maxWidth] (ค่าเริ่มต้น = ความกว้างจอลบระยะขอบ 16
/// ทั้งสองข้าง) ปุ่มจึงไม่ดันล้นจอแม้ถูกวางใน `Row` ที่ไม่จำกัดความกว้าง
class NeumorphicPillButton extends StatelessWidget {
  const NeumorphicPillButton({
    super.key,
    required this.text,
    this.onPressed,
    this.icon,
    this.active = false,
    this.height = 48,
    this.fontSize = 14.5,
    this.iconSize = 18,
    this.depth = 5,
    this.blur = 10,
    this.maxWidth,
    this.color,
  });

  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool active;
  final double height;

  /// สีไอคอน/ข้อความ — ใช้ทำปุ่มหลักที่ยังนูนอยู่ (ไม่ต้องพึ่ง [active]
  /// ซึ่งจะเปลี่ยนปุ่มเป็นร่องจม) ค่าเริ่มต้น: primaryBlue เมื่อ active,
  /// textSecondary เมื่อไม่ active
  final Color? color;

  /// ขนาดตัวอักษร — ลดลงได้เมื่อใช้เป็นปุ่มลิงก์ขนาดเล็กในบรรทัด
  final double fontSize;
  final double iconSize;

  /// ความหนาของเงา — ลดลงเมื่อทำปุ่มเตี้ย (เช่น height 32) เพื่อไม่ให้ดูหนัก
  final double depth;
  final double blur;

  /// เพดานความกว้างของแคปซูล — ค่าเริ่มต้นคือความกว้างหน้าจอลบ 32
  /// ส่งค่าที่แคบกว่าได้เมื่อปุ่มอยู่ในพื้นที่จำกัด (เช่น ครึ่งความกว้าง)
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final accent = NeumorphicTheme.primaryBlue;
    final enabled = onPressed != null;
    final labelColor =
        color ?? (active ? accent : NeumorphicTheme.textSecondary);
    final cap = maxWidth ?? MediaQuery.sizeOf(context).width - 32;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(height / 2),
          child: NeumorphicContainer(
            height: height,
            borderRadius: height / 2,
            depth: depth,
            blur: blur,
            isPressed: active,
            color: active
                ? Color.alphaBlend(
                    accent.withValues(alpha: 0.16),
                    NeumorphicTheme.baseColor,
                  )
                : NeumorphicTheme.baseColor,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: cap),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: iconSize, color: labelColor),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          text,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: fontSize,
                            fontWeight: FontWeight.w600,
                            color: labelColor,
                          ),
                        ),
                      ),
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
