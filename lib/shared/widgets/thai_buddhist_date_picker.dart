import 'package:flutter/material.dart';
import 'package:thai_buddhist_date/thai_buddhist_date.dart';
import 'package:thai_buddhist_date_pickers/thai_buddhist_date_pickers.dart';
import '../../core/constants/app_colors.dart';
import 'neumorphic/neumorphic_theme.dart';
import 'neumorphic/neumorphic_inset.dart';

/// ยูทิลิตี้สำหรับจัดการวันที่ไทย (พ.ศ.)
class ThaiDateUtils {
  static String formatShortDateBE(DateTime date) {
    return '${date.day} ${getThaiShortMonth(date.month)} ${date.year + 543}';
  }

  static String formatShortDateBE2Digit(DateTime date) {
    final beYear = (date.year + 543) % 100;
    return '${date.day} ${getThaiShortMonth(date.month)} $beYear';
  }

  static String formatFullDateBE(DateTime date) {
    return '${date.day} ${getThaiFullMonth(date.month)} พ.ศ. ${date.year + 543}';
  }

  static String getThaiShortMonth(int month) {
    const months = [
      'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
      'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'
    ];
    return (month >= 1 && month <= 12) ? months[month - 1] : '';
  }

  static String getThaiFullMonth(int month) {
    const months = [
      'มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน', 'พฤษภาคม', 'มิถุนายน',
      'กรกฎาคม', 'สิงหาคม', 'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม'
    ];
    return (month >= 1 && month <= 12) ? months[month - 1] : '';
  }

  static int daysInMonth(int year, int month) =>
      DateTime(year, month + 1, 0).day;
}

/// คอมโพเนนต์ช่องกรอกวันที่แบบไทย (พ.ศ.) ส่วนกลาง
/// รองรับ 2-Step Flow: เลือกปีก่อน -> เลือกวันในปฏิทิน (UX สูงสุด)
class ThaiBuddhistDatePickerField extends StatelessWidget {
  final DateTime? value;
  final String label;
  final String hint;
  final bool isRequired;
  final ValueChanged<DateTime> onDateSelected;
  final String? errorText;

  /// สีสำเนียงหลัก (กรอบ/ไอคอน/ปุ่มในปฏิทิน) — default เดิมคือ [AppColors.primary]
  final Color accentColor;

  /// แสดงผลเป็นร่องลึกแบบ Neumorphic Inset ให้เข้าชุดกับ [NeumorphicInputField]
  /// (หาก false จะเป็นกล่องสีขาวมนแบบเดิม)
  final bool useInsetStyle;

