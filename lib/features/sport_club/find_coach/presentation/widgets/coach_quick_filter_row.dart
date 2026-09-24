import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/feed/sport_club_filter_button.dart';

/// Quick-filter chips for Find Coach:
/// ตัวกรอง badge, ยืนยันตัวตน, มีตารางว่าง, รัศมี.
class CoachQuickFilterRow extends StatelessWidget {
  final bool verifiedOnly;
  final bool availableOnly;
  final bool locationEnabled;
  final double? radiusKm;
  final int activeFilterCount;
  final String filterSummary;
  final void Function(String key) onToggleFilter;
  final VoidCallback onShowAdvancedFilter;

  const CoachQuickFilterRow({
    super.key,
    required this.verifiedOnly,
    required this.availableOnly,
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
        label: 'ตัวกรองโค้ช$text ${selected ? 'เปิดอยู่' : 'ปิดอยู่'}',
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
              key: 'verified',
              label: 'ยืนยันตัวตน',
              selected: verifiedOnly,
              icon: Icons.verified_rounded,
            ),
            _chip(
              key: 'available',
              label: 'มีตารางว่าง',
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
          ],
        ),
      ),
    );
  }
}
