import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';

/// Row of quick-filter chips: ตัวกรอง badge, ยังเปิดรับ, รัศมี,
/// เป็นสมาชิก, ก๊วนที่ดูแล.
class QuickFilterRow extends StatelessWidget {
  final bool filterOpenOnly;
  final bool filterJoinedOnly;
  final bool filterManagedOnly;
  final bool locationEnabled;
  final double? radiusKm;
  final int activeFilterCount;
  final String filterSummary;
  final void Function(String key) onToggleFilter;
  final VoidCallback onShowAdvancedFilter;

  const QuickFilterRow({
    super.key,
    required this.filterOpenOnly,
    required this.filterJoinedOnly,
    required this.filterManagedOnly,
    required this.locationEnabled,
    required this.radiusKm,
    required this.activeFilterCount,
    required this.filterSummary,
    required this.onToggleFilter,
    required this.onShowAdvancedFilter,
  });

  Widget _chip({
    required String key,
    required String label,
    required bool selected,
    required IconData icon,
    String? activeLabel,
  }) {
    final text = selected ? (activeLabel ?? label) : label;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        button: true,
        checked: selected,
        label: 'ตัวกรองก๊วน$text ${selected ? 'เปิดอยู่' : 'ปิดอยู่'}',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onToggleFilter(key),
            borderRadius: BorderRadius.circular(14),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? AppColors.primaryDark
                      : Colors.grey.shade300,
                  width: selected ? 1.6 : 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: selected
                        ? AppColors.primary.withValues(alpha: 0.2)
                        : Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 1.5),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: selected
                        ? AppColors.primaryDark
                        : Colors.grey.shade600,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    text,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected
                          ? AppColors.primaryDark
                          : Colors.grey.shade800,
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: AppColors.primaryDark,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasActiveFilter = activeFilterCount > 0;
    return SizedBox(
      height: 44,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Semantics(
                button: true,
                label: 'เปิดตัวกรองทั้งหมด $filterSummary',
                child: Tooltip(
                  message: filterSummary,
                  child: Badge(
                    isLabelVisible: hasActiveFilter,
                    offset: const Offset(-2, 2),
                    backgroundColor: AppColors.primaryDark,
                    label: Text(
                      '$activeFilterCount',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: onShowAdvancedFilter,
                        borderRadius: BorderRadius.circular(14),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 44,
                          height: 38,
                          decoration: BoxDecoration(
                            color: hasActiveFilter
                                ? AppColors.primary.withValues(alpha: 0.15)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: hasActiveFilter
                                  ? AppColors.primaryDark
                                  : Colors.grey.shade300,
                              width: hasActiveFilter ? 1.6 : 1.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: hasActiveFilter
                                    ? AppColors.primary.withValues(alpha: 0.2)
                                    : Colors.black.withValues(alpha: 0.04),
                                blurRadius: 4,
                                offset: const Offset(0, 1.5),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.tune_rounded,
                              size: 20,
                              color: AppColors.primaryDark,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _chip(
              key: 'open',
              label: 'ยังเปิดรับ',
              selected: filterOpenOnly,
              icon: Icons.lock_open_rounded,
            ),
            _chip(
              key: 'radius',
              label: 'รัศมี',
              activeLabel: 'รัศมี ${(radiusKm ?? 10).round()} กม.',
              selected: locationEnabled,
              icon: Icons.near_me_rounded,
            ),
            _chip(
              key: 'joined',
              label: 'เป็นสมาชิก',
              selected: filterJoinedOnly,
              icon: Icons.person_rounded,
            ),
            _chip(
              key: 'managed',
              label: 'ก๊วนที่ดูแล',
              selected: filterManagedOnly,
              icon: Icons.admin_panel_settings_rounded,
            ),
          ],
        ),
      ),
    );
  }
}
