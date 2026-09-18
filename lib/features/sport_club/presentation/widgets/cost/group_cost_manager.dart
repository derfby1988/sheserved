// The sheet-scoped `sheetContext` is intentionally passed to awaited
// editor dialogs; each call site guards with `ctx.mounted` first.
// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/features/community/find_buddies/data/fitness_buddies_repository.dart';
import 'package:sheserved/features/community/find_buddies/presentation/widgets/cost_editors.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/dialogs/sport_club_error_mapper.dart';

/// Group edit sheet: manages cost standards directly against the DB
/// (add / edit / disable-enable). Used standards keep their history —
/// the UI offers ปิดใช้งาน instead of deleting.
class GroupCostManager extends StatelessWidget {
  final BuildContext sheetContext;
  final String groupId;
  final String actorUserId;
  final List<Map<String, dynamic>> standards;
  final Future<void> Function() refresh;
  final FitnessBuddiesRepository repo;

  const GroupCostManager({
    super.key,
    required this.sheetContext,
    required this.groupId,
    required this.actorUserId,
    required this.standards,
    required this.refresh,
    required this.repo,
  });

  Future<void> _addFee() async {
    final result = await showGroupFeeEditor(sheetContext);
    if (result == null) return;
    try {
      await repo.createGroupCostStandard(
        groupId: groupId,
        actorUserId: actorUserId,
        standardType: 'group_fee',
        category: 'membership',
        name: result['name'].toString(),
        amount: (result['amount'] as num).toDouble(),
        billingPeriod: result['billing_period']?.toString(),
        paymentTiming: result['payment_timing'].toString(),
      );
      await refresh();
    } catch (e) {
      if (!sheetContext.mounted) return;
      ScaffoldMessenger.of(sheetContext).showSnackBar(
        SnackBar(content: Text('บันทึกไม่สำเร็จ: ${mapManagementError(e)}')),
      );
    }
  }

  Future<void> _addTemplate() async {
    final result = await showRoundExpenseTemplateEditor(sheetContext);
    if (result == null) return;
    try {
      await repo.createGroupCostStandard(
        groupId: groupId,
        actorUserId: actorUserId,
        standardType: 'round_expense',
        category: result['category'].toString(),
        name: result['name'].toString(),
        amount: (result['amount'] as num).toDouble(),
        pricingUnit: result['pricing_unit']?.toString(),
        defaultQuantity: (result['default_quantity'] as num?)?.toDouble() ?? 1,
        paymentTiming: result['payment_timing'].toString(),
      );
      await refresh();
    } catch (e) {
      if (!sheetContext.mounted) return;
      ScaffoldMessenger.of(sheetContext).showSnackBar(
        SnackBar(content: Text('บันทึกไม่สำเร็จ: ${mapManagementError(e)}')),
      );
    }
  }

