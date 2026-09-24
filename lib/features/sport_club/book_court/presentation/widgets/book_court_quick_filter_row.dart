import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/feed/sport_club_filter_button.dart';

/// Quick-filter chips for Book Court:
/// ตัวกรอง badge, คอร์ทว่าง, รัศมี, เคยจองแล้ว, เป็นเจ้าของ.
class BookCourtQuickFilterRow extends StatelessWidget {
  final bool availableOnly;
  final bool bookedByMeOnly;
  final bool ownerOnly;
  final bool locationEnabled;
  final double? radiusKm;
  final int activeFilterCount;
  final String filterSummary;
  final void Function(String key) onToggleFilter;
  final VoidCallback onShowAdvancedFilter;

  const BookCourtQuickFilterRow({
    super.key,
    required this.availableOnly,
    required this.bookedByMeOnly,
    required this.ownerOnly,
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
        label: 'ตัวกรองสนาม$text ${selected ? 'เปิดอยู่' : 'ปิดอยู่'}',
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
                      fontWeight: selected
                          ? FontWeight.w600
                          : FontWeight.w500,
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
    return SizedBox(
      height: 44,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SportClubFilterButton(
                activeFilterCount: activeFilterCount,
                filterSummary: filterSummary,
                onTap: onShowAdvancedFilter,
              ),
            ),
            _chip(
              key: 'available',
              label: 'คอร์ทว่าง',
              selected: availableOnly,
              icon: Icons.event_available_rounded,
            ),
            _chip(
              key: 'radius',
              label: 'รัศมี',
              activeLabel: 'รัศมี ${(radiusKm ?? 10).round()} กม.',
              selected: locationEnabled,
              icon: Icons.near_me_rounded,
            ),
            _chip(
              key: 'bookedByMe',
              label: 'เคยจองแล้ว',
              selected: bookedByMeOnly,
              icon: Icons.history_rounded,
            ),
            _chip(
              key: 'owner',
              label: 'เป็นเจ้าของ',
              selected: ownerOnly,
              icon: Icons.storefront_rounded,
            ),
          ],
        ),
      ),
    );
  }
}