  const ThaiBuddhistDatePickerField({
    super.key,
    required this.value,
    required this.onDateSelected,
    this.label = 'วันเกิด',
    this.hint = 'เลือกวันที่',
    this.isRequired = false,
    this.errorText,
    this.accentColor = AppColors.primary,
    this.useInsetStyle = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasDate = value != null;
    final String displayText = hasDate
        ? ThaiDateUtils.formatShortDateBE(value!)
        : (isRequired ? '$label *' : label);

    final Color idleColor = useInsetStyle
        ? NeumorphicTheme.textSecondary
        : Colors.grey[400]!;
    final Widget fieldContent = Row(
      children: [
        Icon(
          Icons.calendar_today_outlined,
          color: errorText != null
              ? Colors.redAccent
              : (hasDate ? accentColor : idleColor),
          size: 22,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            displayText,
            style: TextStyle(
              color: hasDate ? accentColor : idleColor,
              fontSize: 15,
              fontWeight: hasDate ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
        if (hasDate)
          Icon(Icons.edit_calendar_outlined,
              color: accentColor.withValues(alpha: 0.5), size: 18),
      ],
    );

    final Widget field = useInsetStyle
        ? CustomPaint(
            painter: NeumorphicInsetPainter(
              borderRadius: 16,
              distance: 4.0,
              blur: 6.0,
              shadowDark: const Color.fromRGBO(163, 177, 198, 0.90),
              shadowLight: const Color.fromRGBO(255, 255, 255, 0.95),
              border: BorderSide(
                color: Colors.white.withValues(alpha: 0.7),
                width: 1.0,
              ),
            ),
            // ล็อกความสูง 52 พอดีกับ NeumorphicInputField เพื่อให้ทุกช่องสูงเท่ากัน
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.centerLeft,
              child: fieldContent,
            ),
          )
        : Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: errorText != null
                    ? Colors.redAccent
                    : (hasDate ? accentColor : Colors.grey[200]!),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: fieldContent,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => _handleTap(context),
          borderRadius:
              BorderRadius.circular(useInsetStyle ? 16 : 28),
          child: field,
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 4),
            child: Text(
              errorText!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Future<void> _handleTap(BuildContext context) async {
    final DateTime current = value ?? DateTime.now();

    // Step 1: เลือกปี พ.ศ.
    final int? selectedYear = await _showThaiYearPicker(context, current.year);
    if (selectedYear == null) return;

    // Step 2: เลือกในปฏิทิน
    final initialDate = DateTime(
      selectedYear,
      current.month,
      current.day.clamp(1, ThaiDateUtils.daysInMonth(selectedYear, current.month)),
    );

    if (!context.mounted) return;
    // เรียก dialog ผ่าน Theme override เพื่อให้ปุ่มตกลง/วันที่ที่เลือก
    // ใช้โทนสีเดียวกับ [accentColor] แทนสีจากธีมหลักของแอป
    final DateTime? picked = await showDialog<DateTime>(
      context: context,
      builder: (dialogContext) => Theme(
        data: Theme.of(dialogContext).copyWith(
          colorScheme: Theme.of(dialogContext)
              .colorScheme
              .copyWith(primary: accentColor),
          // ปุ่มยกเลิกเป็นสีเทา Slate ตามโทน Neumorphic (ไม่ใช้สี primary เขียว)
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: NeumorphicTheme.textSecondary,
            ),
          ),
        ),
        child: ThaiDatePickerDialog(
          initialDate: initialDate,
          firstDate: DateTime(1900),
          lastDate:
              DateTime.now().add(const Duration(days: 3650)), // อนุญาตให้เลือกอนาคตได้ 10 ปี
          era: Era.be,
          locale: 'th_TH',
        ),
      ),
    );

    if (picked != null) {
      onDateSelected(picked);
    }
  }

  Future<int?> _showThaiYearPicker(BuildContext context, int initialYearCE) async {
    final int currentYearBE = DateTime.now().year + 543;
    final int maxYearBE = currentYearBE + 10; // เผื่ออนาคต 10 ปี
    final int currentInitialBE = initialYearCE + 543;
    final int totalItems = maxYearBE - 2443 + 1;
    final int selectedIndex = maxYearBE - currentInitialBE;
    final int selectedRow = selectedIndex ~/ 3;

    final ScrollController scrollController = ScrollController();

    return await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, _) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (scrollController.hasClients && scrollController.position.maxScrollExtent > 0) {
              final int totalRows = (totalItems / 3).ceil();
              final double target = (selectedRow / totalRows.toDouble()) *
                  scrollController.position.maxScrollExtent;
              scrollController.animateTo(
                target.clamp(0.0, scrollController.position.maxScrollExtent),
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOut,
              );
            }
          });

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Icon(Icons.calendar_month, color: accentColor, size: 22),
                const SizedBox(width: 8),
                Text('เลือกปี พ.ศ.',
                    style: TextStyle(fontWeight: FontWeight.bold, color: accentColor)),
                const Spacer(),
                Text('(ระบุปีก่อน)',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500], fontWeight: FontWeight.normal)),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 300,
              child: Scrollbar(
                controller: scrollController,
                thumbVisibility: true,
                child: GridView.builder(
                  controller: scrollController,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 2,
                    crossAxisSpacing: 4,
                    mainAxisSpacing: 4,
                  ),
                  itemCount: totalItems,
                  itemBuilder: (_, index) {
                    final yearBE = maxYearBE - index;
                    final bool isSelected = yearBE == currentInitialBE;
                    return InkWell(
                      onTap: () => Navigator.pop(ctx, yearBE - 543),
                      borderRadius: BorderRadius.circular(10),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        decoration: BoxDecoration(
                          color: isSelected ? accentColor : null,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? accentColor
                                : accentColor.withValues(alpha: 0.2),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '$yearBE',
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.black87,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey)),
              ),
            ],
          );
        },
      ),
    );
  }
}