  Future<void> _editStandard(Map<String, dynamic> standard) async {
    final isFee = standard['standard_type'] == 'group_fee';
    final ctx = sheetContext;
    if (!ctx.mounted) return;
    final result = isFee
        ? await showGroupFeeEditor(ctx, existing: standard)
        : await showRoundExpenseTemplateEditor(ctx, existing: standard);
    if (result == null) return;
    try {
      await repo.updateGroupCostStandard(
        standardId: standard['id'].toString(),
        actorUserId: actorUserId,
        name: result['name'].toString(),
        amount: (result['amount'] as num).toDouble(),
        billingPeriod: result['billing_period']?.toString(),
        pricingUnit: result['pricing_unit']?.toString(),
        defaultQuantity: (result['default_quantity'] as num?)?.toDouble(),
        paymentTiming: result['payment_timing']?.toString(),
      );
      await refresh();
    } catch (e) {
      if (!sheetContext.mounted) return;
      ScaffoldMessenger.of(sheetContext).showSnackBar(
        SnackBar(content: Text('บันทึกไม่สำเร็จ: ${mapManagementError(e)}')),
      );
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> standard) async {
    try {
      await repo.setGroupCostStandardActive(
        standardId: standard['id'].toString(),
        actorUserId: actorUserId,
        isActive: standard['is_active'] != true,
      );
      await refresh();
    } catch (e) {
      if (!sheetContext.mounted) return;
      ScaffoldMessenger.of(sheetContext).showSnackBar(
        SnackBar(content: Text('อัปเดตไม่สำเร็จ: ${mapManagementError(e)}')),
      );
    }
  }

  Widget _standardTile(Map<String, dynamic> s) {
    final isFee = s['standard_type'] == 'group_fee';
    final amount = formatBaht(s['amount'] as num?);
    final qty = (s['default_quantity'] as num?)?.toDouble() ?? 1;
    final qtyText = qty == qty.roundToDouble()
        ? qty.toInt().toString()
        : qty.toString();
    final unitPart = isFee
        ? billingPeriodLabel(s['billing_period']?.toString())
        : '${pricingUnitLabel(s['pricing_unit']?.toString())}'
              '${(s['pricing_unit'] == 'per_item' || s['pricing_unit'] == 'per_hour') ? ' × $qtyText' : ''}';
    final isActive = s['is_active'] != false;
    final cat = s['category']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isActive ? Colors.white : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? Colors.grey.shade200 : Colors.grey.shade300,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.primary.withValues(alpha: 0.12)
                  : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              costCategoryIcon(cat),
              color: isActive ? AppColors.primaryDark : Colors.grey.shade500,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s['name']?.toString() ?? '',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isActive ? null : Colors.grey.shade600,
                          decoration: isActive
                              ? null
                              : TextDecoration.lineThrough,
                        ),
                      ),
                    ),
                    if (!isActive)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'ปิดใช้งาน',
                          style: TextStyle(fontSize: 10, color: Colors.black54),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      amount,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isActive
                            ? AppColors.primaryDark
                            : Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      ' / $unitPart',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                paymentTimingBadge(s['payment_timing']?.toString()),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 19),
                color: Colors.grey.shade700,
                visualDensity: VisualDensity.compact,
                tooltip: 'แก้ไข',
                onPressed: () => _editStandard(s),
              ),
              IconButton(
                icon: Icon(
                  isActive
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 19,
                  color: isActive ? Colors.redAccent : Colors.teal,
                ),
                visualDensity: VisualDensity.compact,
                tooltip: isActive ? 'ปิดใช้งาน' : 'เปิดใช้งาน',
                onPressed: () => _toggleActive(s),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fees = standards
        .where((s) => s['standard_type'] == 'group_fee')
        .toList();
    final templates = standards
        .where((s) => s['standard_type'] == 'round_expense')
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.payments_outlined,
                size: 18,
                color: AppColors.primaryDark,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'ค่าใช้จ่ายมาตรฐานของก๊วน',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            const Icon(
              Icons.card_membership_rounded,
              size: 16,
              color: AppColors.primaryDark,
            ),
            const SizedBox(width: 6),
            const Text(
              'ค่าก๊วน / ค่าสมาชิก',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (fees.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: Colors.grey.shade500,
                ),
                const SizedBox(width: 8),
                Text(
                  'ยังไม่ได้กำหนดค่าก๊วน/ค่าสมาชิก',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          )
        else
          ...fees.map(_standardTile),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryDark,
              side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
            onPressed: _addFee,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text(
              'เพิ่มค่าก๊วน / ค่าสมาชิก',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 18),
        const Divider(height: 1),
        const SizedBox(height: 18),
        Row(
          children: [
            const Icon(
              Icons.sports_tennis_rounded,
              size: 16,
              color: AppColors.primaryDark,
            ),
            const SizedBox(width: 6),
            const Text(
              'Template ค่าใช้จ่ายรอบ',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (templates.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: Colors.grey.shade500,
                ),
                const SizedBox(width: 8),
                Text(
                  'ยังไม่ได้กำหนดแม่แบบค่าใช้จ่ายรอบ',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          )
        else
          ...templates.map(_standardTile),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryDark,
              side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
            onPressed: _addTemplate,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text(
              'เพิ่ม Template ค่าใช้จ่ายรอบ',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}
