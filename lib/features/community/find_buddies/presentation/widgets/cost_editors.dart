import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../../core/constants/app_colors.dart';

// ── Phase 9.1: shared labels / helpers for the two-level expense system ──

const Map<String, String> kCostCategoryLabels = {
  'membership': 'ค่าสมาชิก',
  'venue': 'สนาม',
  'equipment': 'อุปกรณ์',
  'coach': 'ครูฝึก',
  'insurance': 'ประกัน',
  'competition': 'ลงแข่ง',
  'uniform': 'ชุด',
  'other': 'อื่นๆ',
};

const Map<String, String> kBillingPeriodLabels = {
  'per_use': 'รายครั้ง',
  'per_day': 'รายวัน',
  'per_week': 'รายสัปดาห์',
  'per_month': 'รายเดือน',
  'per_year': 'รายปี',
  'lifetime': 'ตลอดชีพ',
};

const Map<String, String> kPricingUnitLabels = {
  'flat': 'เหมา',
  'per_item': 'ต่อชิ้น',
  'per_round': 'ต่อรอบ',
  'per_hour': 'ต่อชั่วโมง',
};

const Map<String, String> kPaymentTimingLabels = {
  'before_round_approval': 'ก่อนอนุมัติเข้าร่วมรอบ',
  'before_group_join': 'ก่อนเข้าร่วมก๊วน',
  'at_venue': 'จ่ายภายหลังที่สนาม',
};

const List<String> kRoundExpenseCategories = [
  'venue',
  'equipment',
  'coach',
  'insurance',
  'competition',
  'uniform',
  'other',
];

const List<String> kPaymentTimings = [
  'before_round_approval',
  'before_group_join',
  'at_venue',
];

String costCategoryLabel(String? v) => kCostCategoryLabels[v] ?? v ?? '-';
String billingPeriodLabel(String? v) => kBillingPeriodLabels[v] ?? v ?? '-';
String pricingUnitLabel(String? v) => kPricingUnitLabels[v] ?? v ?? '-';
String paymentTimingLabel(String? v) => kPaymentTimingLabels[v] ?? v ?? '-';

/// Returns a modern icon representing the cost category.
IconData costCategoryIcon(String? category) {
  switch (category) {
    case 'membership':
      return Icons.card_membership_rounded;
    case 'venue':
      return Icons.stadium_outlined;
    case 'equipment':
      return Icons.sports_tennis_rounded;
    case 'coach':
      return Icons.sports_rounded;
    case 'insurance':
      return Icons.shield_outlined;
    case 'competition':
      return Icons.emoji_events_outlined;
    case 'uniform':
      return Icons.checkroom_outlined;
    case 'other':
    default:
      return Icons.payments_outlined;
  }
}

/// Returns a modern icon representing the payment timing gate.
IconData paymentTimingIcon(String? timing) {
  switch (timing) {
    case 'before_round_approval':
      return Icons.how_to_reg_rounded;
    case 'before_group_join':
      return Icons.group_add_rounded;
    case 'at_venue':
    default:
      return Icons.storefront_rounded;
  }
}

/// Formats a baht amount, dropping decimals when the value is integral.
String formatBaht(num? value) {
  if (value == null) return '฿0';
  final d = value.toDouble();
  if (d == d.roundToDouble()) {
    return '฿${d.toInt()}';
  }
  return '฿${d.toStringAsFixed(2)}';
}

/// Estimated amount of one session cost item per plan rules:
/// flat/per_round → unit_amount (quantity is forced to 1),
/// per_item/per_hour → unit_amount × quantity.
double sessionCostItemEstimate(Map<String, dynamic> item) {
  final unit = (item['unit_amount'] as num?)?.toDouble() ?? 0;
  final qty = (item['quantity'] as num?)?.toDouble() ?? 1;
  return unit * qty;
}

double sessionCostItemsTotal(Iterable<Map<String, dynamic>> items) {
  var total = 0.0;
  for (final item in items) {
    total += sessionCostItemEstimate(item);
  }
  return total;
}

