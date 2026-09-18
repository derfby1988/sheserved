import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/features/community/find_buddies/data/fitness_buddies_repository.dart';
import 'package:sheserved/features/community/find_buddies/presentation/widgets/cost_editors.dart';

/// Phase 9.1: Session cost items editor (shared by create/edit session sheets).
/// Renders the editable line-item list, standard picker + custom add
/// buttons, and the estimated round total. [costItems] is mutated in
/// place; [refresh] must rebuild the enclosing sheet.
class SessionCostEditor extends StatelessWidget {
  final BuildContext sheetContext;
  final String groupId;
  final List<Map<String, dynamic>> costItems;
  final double Function() sessionHours;
  final VoidCallback refresh;
  final FitnessBuddiesRepository repo;

  const SessionCostEditor({
    super.key,
    required this.sheetContext,
    required this.groupId,
    required this.costItems,
    required this.sessionHours,
    required this.refresh,
    required this.repo,
  });

  @override
  Widget build(BuildContext context) {
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
                size: 16,
                color: AppColors.primaryDark,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'รายการค่าใช้จ่ายเฉพาะรอบ',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (costItems.isEmpty)
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
                  size: 18,
                  color: Colors.grey.shade500,
                ),
                const SizedBox(width: 8),
                Text(
                  'ไม่มีค่าใช้จ่ายเฉพาะรอบ (ไม่บังคับ)',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              ],
            ),
          )
        else
          for (var i = 0; i < costItems.length; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
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
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      costCategoryIcon(costItems[i]['category']?.toString()),
                      color: AppColors.primaryDark,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          costItems[i]['name']?.toString() ?? '',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          sessionCostItemSummary(costItems[i]),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        paymentTimingBadge(
                          costItems[i]['payment_timing']?.toString(),
                        ),
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
                        onPressed: () async {
                          final result = await showSessionCostItemEditor(
                            sheetContext,
                            existing: costItems[i],
                          );
                          if (result != null) {
                            costItems[i] = result;
                            refresh();
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 19,
                          color: Colors.redAccent,
                        ),
                        visualDensity: VisualDensity.compact,
                        tooltip: 'ลบ',
                        onPressed: () {
                          costItems.removeAt(i);
                          refresh();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryDark,
                  side: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.5),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                ),
                onPressed: () async {
                  List<Map<String, dynamic>> standards;
                  try {
                    standards = await repo.listGroupCostStandards(
                      groupId,
                      standardType: 'round_expense',
                      activeOnly: true,
                    );
                  } catch (_) {
                    standards = const [];
                  }
                  if (!sheetContext.mounted) return;
                  if (standards.isEmpty) {
                    ScaffoldMessenger.of(sheetContext).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'ก๊วนนี้ยังไม่มี template ค่าใช้จ่ายรอบ — '
                          'สร้างได้ในหน้าแก้ไขก๊วน',
                        ),
                      ),
                    );
                    return;
                  }
                  final standard = await showCostStandardPicker(
                    sheetContext,
                    standards,
                  );
                  if (standard == null || !sheetContext.mounted) return;
                  final result = await showSessionCostItemEditor(
                    sheetContext,
                    fromStandard: standard,
                    defaultHours:
                        standard['pricing_unit']?.toString() == 'per_hour'
                        ? sessionHours()
                        : null,
                  );
                  if (result != null) {
                    costItems.add(result);
                    refresh();
                  }
                },
                icon: const Icon(Icons.playlist_add_rounded, size: 18),
                label: const Text(
                  'เลือกจากแม่แบบ',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryDark,
                  side: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.5),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                ),
                onPressed: () async {
                  final result = await showSessionCostItemEditor(sheetContext);
                  if (result != null) {
                    costItems.add(result);
                    refresh();
                  }
                },
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text(
                  'เพิ่มค่าใช้จ่ายเอง',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
        if (costItems.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.28),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.receipt_long_rounded,
                      size: 20,
                      color: AppColors.primaryDark,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'ยอดประมาณการค่าใช้จ่ายของรอบ',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      '~${formatBaht(sessionCostItemsTotal(costItems.cast<Map<String, dynamic>>()))}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '(ยอดรวมของรอบ ไม่ใช่ยอดต่อคน — อิงเงื่อนไขการชำระตามรายการข้างต้น)',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