/// One-line summary for a session cost item, e.g.
/// "สนาม · ต่อชั่วโมง ฿200 × 1.5 ชม. = ~฿300"
String sessionCostItemSummary(Map<String, dynamic> item) {
  final unit = pricingUnitLabel(item['pricing_unit']?.toString());
  final qty = (item['quantity'] as num?)?.toDouble() ?? 1;
  final amount = (item['unit_amount'] as num?)?.toDouble() ?? 0;
  final estimate = sessionCostItemEstimate(item);
  final qtyText = qty == qty.roundToDouble()
      ? qty.toInt().toString()
      : qty.toString();
  return '${costCategoryLabel(item['category']?.toString())} · $unit '
      '${formatBaht(amount)} × $qtyText = ~${formatBaht(estimate)}';
}

/// Modern pill badge showing the payment timing condition with an icon.
Widget paymentTimingBadge(String? timing, {double fontSize = 11}) {
  final Color primaryColor;
  final Color bgColor;
  final IconData icon = paymentTimingIcon(timing);

  switch (timing) {
    case 'before_round_approval':
      primaryColor = const Color(0xFFD84315); // Deep orange
      bgColor = const Color(0xFFFFEBE5);
      break;
    case 'before_group_join':
      primaryColor = const Color(0xFF6A1B9A); // Deep purple
      bgColor = const Color(0xFFF3E5F5);
      break;
    case 'at_venue':
    default:
      primaryColor = const Color(0xFF00695C); // Deep teal
      bgColor = const Color(0xFFE0F2F1);
      break;
  }

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: primaryColor.withValues(alpha: 0.28),
        width: 0.8,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: fontSize + 2, color: primaryColor),
        const SizedBox(width: 4),
        Text(
          paymentTimingLabel(timing),
          style: TextStyle(
            fontSize: fontSize,
            color: primaryColor,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
      ],
    ),
  );
}

// ── Bottom-sheet editors ──

InputDecoration _fieldDecoration(
  String label, {
  IconData? prefixIcon,
  String? hintText,
  Widget? suffix,
}) => InputDecoration(
  labelText: label,
  hintText: hintText,
  prefixIcon: prefixIcon != null
      ? Icon(prefixIcon, size: 20, color: Colors.grey.shade600)
      : null,
  suffix: suffix,
  filled: true,
  fillColor: Colors.grey.shade50,
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: Colors.grey.shade300),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: Colors.grey.shade300),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: AppColors.primaryDark, width: 1.8),
  ),
  isDense: true,
  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
);

/// Parses a positive money amount (max 2 decimal places) from [raw].
/// Returns null when invalid.
double? _parseMoney(String raw) {
  final v = double.tryParse(raw.trim());
  if (v == null || v < 0 || v > 99999999.99) return null;
  if ((v * 100).roundToDouble() != (v * 100)) return null;
  return v;
}

Widget _buildTimingChips(String selected, void Function(String) onSelected) {
  return Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final timing in kPaymentTimings)
        ChoiceChip(
          avatar: Icon(
            paymentTimingIcon(timing),
            size: 16,
            color: selected == timing
                ? AppColors.primaryDark
                : Colors.grey.shade600,
          ),
          label: Text(
            paymentTimingLabel(timing),
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected == timing
                  ? FontWeight.w600
                  : FontWeight.normal,
              color: selected == timing
                  ? AppColors.primaryDark
                  : Colors.grey.shade800,
            ),
          ),
          selected: selected == timing,
          selectedColor: AppColors.primary.withValues(alpha: 0.18),
          backgroundColor: Colors.grey.shade100,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: selected == timing
                  ? AppColors.primaryDark
                  : Colors.grey.shade300,
              width: selected == timing ? 1.4 : 1,
            ),
          ),
          onSelected: (_) => onSelected(timing),
        ),
    ],
  );
}

/// Editor for a `group_fee` standard (ค่าก๊วน/ค่าสมาชิก).
/// Returns `{name, amount, billing_period, payment_timing}` or null.
Future<Map<String, dynamic>?> showGroupFeeEditor(
  BuildContext context, {
  Map<String, dynamic>? existing,
}) {
  final nameCtrl = TextEditingController(
    text: existing?['name']?.toString() ?? '',
  );
  final amountCtrl = TextEditingController(
    text: existing == null
        ? ''
        : ((existing['amount'] as num?)?.toString() ?? ''),
  );
  var billingPeriod = existing?['billing_period']?.toString() ?? 'per_month';
  var timing = existing?['payment_timing']?.toString() ?? 'at_venue';
  String? errorText;

  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) => SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 12,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.card_membership_rounded,
                        color: AppColors.primaryDark,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            existing == null
                                ? 'เพิ่มค่าก๊วน / ค่าสมาชิก'
                                : 'แก้ไขค่าก๊วน / ค่าสมาชิก',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'กำหนดค่าธรรมเนียมก๊วนหรือสมาชิกรายรอบ',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: nameCtrl,
                  maxLength: 100,
                  decoration: _fieldDecoration(
                    'ชื่อรายการ',
                    prefixIcon: Icons.edit_note_rounded,
                    hintText: 'เช่น ค่าสมาชิกก๊วนรายเดือน, ค่าบำรุงก๊วน',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,2}'),
                    ),
                  ],
                  decoration: _fieldDecoration(
                    'จำนวนเงิน (บาท)',
                    prefixIcon: Icons.payments_outlined,
                    hintText: '0.00',
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: billingPeriod,
                  decoration: _fieldDecoration(
                    'รอบเรียกเก็บ',
                    prefixIcon: Icons.timelapse_rounded,
                  ),
                  items: [
                    for (final e in kBillingPeriodLabels.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setSheetState(() => billingPeriod = v);
                    }
                  },
                ),
                const SizedBox(height: 16),
                const Text(
                  'เงื่อนไขการชำระ',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                _buildTimingChips(
                  timing,
                  (v) => setSheetState(() => timing = v),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          size: 18,
                          color: Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            errorText!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryDark,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    onPressed: () {
                      final name = nameCtrl.text.trim();
                      final amount = _parseMoney(amountCtrl.text);
                      if (name.isEmpty || name.length > 100) {
                        setSheetState(
                          () =>
                              errorText = 'กรุณาระบุชื่อรายการ (≤100 ตัวอักษร)',
                        );
                        return;
                      }
                      if (amount == null || amount <= 0) {
                        setSheetState(
                          () => errorText =
                              'จำนวนเงินต้องมากกว่า 0 และทศนิยมไม่เกิน 2 ตำแหน่ง',
                        );
                        return;
                      }
                      Navigator.pop(ctx, {
                        'name': name,
                        'amount': amount,
                        'billing_period': billingPeriod,
                        'payment_timing': timing,
                      });
                    },
                    icon: const Icon(Icons.check_circle_outline, size: 20),
                    label: const Text(
                      'บันทึกค่าก๊วน',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
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
  );
}

/// Editor for a `round_expense` standard (template ค่าใช้จ่ายรอบ).
/// Returns `{name, category, amount, pricing_unit, default_quantity,
/// payment_timing}` or null.
Future<Map<String, dynamic>?> showRoundExpenseTemplateEditor(
  BuildContext context, {
  Map<String, dynamic>? existing,
}) {
  final nameCtrl = TextEditingController(
    text: existing?['name']?.toString() ?? '',
  );
  final amountCtrl = TextEditingController(
    text: existing == null
        ? ''
        : ((existing['amount'] as num?)?.toString() ?? ''),
  );
  final qtyCtrl = TextEditingController(
    text: existing == null
        ? '1'
        : ((existing['default_quantity'] as num?)?.toString() ?? '1'),
  );
  var category = existing?['category']?.toString() ?? 'venue';
  var unit = existing?['pricing_unit']?.toString() ?? 'flat';
  var timing = existing?['payment_timing']?.toString() ?? 'at_venue';
  String? errorText;

  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) {
        final qtyEditable = unit == 'per_item' || unit == 'per_hour';
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 12,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.16),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          costCategoryIcon(category),
                          color: AppColors.primaryDark,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              existing == null
                                  ? 'เพิ่ม Template ค่าใช้จ่ายรอบ'
                                  : 'แก้ไข Template ค่าใช้จ่ายรอบ',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'ใช้เป็นแม่แบบให้เลือกใส่รอบนัดได้สะดวกรวดเร็ว',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: nameCtrl,
                    maxLength: 100,
                    decoration: _fieldDecoration(
                      'ชื่อรายการ',
                      prefixIcon: Icons.edit_note_rounded,
                      hintText: 'เช่น ค่าคอร์ทแบดมินตัน, ค่าลูกแบด, ค่าโค้ช',
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: _fieldDecoration(
                      'หมวดค่าใช้จ่าย',
                      prefixIcon: costCategoryIcon(category),
                    ),
                    items: [
                      for (final c in kRoundExpenseCategories)
                        DropdownMenuItem(
                          value: c,
                          child: Row(
                            children: [
                              Icon(
                                costCategoryIcon(c),
                                size: 18,
                                color: Colors.grey.shade700,
                              ),
                              const SizedBox(width: 8),
                              Text(costCategoryLabel(c)),
                            ],
                          ),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) setSheetState(() => category = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: unit,
                          decoration: _fieldDecoration('หน่วยคิด'),
                          items: [
                            for (final e in kPricingUnitLabels.entries)
                              DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value),
                              ),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setSheetState(() {
                              unit = v;
                              if (unit == 'flat' || unit == 'per_round') {
                                qtyCtrl.text = '1';
                              }
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: amountCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d{0,2}'),
                            ),
                          ],
                          decoration: _fieldDecoration(
                            'ยอดเงินต่อหน่วย',
                            prefixIcon: Icons.payments_outlined,
                            hintText: '0.00',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: qtyCtrl,
                    enabled: qtyEditable,
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: unit == 'per_hour',
                    ),
                    inputFormatters: unit == 'per_item'
                        ? [FilteringTextInputFormatter.digitsOnly]
                        : [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d{0,2}'),
                            ),
                          ],
                    decoration: _fieldDecoration(
                      qtyEditable ? 'จำนวนเริ่มต้น' : 'จำนวน (คงที่ 1)',
                      prefixIcon: Icons.pin_outlined,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'เงื่อนไขการชำระ',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  _buildTimingChips(
                    timing,
                    (v) => setSheetState(() => timing = v),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            size: 18,
                            color: Colors.red,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              errorText!,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryDark,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () {
                        final name = nameCtrl.text.trim();
                        final amount = _parseMoney(amountCtrl.text);
                        final qty = double.tryParse(qtyCtrl.text.trim());
                        if (name.isEmpty || name.length > 100) {
                          setSheetState(
                            () => errorText =
                                'กรุณาระบุชื่อรายการ (≤100 ตัวอักษร)',
                          );
                          return;
                        }
                        if (amount == null || amount <= 0) {
                          setSheetState(
                            () => errorText =
                                'จำนวนเงินต้องมากกว่า 0 และทศนิยมไม่เกิน 2 ตำแหน่ง',
                          );
                          return;
                        }
                        if (qty == null || qty <= 0) {
                          setSheetState(() => errorText = 'จำนวนต้องมากกว่า 0');
                          return;
                        }
                        if (unit == 'per_item' && qty != qty.roundToDouble()) {
                          setSheetState(
                            () => errorText = 'หน่วยต่อชิ้นต้องเป็นจำนวนเต็ม',
                          );
                          return;
                        }
                        Navigator.pop(ctx, {
                          'name': name,
                          'category': category,
                          'amount': amount,
                          'pricing_unit': unit,
                          'default_quantity':
                              (unit == 'flat' || unit == 'per_round')
                              ? 1.0
                              : qty,
                          'payment_timing': timing,
                        });
                      },
                      icon: const Icon(Icons.check_circle_outline, size: 20),
                      label: const Text(
                        'บันทึก Template',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// Editor for a session cost line item. Pass [fromStandard] to prefill from a
/// `round_expense` standard (keeps `standard_id` + `source_type='standard'`),
/// or [existing] to edit an item. [defaultHours] prefills quantity when the
/// unit is per_hour (admin still sees and confirms the value before saving).
Future<Map<String, dynamic>?> showSessionCostItemEditor(
  BuildContext context, {
  Map<String, dynamic>? existing,
  Map<String, dynamic>? fromStandard,
  double? defaultHours,
}) {
  final source = existing ?? fromStandard;
  final standardId = existing != null
      ? existing['standard_id']?.toString()
      : fromStandard?['id']?.toString();
  final sourceType = standardId != null ? 'standard' : 'custom';

  final nameCtrl = TextEditingController(
    text: source?['name']?.toString() ?? '',
  );
  final amountCtrl = TextEditingController(
    text: source == null
        ? ''
        : ((source['unit_amount'] ?? source['amount']) as num?)?.toString() ??
              '',
  );
  var category = source?['category']?.toString() ?? 'venue';
  var unit = source?['pricing_unit']?.toString() ?? 'flat';
  var timing = source?['payment_timing']?.toString() ?? 'at_venue';
  final initialQty =
      (source?['quantity'] ?? source?['default_quantity']) as num?;
  final qtyCtrl = TextEditingController(
    text: unit == 'per_hour' && defaultHours != null && existing == null
        ? (defaultHours == defaultHours.roundToDouble()
              ? defaultHours.toInt().toString()
              : defaultHours.toStringAsFixed(1))
        : (initialQty?.toString() ?? '1'),
  );
  final noteCtrl = TextEditingController(
    text: existing?['note']?.toString() ?? '',
  );
  String? errorText;

  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) {
        final qtyEditable = unit == 'per_item' || unit == 'per_hour';
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 12,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.16),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          costCategoryIcon(category),
                          color: AppColors.primaryDark,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              existing != null
                                  ? 'แก้ไขรายการค่าใช้จ่ายรอบ'
                                  : 'เพิ่มรายการค่าใช้จ่ายรอบ',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              standardId != null
                                  ? 'อ้างอิงจากแม่แบบก๊วน (Snapshot เฉพาะรอบนี้)'
                                  : 'รายการกำหนดเองเฉพาะรอบนี้',
                              style: TextStyle(
                                fontSize: 12,
                                color: standardId != null
                                    ? AppColors.primaryDark
                                    : Colors.grey.shade600,
                                fontWeight: standardId != null
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: nameCtrl,
                    maxLength: 100,
                    decoration: _fieldDecoration(
                      'ชื่อรายการ',
                      prefixIcon: Icons.edit_note_rounded,
                      hintText: 'เช่น ค่าสนาม, ค่าอุปกรณ์, ค่าโค้ช',
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: _fieldDecoration(
                      'หมวดค่าใช้จ่าย',
                      prefixIcon: costCategoryIcon(category),
                    ),
                    items: [
                      for (final c in kRoundExpenseCategories)
                        DropdownMenuItem(
                          value: c,
                          child: Row(
                            children: [
                              Icon(
                                costCategoryIcon(c),
                                size: 18,
                                color: Colors.grey.shade700,
                              ),
                              const SizedBox(width: 8),
                              Text(costCategoryLabel(c)),
                            ],
                          ),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) setSheetState(() => category = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: unit,
                          decoration: _fieldDecoration('หน่วยคิด'),
                          items: [
                            for (final e in kPricingUnitLabels.entries)
                              DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value),
                              ),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setSheetState(() {
                              unit = v;
                              if (unit == 'flat' || unit == 'per_round') {
                                qtyCtrl.text = '1';
                              }
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: amountCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d{0,2}'),
                            ),
                          ],
                          decoration: _fieldDecoration(
                            'ยอดเงินต่อหน่วย',
                            prefixIcon: Icons.payments_outlined,
                            hintText: '0.00',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: qtyCtrl,
                    enabled: qtyEditable,
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: unit == 'per_hour',
                    ),
                    inputFormatters: unit == 'per_item'
                        ? [FilteringTextInputFormatter.digitsOnly]
                        : [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d{0,2}'),
                            ),
                          ],
                    decoration: _fieldDecoration(
                      unit == 'per_item'
                          ? 'จำนวน (ชิ้น)'
                          : unit == 'per_hour'
                          ? 'จำนวนชั่วโมง'
                          : 'จำนวน (คงที่ 1)',
                      prefixIcon: Icons.pin_outlined,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: noteCtrl,
                    maxLength: 200,
                    decoration: _fieldDecoration(
                      'หมายเหตุรายการ (ไม่บังคับ)',
                      prefixIcon: Icons.chat_bubble_outline_rounded,
                      hintText: 'เช่น รวมลูกแบด 2 หลอด',
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'เงื่อนไขการชำระ',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  _buildTimingChips(
                    timing,
                    (v) => setSheetState(() => timing = v),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 18,
                          color: AppColors.primaryDark,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'ราคาที่ระบุเป็นยอดรวมของรายการนี้สำหรับทั้งรอบ (ไม่ใช่ยอดต่อคน)',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            size: 18,
                            color: Colors.red,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              errorText!,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryDark,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () {
                        final name = nameCtrl.text.trim();
                        final amount = _parseMoney(amountCtrl.text);
                        final qty = double.tryParse(qtyCtrl.text.trim());
                        if (name.isEmpty || name.length > 100) {
                          setSheetState(
                            () => errorText =
                                'กรุณาระบุชื่อรายการ (≤100 ตัวอักษร)',
                          );
                          return;
                        }
                        if (amount == null || amount <= 0) {
                          setSheetState(
                            () => errorText =
                                'จำนวนเงินต้องมากกว่า 0 และทศนิยมไม่เกิน 2 ตำแหน่ง',
                          );
                          return;
                        }
                        if (qty == null || qty <= 0) {
                          setSheetState(() => errorText = 'จำนวนต้องมากกว่า 0');
                          return;
                        }
                        if (unit == 'per_item' && qty != qty.roundToDouble()) {
                          setSheetState(
                            () => errorText = 'หน่วยต่อชิ้นต้องเป็นจำนวนเต็ม',
                          );
                          return;
                        }
                        Navigator.pop(ctx, {
                          'standard_id': standardId,
                          'source_type': sourceType,
                          'name': name,
                          'category': category,
                          'pricing_unit': unit,
                          'unit_amount': amount,
                          'quantity': (unit == 'flat' || unit == 'per_round')
                              ? 1.0
                              : qty,
                          'payment_timing': timing,
                          if (noteCtrl.text.trim().isNotEmpty)
                            'note': noteCtrl.text.trim(),
                        });
                      },
                      icon: const Icon(Icons.check_circle_outline, size: 20),
                      label: const Text(
                        'บันทึกรายการ',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// Picker listing active `round_expense` standards; returns the chosen
/// standard row or null.
Future<Map<String, dynamic>?> showCostStandardPicker(
  BuildContext context,
  List<Map<String, dynamic>> standards,
) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.65,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.playlist_add_check_rounded,
                      color: AppColors.primaryDark,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'เลือกจากแม่แบบค่าใช้จ่ายก๊วน',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (standards.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.receipt_long_outlined,
                          size: 48,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'ยังไม่มีแม่แบบค่าใช้จ่ายของก๊วนนี้',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: standards.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final s = standards[i];
                      final unit = s['pricing_unit']?.toString();
                      final qty =
                          (s['default_quantity'] as num?)?.toDouble() ?? 1;
                      final qtyText = qty == qty.roundToDouble()
                          ? qty.toInt().toString()
                          : qty.toString();
                      final cat = s['category']?.toString();
                      final amount = (s['amount'] as num?)?.toDouble() ?? 0;

                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade200),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => Navigator.pop(ctx, s),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      costCategoryIcon(cat),
                                      color: AppColors.primaryDark,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          s['name']?.toString() ?? '',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${costCategoryLabel(cat)} · ${pricingUnitLabel(unit)} '
                                          '${formatBaht(amount)}'
                                          '${(unit == 'per_item' || unit == 'per_hour') ? ' × $qtyText' : ''}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  paymentTimingBadge(
                                    s['payment_timing']?.toString(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
